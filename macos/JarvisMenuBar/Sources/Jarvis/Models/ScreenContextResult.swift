import Foundation

struct ScreenContextResult {
    let summary: String
    let ocrText: String
    let imageWidth: Int
    let imageHeight: Int
    let displayIndex: Int

    var characterCount: Int {
        ocrText.count
    }

    var promptText: String {
        var parts = [
            "Captura da tela \(displayIndex + 1): \(imageWidth)x\(imageHeight).",
            summary
        ]
        let trimmed = ocrText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parts.append("Texto lido por OCR:\n\(trimmed)")
        }
        return parts.joined(separator: "\n")
    }
}
