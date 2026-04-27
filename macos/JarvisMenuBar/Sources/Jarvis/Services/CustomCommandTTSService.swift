import Foundation

@MainActor
final class CustomCommandTTSService {
    private let playback = AudioPlaybackService()
    private var process: Process?
    private var generation = 0
    private(set) var lastVoiceSummary = "TTS por comando nao usado nesta sessao"

    func speak(
        _ text: String,
        commandTemplate: String,
        timeoutSeconds: Double
    ) async -> PlaybackResult {
        let clean = Self.stripEmoji(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return .failed
        }

        let template = commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty else {
            lastVoiceSummary = "Comando TTS local nao configurado"
            return .failed
        }

        stop()
        generation += 1
        let currentGeneration = generation
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-tts-\(UUID().uuidString).wav")

        let command = Self.renderCommand(
            template,
            text: clean,
            outputURL: outputURL
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        self.process = process

        do {
            try process.run()
        } catch {
            lastVoiceSummary = "Falha ao iniciar comando TTS: \(error.localizedDescription)"
            return .failed
        }

        let deadline = Date().addingTimeInterval(max(1.0, timeoutSeconds))
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        if process.isRunning {
            process.terminate()
            lastVoiceSummary = "Comando TTS excedeu timeout"
            return .failed
        }

        guard currentGeneration == generation else {
            return .stopped
        }

        guard process.terminationStatus == 0 else {
            let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            lastVoiceSummary = message.isEmpty
                ? "Comando TTS terminou com codigo \(process.terminationStatus)"
                : "Comando TTS falhou: \(message)"
            return .failed
        }

        guard let audio = try? Data(contentsOf: outputURL), !audio.isEmpty else {
            lastVoiceSummary = "Comando TTS nao gerou audio em \(outputURL.path)"
            return .failed
        }

        lastVoiceSummary = "Comando local"
        return (try? await playback.play(data: audio)) ?? .failed
    }

    func stop() {
        generation += 1
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        playback.stop()
    }

    static func configurationSummary(commandTemplate: String) -> String {
        commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "TTS local por comando: nao configurado"
            : "TTS local por comando configurado"
    }

    private static func renderCommand(_ template: String, text: String, outputURL: URL) -> String {
        var command = template
        command = command.replacingOccurrences(of: "{{text}}", with: shellQuote(text))
        command = command.replacingOccurrences(of: "{text}", with: shellQuote(text))
        command = command.replacingOccurrences(of: "{{output}}", with: shellQuote(outputURL.path))
        command = command.replacingOccurrences(of: "{output}", with: shellQuote(outputURL.path))
        command = command.replacingOccurrences(of: "{{outputDir}}", with: shellQuote(outputURL.deletingLastPathComponent().path))
        command = command.replacingOccurrences(of: "{outputDir}", with: shellQuote(outputURL.deletingLastPathComponent().path))
        command = command.replacingOccurrences(of: "{{outputBase}}", with: shellQuote(outputURL.deletingPathExtension().lastPathComponent))
        command = command.replacingOccurrences(of: "{outputBase}", with: shellQuote(outputURL.deletingPathExtension().lastPathComponent))
        return command
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
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
}
