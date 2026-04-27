import Foundation

enum TextOverlayResponseMode: String, CaseIterable, Identifiable {
    case voice
    case text

    var id: String { rawValue }

    var title: String {
        switch self {
        case .voice:
            return "Voz"
        case .text:
            return "Texto"
        }
    }
}
