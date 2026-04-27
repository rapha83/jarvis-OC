import AVFoundation
import Foundation
import Speech

final class WakeWordService {
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var restartWorkItem: DispatchWorkItem?
    private var healthWatchdogWorkItem: DispatchWorkItem?
    private var pendingWakeWorkItem: DispatchWorkItem?
    private var pendingDetection: WakeWordDetection?
    private var onWake: ((WakeWordDetection) -> Void)?
    private var wakeWords: [String] = ["jarvis"]
    private var localeID = "pt-BR"
    private var requiresOnDeviceRecognition = false
    private var isRunning = false
    private var recognitionGeneration = 0
    private var lastRecognizerActivityAt = Date()
    private let bareTriggerPauseWindow: TimeInterval = 0.55
    private let commandTriggerPauseWindow: TimeInterval = 1.0

    func start(
        wakeWords: [String] = ["jarvis"],
        localeID: String = "pt-BR",
        requiresOnDeviceRecognition: Bool = false,
        onWake: @escaping (WakeWordDetection) -> Void
    ) throws {
        stop()

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID))
        guard let recognizer, recognizer.isAvailable else {
            throw WakeWordError.recognizerUnavailable
        }
        if requiresOnDeviceRecognition, !recognizer.supportsOnDeviceRecognition {
            throw WakeWordError.onDeviceUnavailable(localeID)
        }
        guard AudioInputDeviceObserver.hasUsableDefaultInputDevice() else {
            throw WakeWordError.noInputDevice(AudioInputDeviceObserver.defaultInputDeviceSummary())
        }

        self.onWake = onWake
        self.wakeWords = wakeWords
        self.localeID = localeID
        self.requiresOnDeviceRecognition = requiresOnDeviceRecognition
        recognitionGeneration += 1
        let generation = recognitionGeneration

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = WakeWordGate.recognitionHints(for: wakeWords).flatMap { word in
            [word, word.lowercased(), word.capitalized]
        }
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = requiresOnDeviceRecognition
        }
        if #available(macOS 13.0, *) {
            request.addsPunctuation = false
        }
        recognitionRequest = request

        let audioEngine = AVAudioEngine()
        self.audioEngine = audioEngine
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRunning = true
        lastRecognizerActivityAt = Date()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.handleRecognition(result: result, error: error, generation: generation)
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning, self.recognitionGeneration == generation, let onWake = self.onWake else {
                return
            }
            try? self.start(
                wakeWords: self.wakeWords,
                localeID: self.localeID,
                requiresOnDeviceRecognition: requiresOnDeviceRecognition,
                onWake: onWake
            )
        }
        restartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: workItem)
        scheduleHealthWatchdog(generation: generation)
    }

    func stop() {
        recognitionGeneration += 1
        pendingWakeWorkItem?.cancel()
        pendingWakeWorkItem = nil
        pendingDetection = nil
        restartWorkItem?.cancel()
        restartWorkItem = nil
        healthWatchdogWorkItem?.cancel()
        healthWatchdogWorkItem = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            if audioEngine.isRunning {
                audioEngine.stop()
            }
        }
        audioEngine = nil
        isRunning = false
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?, generation: Int) {
        guard generation == recognitionGeneration else {
            return
        }

        if result != nil || error != nil {
            lastRecognizerActivityAt = Date()
        }

        if let result {
            if let detection = WakeWordGate.match(result: result, wakeWords: wakeWords) {
                DiagnosticsFileLog.shared.log(
                    category: "wake-word",
                    event: "detected",
                    fields: [
                        "engine": "appleSpeech",
                        "trigger": detection.trigger,
                        "inline": "\(detection.hasCommandHint)",
                        "final": "\(result.isFinal)"
                    ]
                )
                if result.isFinal {
                    emitWake(detection)
                    return
                }

                scheduleWakeAfterPause(detection, generation: generation)
                return
            }

            if result.isFinal {
                restartAfterRecognitionEnd()
            }
        }

        if error != nil {
            restartAfterRecognitionEnd()
        }
    }

    private func scheduleHealthWatchdog(generation: Int) {
        healthWatchdogWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning, self.recognitionGeneration == generation else {
                return
            }

            let idleSeconds = Date().timeIntervalSince(self.lastRecognizerActivityAt)
            if idleSeconds > 18 {
                DiagnosticsFileLog.shared.log(
                    category: "wake-word",
                    event: "recognizer_watchdog_restart",
                    fields: ["idleSeconds": "\(Int(idleSeconds))"]
                )
                self.restartAfterRecognitionEnd()
                return
            }

            self.scheduleHealthWatchdog(generation: generation)
        }
        healthWatchdogWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: workItem)
    }

    private func scheduleWakeAfterPause(_ detection: WakeWordDetection, generation: Int) {
        pendingDetection = detection
        pendingWakeWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isRunning, self.recognitionGeneration == generation else {
                return
            }
            self.emitWake(self.pendingDetection ?? detection)
        }
        pendingWakeWorkItem = workItem
        let delay = detection.hasCommandHint ? commandTriggerPauseWindow : bareTriggerPauseWindow
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func emitWake(_ detection: WakeWordDetection) {
        guard isRunning else {
            return
        }
        let callback = onWake
        stop()
        callback?(detection)
    }

    private func restartAfterRecognitionEnd() {
        guard isRunning, let onWake else {
            return
        }
        if let pendingDetection {
            emitWake(pendingDetection)
            return
        }
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else {
                return
            }
            try? self.start(
                wakeWords: self.wakeWords,
                localeID: self.localeID,
                requiresOnDeviceRecognition: self.requiresOnDeviceRecognition,
                onWake: onWake
            )
        }
    }
}

enum WakeWordError: LocalizedError {
    case recognizerUnavailable
    case onDeviceUnavailable(String)
    case noInputDevice(String)

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Reconhecimento de fala indisponivel"
        case .onDeviceUnavailable(let localeID):
            return "Wake word local/offline indisponivel para \(localeID) neste macOS"
        case .noInputDevice(let summary):
            return "Nenhum microfone de entrada utilizavel encontrado (\(summary))"
        }
    }
}
