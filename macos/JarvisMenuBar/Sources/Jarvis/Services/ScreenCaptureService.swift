import AppKit
import Foundation
@preconcurrency import ScreenCaptureKit

@MainActor
final class ScreenCaptureService {
    enum CaptureError: LocalizedError {
        case notAuthorized
        case noDisplays
        case invalidCapture(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Permissao de gravacao de tela nao autorizada"
            case .noDisplays:
                return "Nenhuma tela disponivel"
            case .invalidCapture(let message):
                return message
            }
        }
    }

    struct Snapshot {
        let image: CGImage
        let width: Int
        let height: Int
        let displayIndex: Int
    }

    func availableDisplays() async throws -> [ScreenDisplayOption] {
        guard PermissionsService.isScreenRecordingAuthorized() else {
            throw CaptureError.notAuthorized
        }

        let content = try await SCShareableContent.current
        return content.displays
            .sorted { $0.displayID < $1.displayID }
            .enumerated()
            .map { index, display in
                ScreenDisplayOption(
                    id: index,
                    title: index == 0 ? "Tela principal" : "Tela \(index + 1)",
                    size: "\(display.width)x\(display.height)"
                )
            }
    }

    func capture(options: ScreenCaptureOptions = ScreenCaptureOptions(
        displayIndex: 0,
        maxWidth: 1400,
        showsCursor: true
    )) async throws -> Snapshot {
        guard PermissionsService.isScreenRecordingAuthorized() else {
            throw CaptureError.notAuthorized
        }

        let content = try await SCShareableContent.current
        let displays = content.displays.sorted { $0.displayID < $1.displayID }
        guard !displays.isEmpty else {
            throw CaptureError.noDisplays
        }
        let displayIndex = min(max(options.displayIndex, 0), displays.count - 1)
        let display = displays[displayIndex]

        let targetSize = Self.targetSize(
            width: display.width,
            height: display.height,
            maxWidth: options.maxWidth
        )
        let config = SCStreamConfiguration()
        config.width = targetSize.width
        config.height = targetSize.height
        config.showsCursor = options.showsCursor

        let filter = SCContentFilter(display: display, excludingWindows: [])
        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return Snapshot(image: image, width: image.width, height: image.height, displayIndex: displayIndex)
        } catch {
            throw CaptureError.invalidCapture(error.localizedDescription)
        }
    }

    private static func targetSize(width: Int, height: Int, maxWidth: Int) -> (width: Int, height: Int) {
        guard width > 0, height > 0, width > maxWidth else {
            return (width: width, height: height)
        }
        let scale = Double(maxWidth) / Double(width)
        return (width: maxWidth, height: max(1, Int((Double(height) * scale).rounded())))
    }
}
