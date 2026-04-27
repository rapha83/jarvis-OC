import AVFoundation
import Foundation
import Speech

@MainActor
final class NativeSpeechCommandRecognizer {
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<String?, Error>?
    private var silenceWatchdog: Task<Void, Never>?
    private var hardStopWatchdog: Task<Void, Never>?
    private var onLevel: (@MainActor (Float) -> Void)?
    private var latestTranscript = ""
    private var speechStarted = false
    private var startedAt = Date()
    private var lastSpeechAt = Date()
    private var noiseFloor: Float = 0.003
    private var finished = false

    func recognizeUntilSilence(
        localeID: String,
        requiresOnDeviceRecognition: Bool,
        contextualStrings: [String],
        onLevel: @escaping @MainActor (Float) -> Void
    ) async throws -> String? {
        stop()

        guard AudioInputDeviceObserver.hasUsableDefaultInputDevice() else {
            throw NativeSpeechRecognitionError.noInputDevice(AudioInputDeviceObserver.defaultInputDeviceSummary())
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)), recognizer.isAvailable else {
            throw NativeSpeechRecognitionError.recognizerUnavailable
        }
        if requiresOnDeviceRecognition, !recognizer.supportsOnDeviceRecognition {
            throw NativeSpeechRecognitionError.onDeviceUnavailable(localeID)
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.onLevel = onLevel
            self.startRecognition(
                recognizer: recognizer,
                requiresOnDeviceRecognition: requiresOnDeviceRecognition,
                contextualStrings: contextualStrings
            )
        }
    }

    func stop() {
        finish(result: .success(nil), cancelTask: true)
    }

    private func startRecognition(
        recognizer: SFSpeechRecognizer,
        requiresOnDeviceRecognition: Bool,
        contextualStrings: [String]
    ) {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = contextualStrings
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = requiresOnDeviceRecognition
        }
        if #available(macOS 13.0, *) {
            request.addsPunctuation = false
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, weak request] buffer, _ in
            request?.append(buffer)
            let level = Self.rms(buffer: buffer)
            Task { @MainActor in
                self?.consume(level: level)
            }
        }

        audioEngine = engine
        recognitionRequest = request
        latestTranscript = ""
        speechStarted = false
        startedAt = Date()
        lastSpeechAt = startedAt
        noiseFloor = 0.003
        finished = false

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handleRecognition(result: result, error: error)
            }
        }

        do {
            engine.prepare()
            try engine.start()
            startWatchdogs()
        } catch {
            finish(result: .failure(error), cancelTask: true)
        }
    }

    private func consume(level rms: Float) {
        guard !finished else {
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(startedAt)
        let threshold = speechThreshold(rms: rms, elapsed: elapsed)
        let isSpeech = rms > threshold
        onLevel?(min(1, rms / max(threshold, 0.001)))

        if isSpeech {
            speechStarted = true
            lastSpeechAt = now
        }
    }

    private func handleRecognition(result: SFSpeechRecognitionResult?, error: Error?) {
        guard !finished else {
            return
        }

        if let result {
            let text = result.bestTranscription.formattedString
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                latestTranscript = text
            }
            if result.isFinal, !latestTranscript.isEmpty {
                finish(result: .success(latestTranscript), cancelTask: false)
                return
            }
        }

        if let error {
            finish(result: .failure(error), cancelTask: true)
        }
    }

    private func startWatchdogs() {
        silenceWatchdog?.cancel()
        hardStopWatchdog?.cancel()

        silenceWatchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000)
                await MainActor.run {
                    self?.finishIfSilent()
                }
            }
        }

        hardStopWatchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            await MainActor.run {
                self?.finish(result: .success(self?.latestTranscript), cancelTask: true)
            }
        }
    }

    private func finishIfSilent() {
        guard !finished else {
            return
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(startedAt)
        if !speechStarted, elapsed > 4.8 {
            finish(result: .success(nil), cancelTask: true)
            return
        }

        guard speechStarted else {
            return
        }

        let silenceDuration = now.timeIntervalSince(lastSpeechAt)
        let finishDelay = latestTranscript.count >= 8 ? 0.88 : 1.15
        if silenceDuration > finishDelay, !latestTranscript.isEmpty {
            finish(result: .success(latestTranscript), cancelTask: true)
        } else if silenceDuration > 2.2 {
            finish(result: .success(nil), cancelTask: true)
        }
    }

    private func speechThreshold(rms: Float, elapsed: TimeInterval) -> Float {
        if !speechStarted, elapsed < 0.8 {
            noiseFloor = (noiseFloor * 0.85) + (rms * 0.15)
        } else if !speechStarted, rms < max(noiseFloor * 3.0, 0.004) {
            noiseFloor = (noiseFloor * 0.97) + (rms * 0.03)
        }

        return min(0.035, max(0.004, noiseFloor * 4.0))
    }

    private func finish(result: Result<String?, Error>, cancelTask: Bool) {
        guard !finished else {
            return
        }

        finished = true
        silenceWatchdog?.cancel()
        silenceWatchdog = nil
        hardStopWatchdog?.cancel()
        hardStopWatchdog = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        if cancelTask {
            recognitionTask?.cancel()
        }
        recognitionTask = nil

        if let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            if audioEngine.isRunning {
                audioEngine.stop()
            }
        }
        audioEngine = nil
        onLevel = nil

        let continuation = continuation
        self.continuation = nil
        switch result {
        case .success(let transcript):
            continuation?.resume(returning: transcript)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }

    private static func rms(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else {
            return 0
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else {
            return 0
        }

        var sumSquares: Float = 0
        for frame in 0..<frameLength {
            var mixed: Float = 0
            for channel in 0..<channelCount {
                mixed += channelData[channel][frame]
            }
            mixed /= Float(channelCount)
            sumSquares += mixed * mixed
        }

        return sqrt(sumSquares / Float(frameLength))
    }
}

enum NativeSpeechRecognitionError: LocalizedError {
    case recognizerUnavailable
    case onDeviceUnavailable(String)
    case noInputDevice(String)

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Reconhecimento de fala nativo indisponivel"
        case .onDeviceUnavailable(let localeID):
            return "STT local/offline indisponivel para \(localeID) neste macOS"
        case .noInputDevice(let summary):
            return "Nenhum microfone de entrada utilizavel encontrado (\(summary))"
        }
    }
}
