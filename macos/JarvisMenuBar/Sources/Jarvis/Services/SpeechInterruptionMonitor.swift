import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechInterruptionMonitor {
    private var engine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var armTask: Task<Void, Never>?
    private var isArmed = false
    private var consecutiveHits = 0
    private var lastSpeechEnergyAt: Date?
    private var lastSpokenText = ""
    private var recognitionGateActive = false

    func start(
        delay: TimeInterval = 0.8,
        threshold: Float = 0.035,
        sustainedBuffers: Int = 8,
        localeID: String = "pt-BR",
        lastSpokenText: String = "",
        wakeWords: [String] = [],
        requireWakeWord: Bool = false,
        onSpeech: @escaping @MainActor () -> Void
    ) {
        stop()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            return
        }

        isArmed = false
        consecutiveHits = 0
        self.lastSpokenText = lastSpokenText
        let wakeWords = wakeWords.isEmpty ? ["Jarvis"] : wakeWords
        self.engine = engine
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID))
        if let recognizer, recognizer.isAvailable {
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            if #available(macOS 13.0, *) {
                request.addsPunctuation = false
            }
            recognitionRequest = request
            recognitionGateActive = true
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, _ in
                guard let result else {
                    return
                }
                Task { @MainActor in
                    self?.evaluateRecognition(
                        result,
                        wakeWords: wakeWords,
                        requireWakeWord: requireWakeWord,
                        onSpeech: onSpeech
                    )
                }
            }
        } else {
            recognitionGateActive = false
        }

        let request = recognitionRequest
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, weak engine, weak request] buffer, _ in
            guard let self, let engine else {
                return
            }
            request?.append(buffer)
            let level = Self.rmsLevel(buffer: buffer)
            Task { @MainActor in
                guard self.engine === engine, self.isArmed else {
                    return
                }

                if level >= threshold {
                    self.consecutiveHits += 1
                    self.lastSpeechEnergyAt = Date()
                } else {
                    self.consecutiveHits = 0
                }

                guard !self.recognitionGateActive, !requireWakeWord else {
                    return
                }
                guard self.consecutiveHits >= sustainedBuffers else {
                    return
                }
                self.stop()
                onSpeech()
            }
        }

        do {
            try engine.start()
        } catch {
            stop()
            return
        }

        armTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                self?.isArmed = true
            }
        }
    }

    func stop() {
        armTask?.cancel()
        armTask = nil
        isArmed = false
        consecutiveHits = 0
        lastSpeechEnergyAt = nil
        lastSpokenText = ""
        recognitionGateActive = false
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
    }

    private func evaluateRecognition(
        _ result: SFSpeechRecognitionResult,
        wakeWords: [String],
        requireWakeWord: Bool,
        onSpeech: @escaping @MainActor () -> Void
    ) {
        guard isArmed else {
            return
        }
        let transcript = result.bestTranscription.formattedString
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard transcript.count >= 3 else {
            return
        }
        let hasConfidence = result.bestTranscription.segments.contains { $0.confidence >= 0.55 }
            || result.isFinal
        guard hasConfidence else {
            return
        }
        if requireWakeWord, WakeWordGate.match(transcript: transcript, wakeWords: wakeWords) == nil {
            return
        }
        if let lastSpeechEnergyAt, Date().timeIntervalSince(lastSpeechEnergyAt) > 0.45 {
            return
        }
        guard !Self.isLikelyEcho(transcript: transcript, spoken: lastSpokenText) else {
            return
        }
        stop()
        onSpeech()
    }

    private static func isLikelyEcho(transcript: String, spoken: String) -> Bool {
        let probe = normalize(transcript)
        let source = normalize(spoken)
        guard probe.count >= 3, !source.isEmpty else {
            return false
        }
        if source.contains(probe) {
            return true
        }
        if probe.count >= 8 {
            let prefix = String(probe.prefix(24))
            return source.contains(prefix)
        }
        return false
    }

    private static func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func rmsLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard
            let channelData = buffer.floatChannelData,
            buffer.frameLength > 0
        else {
            return 0
        }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        var sampleCount = 0

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for index in 0..<frameLength {
                let sample = samples[index]
                sum += sample * sample
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else {
            return 0
        }
        return sqrt(sum / Float(sampleCount))
    }
}
