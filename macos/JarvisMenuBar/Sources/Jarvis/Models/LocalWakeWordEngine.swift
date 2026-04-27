import Foundation

enum LocalWakeWordEngine: String, CaseIterable, Identifiable {
    case coreMLKeywordSpotter
    case speechAnalyzer
    case appleSpeech
    case appleCommandRecognizer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .coreMLKeywordSpotter:
            return "Core ML Jarvis"
        case .speechAnalyzer:
            return "SpeechAnalyzer macOS 26"
        case .appleSpeech:
            return "Apple Speech"
        case .appleCommandRecognizer:
            return "Detector dedicado local"
        }
    }

    var detail: String {
        switch self {
        case .coreMLKeywordSpotter:
            return "Keyword spotter local dedicado; requer JarvisWakeWord.mlmodelc"
        case .speechAnalyzer:
            return "Experimental; usa fallback Apple Speech enquanto o modo continuo nao estiver confiavel"
        case .appleSpeech:
            return "Reconhecimento continuo do macOS"
        case .appleCommandRecognizer:
            return "Legado; pode pedir download do macOS, entao o app usa fallback Apple Speech"
        }
    }
}
