import AppKit
import Foundation

final class DedicatedWakeWordService: NSObject, NSSpeechRecognizerDelegate {
    private var recognizer: NSSpeechRecognizer?
    private var onWake: ((WakeWordDetection) -> Void)?
    private var wakeWords: [String] = ["Jarvis"]
    private var isRunning = false

    func start(
        wakeWords: [String] = ["Jarvis"],
        localeID: String = "pt-BR",
        onWake: @escaping (WakeWordDetection) -> Void
    ) throws {
        stop()

        guard AudioInputDeviceObserver.hasUsableDefaultInputDevice() else {
            throw DedicatedWakeWordError.noInputDevice(AudioInputDeviceObserver.defaultInputDeviceSummary())
        }

        let commands = Self.commandVariants(for: wakeWords)
        guard !commands.isEmpty else {
            throw DedicatedWakeWordError.noWakeWords
        }

        guard let recognizer = NSSpeechRecognizer() else {
            throw DedicatedWakeWordError.runtimeUnavailable
        }
        recognizer.commands = commands
        recognizer.listensInForegroundOnly = false
        recognizer.delegate = self

        self.recognizer = recognizer
        self.onWake = onWake
        self.wakeWords = wakeWords
        self.isRunning = true

        recognizer.startListening()
        DiagnosticsFileLog.shared.log(
            category: "wake-word",
            event: "dedicated_started",
            fields: [
                "engine": "ns-speech-recognizer",
                "locale": localeID,
                "commands": commands.joined(separator: ",")
            ]
        )
    }

    func stop() {
        isRunning = false
        recognizer?.stopListening()
        recognizer?.delegate = nil
        recognizer = nil
        onWake = nil
    }

    static func runtimeSummary() -> String {
        "Detector dedicado local pronto"
    }

    func speechRecognizer(_ sender: NSSpeechRecognizer, didRecognizeCommand command: String) {
        guard isRunning else {
            return
        }

        let detection = WakeWordGate.match(transcript: command, wakeWords: wakeWords)
            ?? WakeWordDetection(transcript: command, commandHint: nil, trigger: command)

        DiagnosticsFileLog.shared.log(
            category: "wake-word",
            event: "dedicated_detected",
            fields: ["command": command]
        )

        let callback = onWake
        stop()
        callback?(detection)
    }

    private static func commandVariants(for wakeWords: [String]) -> [String] {
        var seen = Set<String>()
        return wakeWords
            .flatMap { word in
                let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
                return [trimmed, trimmed.lowercased(), trimmed.capitalized]
            }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

enum DedicatedWakeWordError: LocalizedError {
    case runtimeUnavailable
    case noWakeWords
    case noInputDevice(String)

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable:
            return "Detector dedicado local indisponivel neste macOS"
        case .noWakeWords:
            return "Configure pelo menos uma wake word"
        case .noInputDevice(let summary):
            return "Nenhum microfone de entrada utilizavel encontrado (\(summary))"
        }
    }
}
