import Foundation

@MainActor
final class SpeechAnalyzerWakeWordService {
    private var commandRecognizer = SpeechAnalyzerCommandRecognizer()
    private var task: Task<Void, Never>?
    private var pendingWakeWorkItem: DispatchWorkItem?
    private var wakeWords: [String] = ["Jarvis"]
    private var localeID = "pt-BR"
    private var onWake: ((WakeWordDetection) -> Void)?
    private let triggerOnlyPauseWindow: TimeInterval = 0.55
    private let commandPauseWindow: TimeInterval = 1.0

    func start(
        wakeWords: [String],
        localeID: String,
        onWake: @escaping (WakeWordDetection) -> Void
    ) throws {
        stop()
        guard #available(macOS 26.0, *) else {
            throw SpeechAnalyzerRecognitionError.unavailable
        }
        guard AudioInputDeviceObserver.hasUsableDefaultInputDevice() else {
            throw WakeWordError.noInputDevice(AudioInputDeviceObserver.defaultInputDeviceSummary())
        }

        self.wakeWords = wakeWords
        self.localeID = localeID
        self.onWake = onWake
        listenOnce()
    }

    func stop() {
        pendingWakeWorkItem?.cancel()
        pendingWakeWorkItem = nil
        task?.cancel()
        task = nil
        commandRecognizer.stop()
        onWake = nil
    }

    private func listenOnce() {
        task?.cancel()
        let contextual = WakeWordGate.recognitionHints(for: wakeWords)
        task = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let transcript = try await self.commandRecognizer.recognizeUntilSilence(
                    localeID: self.localeID,
                    contextualStrings: contextual,
                    onLevel: { _ in }
                )?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                guard !Task.isCancelled else {
                    return
                }
                if let detection = WakeWordGate.match(transcript: transcript, wakeWords: self.wakeWords) {
                    self.scheduleWake(detection)
                } else {
                    self.restartSoon()
                }
            } catch {
                DiagnosticsFileLog.shared.log(
                    category: "wake-word",
                    event: "speech_analyzer_error",
                    fields: ["error": error.localizedDescription]
                )
                self.restartSoon()
            }
        }
    }

    private func scheduleWake(_ detection: WakeWordDetection) {
        pendingWakeWorkItem?.cancel()
        let delay = detection.hasCommandHint ? commandPauseWindow : triggerOnlyPauseWindow
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else {
                return
            }
            let callback = self.onWake
            self.stop()
            callback?(detection)
        }
        pendingWakeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func restartSoon() {
        pendingWakeWorkItem?.cancel()
        pendingWakeWorkItem = nil
        task?.cancel()
        task = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.onWake != nil else {
                return
            }
            self.listenOnce()
        }
    }
}
