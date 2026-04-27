import AVFoundation
import CoreML
import Foundation
import SoundAnalysis

struct CoreMLWakeWordStatus: Equatable {
    let isRuntimeAvailable: Bool
    let modelPath: String?
    let summary: String
}

final class CoreMLWakeWordService {
    private let fileManager = FileManager.default
    private var audioEngine: AVAudioEngine?
    private var analyzer: SNAudioStreamAnalyzer?
    private var observer: CoreMLWakeWordObserver?
    private var onWake: ((WakeWordDetection) -> Void)?
    private var isRunning = false

    var modelDirectoryURL: URL {
        Self.modelDirectoryURL
    }

    func start(
        wakeWords: [String] = ["Jarvis"],
        confidenceThreshold: Double = 0.78,
        onWake: @escaping (WakeWordDetection) -> Void
    ) throws {
        stop()

        guard AudioInputDeviceObserver.hasUsableDefaultInputDevice() else {
            throw CoreMLWakeWordError.noInputDevice(AudioInputDeviceObserver.defaultInputDeviceSummary())
        }

        guard !wakeWords.isEmpty else {
            throw CoreMLWakeWordError.noWakeWords
        }

        let modelURL = try Self.loadableModelURL()
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        let model = try MLModel(contentsOf: modelURL, configuration: configuration)
        let request = try SNClassifySoundRequest(mlModel: model)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw CoreMLWakeWordError.noInputDevice("Formato de microfone invalido")
        }

        let analyzer = SNAudioStreamAnalyzer(format: format)
        let observer = CoreMLWakeWordObserver(
            wakeWords: wakeWords,
            confidenceThreshold: confidenceThreshold
        ) { [weak self] identifier, confidence in
            guard let self, self.isRunning else {
                return
            }
            let detection = WakeWordDetection(
                transcript: identifier,
                commandHint: nil,
                trigger: identifier
            )
            DiagnosticsFileLog.shared.log(
                category: "wake-word",
                event: "coreml_detected",
                fields: [
                    "identifier": identifier,
                    "confidence": String(format: "%.2f", confidence)
                ]
            )
            let callback = self.onWake
            self.stop()
            callback?(detection)
        }

        try analyzer.add(request, withObserver: observer)
        input.installTap(onBus: 0, bufferSize: 2_048, format: format) { [weak analyzer] buffer, time in
            analyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
        }

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        self.analyzer = analyzer
        self.observer = observer
        self.onWake = onWake
        self.isRunning = true

        DiagnosticsFileLog.shared.log(
            category: "wake-word",
            event: "coreml_started",
            fields: [
                "model": modelURL.path,
                "threshold": String(format: "%.2f", confidenceThreshold),
                "wakeWords": wakeWords.joined(separator: ",")
            ]
        )
    }

    func stop() {
        isRunning = false
        if let input = audioEngine?.inputNode {
            input.removeTap(onBus: 0)
        }
        audioEngine?.stop()
        analyzer?.removeAllRequests()
        audioEngine = nil
        analyzer = nil
        observer = nil
        onWake = nil
    }

    func status() -> CoreMLWakeWordStatus {
        Self.status()
    }

    func ensureModelDirectory() throws -> URL {
        try fileManager.createDirectory(at: modelDirectoryURL, withIntermediateDirectories: true)
        return modelDirectoryURL
    }

    static func status() -> CoreMLWakeWordStatus {
        guard #available(macOS 10.15, *) else {
            return CoreMLWakeWordStatus(
                isRuntimeAvailable: false,
                modelPath: nil,
                summary: "SoundAnalysis/Core ML indisponivel neste macOS"
            )
        }

        if let compiled = discoverCompiledModelURL() {
            return CoreMLWakeWordStatus(
                isRuntimeAvailable: true,
                modelPath: compiled.path,
                summary: "Core ML Jarvis pronto"
            )
        }

        if let source = discoverSourceModelURL() {
            return CoreMLWakeWordStatus(
                isRuntimeAvailable: true,
                modelPath: source.path,
                summary: "Core ML Jarvis pronto para compilar"
            )
        }

        return CoreMLWakeWordStatus(
            isRuntimeAvailable: false,
            modelPath: nil,
            summary: "Modelo JarvisWakeWord.mlmodelc ausente"
        )
    }

    private static var modelDirectoryURL: URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("JARVIS", isDirectory: true)
            .appendingPathComponent("WakeWord", isDirectory: true)
    }

    private static func loadableModelURL() throws -> URL {
        if let compiled = discoverCompiledModelURL() {
            return compiled
        }
        if let source = discoverSourceModelURL() {
            return try MLModel.compileModel(at: source)
        }
        throw CoreMLWakeWordError.modelMissing(modelDirectoryURL.path)
    }

    private static func discoverCompiledModelURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "JarvisWakeWord", withExtension: "mlmodelc") {
            return bundled
        }
        let candidate = modelDirectoryURL.appendingPathComponent("JarvisWakeWord.mlmodelc", isDirectory: true)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    private static func discoverSourceModelURL() -> URL? {
        if let bundled = Bundle.main.url(forResource: "JarvisWakeWord", withExtension: "mlmodel") {
            return bundled
        }
        let candidate = modelDirectoryURL.appendingPathComponent("JarvisWakeWord.mlmodel", isDirectory: false)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }
}

private final class CoreMLWakeWordObserver: NSObject, SNResultsObserving {
    private let wakeWords: [String]
    private let confidenceThreshold: Double
    private let onDetected: (String, Double) -> Void

    init(
        wakeWords: [String],
        confidenceThreshold: Double,
        onDetected: @escaping (String, Double) -> Void
    ) {
        self.wakeWords = wakeWords.map(Self.normalized)
        self.confidenceThreshold = confidenceThreshold
        self.onDetected = onDetected
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else {
            return
        }
        guard let best = result.classifications.max(by: { $0.confidence < $1.confidence }) else {
            return
        }
        let identifier = Self.normalized(best.identifier)
        guard best.confidence >= confidenceThreshold else {
            return
        }
        guard identifier.contains("jarvis")
            || wakeWords.contains(where: { identifier.contains($0) })
            || identifier == "wake_word" else {
            return
        }
        onDetected(best.identifier, best.confidence)
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        DiagnosticsFileLog.shared.log(
            category: "wake-word",
            event: "coreml_failed",
            fields: ["error": error.localizedDescription]
        )
    }

    func requestDidComplete(_ request: SNRequest) {}

    private static func normalized(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CoreMLWakeWordError: LocalizedError {
    case noWakeWords
    case noInputDevice(String)
    case modelMissing(String)

    var errorDescription: String? {
        switch self {
        case .noWakeWords:
            return "Configure pelo menos uma wake word"
        case .noInputDevice(let summary):
            return "Nenhum microfone de entrada utilizavel encontrado (\(summary))"
        case .modelMissing(let path):
            return "Modelo JarvisWakeWord.mlmodelc ausente em \(path)"
        }
    }
}
