import Foundation

struct NeuralTTSRuntimeStatus: Equatable {
    let isRuntimeAvailable: Bool
    let modelPath: String?
    let summary: String
}

@MainActor
final class NeuralTTSRuntime {
    static let shared = NeuralTTSRuntime()

    private let fileManager = FileManager.default
    private var cancellation = NeuralTTSCancellation()
    private var helperProcess: Process?
    private var helperInputPipe: Pipe?
    private var helperOutputPipe: Pipe?
    private var helperErrorPipe: Pipe?
    private var helperOutputBuffer = Data()
    private var helperContinuations: [String: CheckedContinuation<ResidentHelperResponse, Error>] = [:]
    private let voiceInstruction = "Speak in Brazilian Portuguese with a neutral, natural Brazilian accent. Calm, confident masculine AI assistant voice. Smooth delivery, no exaggerated emotion, not robotic."

    var modelDirectoryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("JARVIS", isDirectory: true)
            .appendingPathComponent("TTSKit", isDirectory: true)
    }

    func status() -> NeuralTTSRuntimeStatus {
        let modelPath = discoverModelPath()?.path
        if helperProcess?.isRunning == true {
            return NeuralTTSRuntimeStatus(
                isRuntimeAvailable: true,
                modelPath: modelPath,
                summary: "TTSKit helper residente ativo"
            )
        }

        if helperExecutableURL() != nil {
            return NeuralTTSRuntimeStatus(
                isRuntimeAvailable: true,
                modelPath: modelPath,
                summary: "TTSKit helper pronto para modo residente"
            )
        }

        return NeuralTTSRuntimeStatus(
            isRuntimeAvailable: false,
            modelPath: modelPath,
            summary: "TTSKit helper nao encontrado no bundle"
        )
    }

    func speak(_ text: String, localeID: String, voiceID: String) async throws {
        let clean = Self.stripEmoji(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            throw NeuralTTSError.emptyText
        }

        stopCurrentPlayback()
        let currentCancellation = NeuralTTSCancellation()
        cancellation = currentCancellation

        guard let helperURL = helperExecutableURL() else {
            throw NeuralTTSError.runtimeUnavailable("TTSKit helper nao encontrado no bundle")
        }

        try await runResidentCommand(
            helperURL: helperURL,
            action: "speak",
            text: clean,
            localeID: localeID,
            voiceID: voiceID,
            timeoutSeconds: min(max(Double(clean.count) / 7.0, 15.0), 240.0),
            cancellation: currentCancellation
        )
    }

    func prepare(localeID: String, voiceID: String) async {
        guard let helperURL = helperExecutableURL() else {
            return
        }

        do {
            try await runResidentCommand(
                helperURL: helperURL,
                action: "prepare",
                text: nil,
                localeID: localeID,
                voiceID: voiceID,
                timeoutSeconds: 45
            )
            DiagnosticsFileLog.shared.log(
                category: "tts",
                event: "neural_helper_resident_ready",
                fields: ["locale": localeID, "voice": voiceID]
            )
        } catch {
            DiagnosticsFileLog.shared.log(
                category: "tts",
                event: "neural_helper_resident_prepare_failed",
                fields: ["error": error.localizedDescription]
            )
        }
    }

    func stop() {
        stopCurrentPlayback()
    }

    func ensureModelDirectory() throws -> URL {
        try fileManager.createDirectory(at: modelDirectoryURL, withIntermediateDirectories: true)
        return modelDirectoryURL
    }

    private func stopCurrentPlayback() {
        cancellation.cancel()
        sendStopToResidentHelper()
    }

    private func discoverModelPath() -> URL? {
        if let bundled = Bundle.main.url(forResource: "TTSKit", withExtension: nil),
           containsModelFiles(at: bundled) {
            return bundled
        }

        let dir = modelDirectoryURL
        if containsModelFiles(at: dir) {
            return dir
        }

        return nil
    }

    private func helperExecutableURL() -> URL? {
        let candidates = [
            Bundle.main.executableURL?
                .deletingLastPathComponent()
                .appendingPathComponent("JarvisTTSHelper"),
            Bundle.main.url(forAuxiliaryExecutable: "JarvisTTSHelper")
        ].compactMap { $0 }

        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private func runResidentCommand(
        helperURL: URL,
        action: String,
        text: String?,
        localeID: String,
        voiceID: String,
        timeoutSeconds: Double,
        cancellation: NeuralTTSCancellation? = nil
    ) async throws {
        try ensureResidentHelper(helperURL: helperURL)
        let id = UUID().uuidString
        let command = ResidentHelperCommand(
            id: id,
            action: action,
            text: text,
            locale: localeID,
            voice: voiceID,
            modelDir: modelDirectoryURL.path,
            instruction: voiceInstruction
        )
        let data = try Self.encodeLine(command)
        let timeoutNanoseconds = UInt64(timeoutSeconds * 1_000_000_000)

        let response: ResidentHelperResponse = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                helperContinuations[id] = continuation
                do {
                    try helperInputPipe?.fileHandleForWriting.write(contentsOf: data)
                } catch {
                    helperContinuations.removeValue(forKey: id)
                    continuation.resume(throwing: error)
                    return
                }

                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    await MainActor.run {
                        guard let self, let pending = self.helperContinuations.removeValue(forKey: id) else {
                            return
                        }
                        pending.resume(throwing: NeuralTTSError.runtimeUnavailable("TTSKit helper residente excedeu timeout"))
                    }
                }

                if let cancellation {
                    Task { [weak self] in
                        while !Task.isCancelled {
                            if cancellation.isCancelled {
                                await MainActor.run {
                                    self?.sendStopToResidentHelper()
                                }
                                return
                            }
                            try? await Task.sleep(nanoseconds: 80_000_000)
                        }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in
                self.helperContinuations.removeValue(forKey: id)?.resume(throwing: NeuralTTSError.cancelled)
                self.sendStopToResidentHelper()
            }
        }

        switch response.status {
        case "ok":
            return
        case "cancelled":
            throw NeuralTTSError.cancelled
        default:
            throw NeuralTTSError.runtimeUnavailable(response.error ?? "TTSKit helper residente falhou")
        }
    }

    private func ensureResidentHelper(helperURL: URL) throws {
        if helperProcess?.isRunning == true {
            return
        }

        completeAllPending(with: NeuralTTSError.runtimeUnavailable("TTSKit helper residente reiniciado"))
        helperOutputBuffer = Data()

        let process = Process()
        process.executableURL = helperURL
        process.arguments = [
            "--server",
            "--locale", "pt-BR",
            "--voice", "aiden",
            "--model-dir", modelDirectoryURL.path,
            "--instruction", voiceInstruction
        ]
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                return
            }
            Task { @MainActor in
                self?.handleResidentOutput(data)
            }
        }

        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }
            DiagnosticsFileLog.shared.log(
                category: "tts",
                event: "neural_helper_stderr",
                fields: ["message": text.trimmingCharacters(in: .whitespacesAndNewlines)]
            )
        }

        process.terminationHandler = { [weak self] process in
            Task { @MainActor in
                self?.handleResidentTermination(status: process.terminationStatus)
            }
        }

        helperInputPipe = inputPipe
        helperOutputPipe = outputPipe
        helperErrorPipe = errorPipe
        helperProcess = process

        try process.run()
        DiagnosticsFileLog.shared.log(category: "tts", event: "neural_helper_resident_started")
    }

    private func sendStopToResidentHelper() {
        guard helperProcess?.isRunning == true else {
            return
        }
        let command = ResidentHelperCommand(
            id: UUID().uuidString,
            action: "stop",
            text: nil,
            locale: nil,
            voice: nil,
            modelDir: nil,
            instruction: nil
        )
        if let data = try? Self.encodeLine(command) {
            try? helperInputPipe?.fileHandleForWriting.write(contentsOf: data)
        }
    }

    private func handleResidentOutput(_ data: Data) {
        helperOutputBuffer.append(data)
        while let newline = helperOutputBuffer.firstIndex(of: 0x0A) {
            let lineData = helperOutputBuffer[..<newline]
            helperOutputBuffer.removeSubrange(...newline)
            guard !lineData.isEmpty else {
                continue
            }
            do {
                let response = try JSONDecoder().decode(ResidentHelperResponse.self, from: Data(lineData))
                if let continuation = helperContinuations.removeValue(forKey: response.id) {
                    continuation.resume(returning: response)
                }
            } catch {
                DiagnosticsFileLog.shared.log(
                    category: "tts",
                    event: "neural_helper_bad_response",
                    fields: ["error": error.localizedDescription]
                )
            }
        }
    }

    private func handleResidentTermination(status: Int32) {
        helperOutputPipe?.fileHandleForReading.readabilityHandler = nil
        helperErrorPipe?.fileHandleForReading.readabilityHandler = nil
        helperInputPipe = nil
        helperOutputPipe = nil
        helperErrorPipe = nil
        helperProcess = nil
        helperOutputBuffer = Data()
        completeAllPending(with: NeuralTTSError.runtimeUnavailable("TTSKit helper residente encerrou (\(status))"))
        DiagnosticsFileLog.shared.log(
            category: "tts",
            event: "neural_helper_resident_terminated",
            fields: ["status": "\(status)"]
        )
    }

    private func completeAllPending(with error: Error) {
        let continuations = helperContinuations
        helperContinuations = [:]
        for continuation in continuations.values {
            continuation.resume(throwing: error)
        }
    }

    private func containsModelFiles(at url: URL) -> Bool {
        guard let children = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        return children.contains { child in
            let name = child.lastPathComponent.lowercased()
            return name.hasSuffix(".mlmodelc")
                || name == "models"
                || name == "embeddings"
                || name.contains("qwen")
                || name.contains("ttskit")
        }
    }

    private static func stripEmoji(_ text: String) -> String {
        String(text.unicodeScalars.filter { scalar in
            let value = scalar.value
            return !(
                (0x1F000...0x1FAFF).contains(value)
                || (0x2600...0x27BF).contains(value)
                || value == 0x200D
                || value == 0xFE0E
                || value == 0xFE0F
            )
        })
    }

    private static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        return data
    }
}

private struct ResidentHelperCommand: Encodable {
    let id: String
    let action: String
    let text: String?
    let locale: String?
    let voice: String?
    let modelDir: String?
    let instruction: String?
}

private struct ResidentHelperResponse: Decodable {
    let id: String
    let status: String
    let error: String?
}

final class NeuralTTSCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

enum NeuralTTSError: LocalizedError {
    case emptyText
    case cancelled
    case runtimeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Texto vazio para TTS neural"
        case .cancelled:
            return "TTS neural cancelado"
        case .runtimeUnavailable(let reason):
            return reason
        }
    }
}
