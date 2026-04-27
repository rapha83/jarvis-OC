import Foundation

#if canImport(WhisperKit)
import WhisperKit
#endif

struct WhisperCoreMLRuntimeStatus: Equatable {
    let isRuntimeAvailable: Bool
    let modelPath: String?
    let summary: String
}

@MainActor
final class WhisperCoreMLRuntime {
    static let shared = WhisperCoreMLRuntime()

    private let fileManager = FileManager.default

    var modelDirectoryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return appSupport
            .appendingPathComponent("JARVIS", isDirectory: true)
            .appendingPathComponent("WhisperCoreML", isDirectory: true)
    }

    func status() -> WhisperCoreMLRuntimeStatus {
        let modelPath = discoverModelPath()?.path
        let runtimeAvailable = Self.isWhisperKitLinked()

        if runtimeAvailable, let modelPath {
            return WhisperCoreMLRuntimeStatus(
                isRuntimeAvailable: true,
                modelPath: modelPath,
                summary: "Whisper/Core ML pronto"
            )
        }

        if !runtimeAvailable {
            return WhisperCoreMLRuntimeStatus(
                isRuntimeAvailable: false,
                modelPath: modelPath,
                summary: "WhisperKit nao esta embutido no build"
            )
        }

        return WhisperCoreMLRuntimeStatus(
            isRuntimeAvailable: true,
            modelPath: nil,
            summary: "WhisperKit pronto; modelo sera baixado/cacheado no primeiro uso"
        )
    }

    func transcribe(wavData: Data, localeID: String) async throws -> String {
        let modelPath = discoverModelPath()
        guard status().isRuntimeAvailable else {
            throw WhisperCoreMLError.runtimeUnavailable(status().summary)
        }
        guard !wavData.isEmpty else {
            return ""
        }

        #if canImport(WhisperKit)
        let tempURL = fileManager.temporaryDirectory
            .appendingPathComponent("jarvis-whisper-\(UUID().uuidString)", isDirectory: false)
            .appendingPathExtension("wav")
        try wavData.write(to: tempURL, options: .atomic)
        defer { try? fileManager.removeItem(at: tempURL) }

        let pipe: WhisperKit
        if let modelPath {
            pipe = try await WhisperKit(WhisperKitConfig(modelFolder: modelPath.path))
        } else {
            pipe = try await WhisperKit()
        }
        let decodeOptions = DecodingOptions(language: languageCode(from: localeID))
        let results = try await pipe.transcribe(audioPath: tempURL.path, decodeOptions: decodeOptions)
        return results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        #else
        _ = modelPath
        _ = localeID
        throw WhisperCoreMLError.runtimeUnavailable("WhisperKit nao esta embutido no build")
        #endif
    }

    func ensureModelDirectory() throws -> URL {
        try fileManager.createDirectory(at: modelDirectoryURL, withIntermediateDirectories: true)
        return modelDirectoryURL
    }

    private func discoverModelPath() -> URL? {
        if let bundled = Bundle.main.url(forResource: "WhisperCoreML", withExtension: nil) {
            return bundled
        }

        let dir = modelDirectoryURL
        guard let children = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        return children.first { url in
            let name = url.lastPathComponent.lowercased()
            return name.contains("whisper") || name.contains("openai")
        }
    }

    private func languageCode(from localeID: String) -> String {
        localeID
            .split(separator: "-")
            .first
            .map(String.init)?
            .lowercased() ?? "pt"
    }

    private static func isWhisperKitLinked() -> Bool {
        #if canImport(WhisperKit)
        return true
        #else
        return false
        #endif
    }
}

enum WhisperCoreMLError: LocalizedError {
    case runtimeUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .runtimeUnavailable(let reason):
            return reason
        }
    }
}
