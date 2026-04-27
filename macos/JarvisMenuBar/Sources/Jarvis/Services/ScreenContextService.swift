import Foundation

@MainActor
final class ScreenContextService {
    private let capture = ScreenCaptureService()
    private let ocr = ScreenOCRService()

    func makeContext(ocrEnabled: Bool, options: ScreenCaptureOptions) async throws -> ScreenContextResult {
        let snapshot = try await capture.capture(options: options)
        let text: String
        if ocrEnabled {
            text = try await ocr.recognizeText(in: snapshot.image)
        } else {
            text = ""
        }

        return ScreenContextResult(
            summary: MacContextService.currentSummary(),
            ocrText: text,
            imageWidth: snapshot.width,
            imageHeight: snapshot.height,
            displayIndex: snapshot.displayIndex
        )
    }

    func availableDisplays() async throws -> [ScreenDisplayOption] {
        try await capture.availableDisplays()
    }
}
