import Darwin
import Foundation

#if canImport(TTSKit)
import TTSKit
#endif

@main
struct JarvisTTSHelper {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run() async throws {
        let args = CommandLine.arguments.dropFirst()
        let options = parse(args)
        let localeID = options["locale"] ?? "pt-BR"
        let voiceID = options["voice"] ?? "aiden"
        let modelDir = options["model-dir"].map(URL.init(fileURLWithPath:))
        let instruction = options["instruction"] ?? defaultInstruction

        if options.keys.contains("server") {
            let server = HelperServer(
                defaultLocaleID: localeID,
                defaultVoiceID: voiceID,
                defaultModelDir: modelDir,
                defaultInstruction: instruction
            )
            await server.run()
            return
        }

        if options.keys.contains("prepare") {
            try await prepare(localeID: localeID, voiceID: voiceID, modelDir: modelDir, instruction: instruction)
            return
        }

        guard options.keys.contains("speak") else {
            throw HelperError.invalidArguments
        }
        let text = (options["text"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw HelperError.emptyText
        }
        try await speak(text: text, localeID: localeID, voiceID: voiceID, modelDir: modelDir, instruction: instruction)
    }

    private static let defaultInstruction = "Speak naturally."

    private static func parse(_ args: ArraySlice<String>) -> [String: String] {
        var values: [String: String] = [:]
        var iterator = args.makeIterator()
        while let token = iterator.next() {
            guard token.hasPrefix("--") else {
                continue
            }
            let key = String(token.dropFirst(2))
            if ["speak", "prepare", "server"].contains(key) {
                values[key] = "true"
                continue
            }
            values[key] = iterator.next() ?? ""
        }
        return values
    }

    fileprivate static func speak(
        text: String,
        localeID: String,
        voiceID: String,
        modelDir: URL?,
        instruction: String,
        cancellation: HelperCancellation = HelperCancellation()
    ) async throws {
        #if canImport(TTSKit)
        let kit = try await SharedTTSKitStore.shared.kit(modelDir: modelDir)
        let options = GenerationOptions(
            temperature: 0.82,
            topK: 45,
            repetitionPenalty: 1.06,
            maxNewTokens: 280,
            concurrentWorkerCount: 1,
            chunkingStrategy: .sentence,
            targetChunkSize: 38,
            minChunkSize: 8,
            instruction: instruction
        )
        _ = try await kit.play(
            text: stripEmoji(text),
            speaker: speaker(from: voiceID),
            language: language(from: localeID),
            options: options,
            playbackStrategy: .auto,
            callback: { _ in
                cancellation.isCancelled ? false : nil
            }
        )
        if cancellation.isCancelled {
            throw HelperError.cancelled
        }
        #else
        _ = (text, localeID, voiceID, modelDir, instruction, cancellation)
        throw HelperError.ttsKitUnavailable
        #endif
    }

    fileprivate static func prepare(
        localeID: String,
        voiceID: String,
        modelDir: URL?,
        instruction: String
    ) async throws {
        #if canImport(TTSKit)
        let kit = try await SharedTTSKitStore.shared.kit(modelDir: modelDir)
        _ = try await kit.buildPromptCache(
            speaker: speaker(from: voiceID),
            language: language(from: localeID),
            instruction: instruction
        )
        #else
        _ = (localeID, voiceID, modelDir, instruction)
        throw HelperError.ttsKitUnavailable
        #endif
    }

    #if canImport(TTSKit)
    fileprivate static func containsModelFiles(at url: URL) -> Bool {
        guard let children = try? FileManager.default.contentsOfDirectory(
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

    fileprivate static func language(from localeID: String) -> Qwen3Language {
        let code = localeID
            .split(separator: "-")
            .first
            .map(String.init)?
            .lowercased() ?? "pt"

        switch code {
        case "pt":
            return .portuguese
        case "es":
            return .spanish
        case "fr":
            return .french
        case "de":
            return .german
        case "it":
            return .italian
        case "ru":
            return .russian
        case "ja":
            return .japanese
        case "ko":
            return .korean
        case "zh":
            return .chinese
        default:
            return .english
        }
    }

    fileprivate static func speaker(from voiceID: String) -> Qwen3Speaker {
        switch voiceID {
        case "ryan":
            return .ryan
        case "uncle-fu":
            return .uncleFu
        case "dylan":
            return .dylan
        case "eric":
            return .eric
        default:
            return .aiden
        }
    }
    #endif

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
}

private struct HelperCommand: Codable {
    let id: String
    let action: String
    let text: String?
    let locale: String?
    let voice: String?
    let modelDir: String?
    let instruction: String?
}

private struct HelperResponse: Codable {
    let id: String
    let status: String
    let error: String?

    static func ok(_ id: String) -> HelperResponse {
        HelperResponse(id: id, status: "ok", error: nil)
    }

    static func failed(_ id: String, error: Error) -> HelperResponse {
        HelperResponse(id: id, status: "error", error: error.localizedDescription)
    }

    static func cancelled(_ id: String) -> HelperResponse {
        HelperResponse(id: id, status: "cancelled", error: nil)
    }
}

private final class HelperServer {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let writeLock = NSLock()
    private let stateLock = NSLock()
    private let defaultLocaleID: String
    private let defaultVoiceID: String
    private let defaultModelDir: URL?
    private let defaultInstruction: String
    private var currentTask: Task<Void, Never>?
    private var currentCancellation: HelperCancellation?
    private var shouldShutdown = false

    init(
        defaultLocaleID: String,
        defaultVoiceID: String,
        defaultModelDir: URL?,
        defaultInstruction: String
    ) {
        self.defaultLocaleID = defaultLocaleID
        self.defaultVoiceID = defaultVoiceID
        self.defaultModelDir = defaultModelDir
        self.defaultInstruction = defaultInstruction
    }

    func run() async {
        while !shouldShutdown, let line = readLine(strippingNewline: true) {
            guard let data = line.data(using: .utf8) else {
                continue
            }
            do {
                let command = try decoder.decode(HelperCommand.self, from: data)
                handle(command)
            } catch {
                respond(HelperResponse(id: "unknown", status: "error", error: error.localizedDescription))
            }
        }
        cancelCurrent()
    }

    private func handle(_ command: HelperCommand) {
        switch command.action {
        case "prepare":
            startTask(command: command) { [weak self] cancellation in
                guard let self else { return }
                do {
                    try await JarvisTTSHelper.prepare(
                        localeID: command.locale ?? self.defaultLocaleID,
                        voiceID: command.voice ?? self.defaultVoiceID,
                        modelDir: self.modelDir(from: command),
                        instruction: command.instruction ?? self.defaultInstruction
                    )
                    if cancellation.isCancelled {
                        self.respond(.cancelled(command.id))
                    } else {
                        self.respond(.ok(command.id))
                    }
                } catch {
                    self.respond(.failed(command.id, error: error))
                }
            }
        case "speak":
            let text = (command.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                respond(.failed(command.id, error: HelperError.emptyText))
                return
            }
            startTask(command: command) { [weak self] cancellation in
                guard let self else { return }
                do {
                    try await JarvisTTSHelper.speak(
                        text: text,
                        localeID: command.locale ?? self.defaultLocaleID,
                        voiceID: command.voice ?? self.defaultVoiceID,
                        modelDir: self.modelDir(from: command),
                        instruction: command.instruction ?? self.defaultInstruction,
                        cancellation: cancellation
                    )
                    self.respond(.ok(command.id))
                } catch HelperError.cancelled {
                    self.respond(.cancelled(command.id))
                } catch {
                    self.respond(.failed(command.id, error: error))
                }
            }
        case "stop":
            cancelCurrent()
            respond(.ok(command.id))
        case "shutdown":
            shouldShutdown = true
            cancelCurrent()
            respond(.ok(command.id))
        default:
            respond(HelperResponse(id: command.id, status: "error", error: "Acao desconhecida: \(command.action)"))
        }
    }

    private func startTask(
        command: HelperCommand,
        operation: @escaping (HelperCancellation) async -> Void
    ) {
        cancelCurrent()
        let cancellation = HelperCancellation()
        let task = Task {
            await operation(cancellation)
        }

        stateLock.lock()
        currentCancellation = cancellation
        currentTask = task
        stateLock.unlock()
    }

    private func cancelCurrent() {
        stateLock.lock()
        let task = currentTask
        let cancellation = currentCancellation
        currentTask = nil
        currentCancellation = nil
        stateLock.unlock()

        cancellation?.cancel()
        task?.cancel()
    }

    private func modelDir(from command: HelperCommand) -> URL? {
        command.modelDir.map(URL.init(fileURLWithPath:)) ?? defaultModelDir
    }

    private func respond(_ response: HelperResponse) {
        guard let data = try? encoder.encode(response) else {
            return
        }
        writeLock.lock()
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
        writeLock.unlock()
    }
}

#if canImport(TTSKit)
private actor SharedTTSKitStore {
    static let shared = SharedTTSKitStore()
    private var kit: TTSKit?
    private var loadedModelDir: URL?

    func kit(modelDir: URL?) async throws -> TTSKit {
        if let kit, loadedModelDir?.path == modelDir?.path {
            return kit
        }

        let loaded: TTSKit
        if let modelDir, JarvisTTSHelper.containsModelFiles(at: modelDir) {
            loaded = try await TTSKit(
                model: .qwen3TTS_1_7b,
                modelFolder: modelDir,
                download: false
            )
        } else {
            loaded = try await TTSKit(model: .qwen3TTS_1_7b)
        }
        kit = loaded
        loadedModelDir = modelDir
        return loaded
    }
}
#endif

final class HelperCancellation: @unchecked Sendable {
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

enum HelperError: LocalizedError {
    case invalidArguments
    case emptyText
    case cancelled
    case ttsKitUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidArguments:
            return "Uso: JarvisTTSHelper --server, --speak --text <texto> ou --prepare"
        case .emptyText:
            return "Texto vazio"
        case .cancelled:
            return "TTS cancelado"
        case .ttsKitUnavailable:
            return "TTSKit nao esta linkado no helper"
        }
    }
}
