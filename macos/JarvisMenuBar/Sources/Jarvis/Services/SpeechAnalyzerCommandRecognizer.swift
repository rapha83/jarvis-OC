import AVFoundation
import Foundation
import Speech

@MainActor
final class SpeechAnalyzerCommandRecognizer {
    private var pipeline: Any?
    private var resultTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private var continuation: CheckedContinuation<String?, Error>?
    private var latestTranscript = ""
    private var lastTranscriptAt = Date()
    private var startedAt = Date()
    private var emptySpeechTimeout: TimeInterval = 4.8
    private var finished = false

    func recognizeUntilSilence(
        localeID: String,
        contextualStrings: [String],
        emptyTimeout: TimeInterval = 4.8,
        onLevel: @escaping @MainActor (Float) -> Void
    ) async throws -> String? {
        stop()

        guard AudioInputDeviceObserver.hasUsableDefaultInputDevice() else {
            throw NativeSpeechRecognitionError.noInputDevice(AudioInputDeviceObserver.defaultInputDeviceSummary())
        }

        guard #available(macOS 26.0, *) else {
            throw SpeechAnalyzerRecognitionError.unavailable
        }

#if JARVIS_DISABLE_SPEECH_ANALYZER
        throw SpeechAnalyzerRecognitionError.unavailable
#else
        _ = contextualStrings
        startedAt = Date()
        lastTranscriptAt = startedAt
        latestTranscript = ""
        emptySpeechTimeout = emptyTimeout
        finished = false

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            Task { @MainActor in
                do {
                    let pipeline = ModernSpeechAnalyzerPipeline()
                    self.pipeline = pipeline
                    let stream = try await pipeline.start(localeIdentifier: localeID)
                    self.consume(stream: stream, pipeline: pipeline, onLevel: onLevel)
                } catch {
                    self.finish(result: .failure(error))
                }
            }
        }
#endif
    }

    func stop() {
        finish(result: .success(nil))
    }

#if !JARVIS_DISABLE_SPEECH_ANALYZER
    @available(macOS 26.0, *)
    private func consume(
        stream: AsyncStream<ModernSpeechSegment>,
        pipeline: ModernSpeechAnalyzerPipeline,
        onLevel: @escaping @MainActor (Float) -> Void
    ) {
        resultTask?.cancel()
        silenceTask?.cancel()

        resultTask = Task { [weak self] in
            for await segment in stream {
                await MainActor.run {
                    guard let self, !self.finished else {
                        return
                    }
                    let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        self.latestTranscript = text
                        self.lastTranscriptAt = Date()
                        onLevel(0.75)
                    }
                    if segment.isFinal, !self.latestTranscript.isEmpty {
                        self.finish(result: .success(self.latestTranscript))
                    }
                }
            }
        }

        silenceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 160_000_000)
                await MainActor.run {
                    self?.finishIfSilent()
                }
            }
            await pipeline.stop()
        }
    }
#endif

    private func finishIfSilent() {
        guard !finished else {
            return
        }

        let now = Date()
        if latestTranscript.isEmpty {
            if now.timeIntervalSince(startedAt) > emptySpeechTimeout {
                finish(result: .success(nil))
            }
            return
        }

        if now.timeIntervalSince(lastTranscriptAt) > 0.95 {
            finish(result: .success(latestTranscript))
        }
    }

    private func finish(result: Result<String?, Error>) {
        guard !finished else {
            return
        }
        finished = true
        resultTask?.cancel()
        resultTask = nil
        silenceTask?.cancel()
        silenceTask = nil

#if !JARVIS_DISABLE_SPEECH_ANALYZER
        if #available(macOS 26.0, *), let pipeline = pipeline as? ModernSpeechAnalyzerPipeline {
            Task { await pipeline.stop() }
        }
#endif
        pipeline = nil

        let continuation = continuation
        self.continuation = nil
        switch result {
        case .success(let transcript):
            continuation?.resume(returning: transcript)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
    }
}

#if !JARVIS_DISABLE_SPEECH_ANALYZER
@available(macOS 26.0, *)
struct ModernSpeechSegment: Sendable {
    let text: String
    let isFinal: Bool
}

@available(macOS 26.0, *)
actor ModernSpeechAnalyzerPipeline {
    private struct UnsafeBuffer: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
    }

    private let converter = BufferConverter()
    private var engine = AVAudioEngine()
    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultTask: Task<Void, Never>?

    func start(localeIdentifier: String) async throws -> AsyncStream<ModernSpeechSegment> {
        let auth = await requestAuthorizationIfNeeded()
        guard auth == .authorized else {
            throw SpeechAnalyzerRecognitionError.authorizationDenied
        }

        let requestedLocale = Locale(identifier: localeIdentifier)
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw SpeechAnalyzerRecognitionError.localeUnsupported(localeIdentifier)
        }

        let transcriberModule = SpeechTranscriber(
            locale: supportedLocale,
            transcriptionOptions: [.etiquetteReplacements],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        transcriber = transcriberModule

        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        let preferredAnalyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriberModule],
            considering: inputFormat
        )
        let fallbackAnalyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriberModule])
        guard let analyzerFormat = preferredAnalyzerFormat ?? fallbackAnalyzerFormat else {
            throw SpeechAnalyzerRecognitionError.analyzerFormatUnavailable
        }

        let analyzer = SpeechAnalyzer(modules: [transcriberModule])
        self.analyzer = analyzer
        try await analyzer.prepareToAnalyze(in: analyzerFormat)

        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = inputContinuation

        let inputNode = engine.inputNode
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else {
                return
            }
            let boxed = UnsafeBuffer(buffer: buffer)
            Task {
                await self.handleBuffer(boxed.buffer, targetFormat: analyzerFormat)
            }
        }

        engine.prepare()
        try await analyzer.start(inputSequence: inputStream)
        try engine.start()

        guard let transcriber else {
            throw SpeechAnalyzerRecognitionError.transcriberUnavailable
        }

        return AsyncStream { continuation in
            self.resultTask = Task {
                do {
                    for try await result in transcriber.results {
                        continuation.yield(ModernSpeechSegment(
                            text: String(result.text.characters),
                            isFinal: result.isFinal
                        ))
                    }
                } catch {
                    DiagnosticsFileLog.shared.log(
                        category: "speech-analyzer",
                        event: "result_stream_error",
                        fields: ["error": error.localizedDescription]
                    )
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                Task {
                    await self.stop()
                }
            }
        }
    }

    func stop() async {
        resultTask?.cancel()
        resultTask = nil
        inputContinuation?.finish()
        inputContinuation = nil
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
        }
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        analyzer = nil
        transcriber = nil
    }

    private func handleBuffer(_ buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) async {
        do {
            let converted = try converter.convert(buffer, to: targetFormat)
            inputContinuation?.yield(AnalyzerInput(buffer: converted))
        } catch {
            DiagnosticsFileLog.shared.log(
                category: "speech-analyzer",
                event: "convert_failed",
                fields: ["error": "\(error)"]
            )
        }
    }

    private func requestAuthorizationIfNeeded() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else {
            return current
        }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
#endif

enum SpeechAnalyzerRecognitionError: LocalizedError {
    case unavailable
    case authorizationDenied
    case localeUnsupported(String)
    case analyzerFormatUnavailable
    case transcriberUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "SpeechAnalyzer requer macOS 26 ou superior"
        case .authorizationDenied:
            return "Reconhecimento de fala nao autorizado"
        case .localeUnsupported(let localeID):
            return "Locale \(localeID) nao suportado pelo SpeechAnalyzer"
        case .analyzerFormatUnavailable:
            return "Formato de audio indisponivel para SpeechAnalyzer"
        case .transcriberUnavailable:
            return "SpeechTranscriber indisponivel"
        }
    }
}
