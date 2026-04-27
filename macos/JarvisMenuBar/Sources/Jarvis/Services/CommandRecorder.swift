import AVFoundation
import Foundation

final class CommandRecorder {
    private let queue = DispatchQueue(label: "jarvis.command-recorder")
    private var audioEngine: AVAudioEngine?
    private var continuation: CheckedContinuation<Data?, Error>?
    private var levelHandler: (@Sendable (Float) -> Void)?
    private var pcmData = Data()
    private var sampleRate = 44_100
    private var speechStarted = false
    private var silenceStartedAt: Date?
    private var recordingStartedAt: Date?
    private var finished = false
    private var noiseFloor: Float = 0.003

    func recordUntilSilence(onLevel: (@Sendable (Float) -> Void)? = nil) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.continuation = continuation
                self.levelHandler = onLevel
                self.startLocked()
            }
        }
    }

    func stop() {
        queue.async {
            self.finishLocked(data: nil)
        }
    }

    private func startLocked() {
        guard AudioInputDeviceObserver.hasUsableDefaultInputDevice() else {
            finishLocked(error: CommandRecorderError.noInputDevice(AudioInputDeviceObserver.defaultInputDeviceSummary()))
            return
        }

        let engine = AVAudioEngine()
        audioEngine = engine
        pcmData = Data()
        speechStarted = false
        silenceStartedAt = nil
        recordingStartedAt = Date()
        finished = false
        noiseFloor = 0.003

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        sampleRate = Int(format.sampleRate.rounded())
        inputNode.removeTap(onBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.queue.async {
                self?.consume(buffer: buffer)
            }
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            finishLocked(error: error)
        }
    }

    private func consume(buffer: AVAudioPCMBuffer) {
        guard !finished, let channelData = buffer.floatChannelData else {
            return
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var sumSquares: Float = 0

        for frame in 0..<frameLength {
            var mixed: Float = 0
            for channel in 0..<channelCount {
                mixed += channelData[channel][frame]
            }
            mixed /= Float(max(channelCount, 1))
            sumSquares += mixed * mixed

            let clamped = max(-1, min(1, mixed))
            var sample = Int16(clamped * Float(Int16.max)).littleEndian
            pcmData.append(Data(bytes: &sample, count: MemoryLayout<Int16>.size))
        }

        let rms = sqrt(sumSquares / Float(max(frameLength, 1)))
        let now = Date()
        let elapsed = recordingStartedAt.map { now.timeIntervalSince($0) } ?? 0
        let threshold = speechThreshold(rms: rms, elapsed: elapsed)
        let isSpeech = rms > threshold
        levelHandler?(min(1, rms / max(threshold, 0.001)))

        if isSpeech {
            speechStarted = true
            silenceStartedAt = nil
        } else if speechStarted {
            if silenceStartedAt == nil {
                silenceStartedAt = now
            } else if let silenceStartedAt, now.timeIntervalSince(silenceStartedAt) > 0.95 {
                finishLocked(data: WavWriter.makeWav(pcm16: pcmData, sampleRate: sampleRate))
            }
        } else if elapsed > 4.8 {
            finishLocked(data: nil)
        }

        if elapsed > 18 {
            finishLocked(data: WavWriter.makeWav(pcm16: pcmData, sampleRate: sampleRate))
        }
    }

    private func speechThreshold(rms: Float, elapsed: TimeInterval) -> Float {
        if !speechStarted && elapsed < 0.8 {
            noiseFloor = (noiseFloor * 0.85) + (rms * 0.15)
        } else if !speechStarted && rms < max(noiseFloor * 3.0, 0.004) {
            noiseFloor = (noiseFloor * 0.97) + (rms * 0.03)
        }

        return min(0.035, max(0.004, noiseFloor * 4.0))
    }

    private func finishLocked(data: Data?) {
        guard !finished else {
            return
        }
        finished = true
        if let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        audioEngine = nil
        levelHandler = nil
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: data)
    }

    private func finishLocked(error: Error) {
        guard !finished else {
            return
        }
        finished = true
        if let audioEngine {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        audioEngine = nil
        levelHandler = nil
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(throwing: error)
    }
}

enum CommandRecorderError: LocalizedError {
    case noInputDevice(String)

    var errorDescription: String? {
        switch self {
        case .noInputDevice(let summary):
            return "Nenhum microfone de entrada utilizavel encontrado (\(summary))"
        }
    }
}

extension CommandRecorder: @unchecked Sendable {}
