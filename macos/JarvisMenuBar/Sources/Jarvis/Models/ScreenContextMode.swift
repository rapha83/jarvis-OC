import Foundation

enum ScreenContextMode: String, CaseIterable, Identifiable {
    case onDemand
    case always

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onDemand:
            return "Sob demanda"
        case .always:
            return "Sempre"
        }
    }

    var detail: String {
        switch self {
        case .onDemand:
            return "Quando o comando mencionar tela, janela ou o que esta aqui"
        case .always:
            return "Em todo comando de voz"
        }
    }

    func shouldCapture(for text: String) -> Bool {
        switch self {
        case .always:
            return true
        case .onDemand:
            return Self.looksScreenRelated(text)
        }
    }

    private static func looksScreenRelated(_ text: String) -> Bool {
        let normalized = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let patterns = [
            "tela", "janela", "monitor", "imagem", "pagina", "site", "app",
            "ocr", "print", "screenshot", "captura", "leia", "ler",
            "veja", "olhe", "olha", "aparece", "mostrando", "aqui",
            "isso aqui", "nessa tela", "nesta tela", "nesse app", "nesta janela"
        ]
        return patterns.contains { normalized.contains($0) }
    }
}
