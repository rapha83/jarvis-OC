import Foundation

enum LocalTTSEngine: String, CaseIterable, Identifiable {
    case ttsKitNeural
    case azureNeural
    case customCommand
    case appleSystem
    case appleNeuralEnhanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ttsKitNeural:
            return "TTSKit Neural"
        case .azureNeural:
            return "Azure Neural (F0)"
        case .customCommand:
            return "TTS local por comando"
        case .appleSystem:
            return "Apple Speech"
        case .appleNeuralEnhanced:
            return "Apple Neural/Enhanced"
        }
    }

    var detail: String {
        switch self {
        case .ttsKitNeural:
            return "Modelo neural local Core ML; baixa/cacheia no primeiro uso"
        case .azureNeural:
            return "Azure AI Speech Neural; use um recurso Free F0"
        case .customCommand:
            return "Executa um comando local que gera audio para o Jarvis tocar"
        case .appleSystem:
            return "Voz padrao do macOS"
        case .appleNeuralEnhanced:
            return "Prefere vozes locais enhanced/premium instaladas"
        }
    }
}
