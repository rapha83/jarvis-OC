import Foundation

enum LocalSTTEngine: String, CaseIterable, Identifiable {
    case appleSpeech
    case speechAnalyzer
    case whisperCoreML

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleSpeech:
            return "Apple Speech"
        case .speechAnalyzer:
            return "SpeechAnalyzer macOS 26"
        case .whisperCoreML:
            return "Whisper/Core ML"
        }
    }

    var detail: String {
        switch self {
        case .appleSpeech:
            return "SFSpeechRecognizer tradicional do macOS"
        case .speechAnalyzer:
            return "Pipeline moderno do macOS 26 com resultados volateis"
        case .whisperCoreML:
            return "WhisperKit/Core ML local"
        }
    }
}
