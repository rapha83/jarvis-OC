import AppKit
import SwiftUI

struct MonsterEyeIcon: View {
    let status: AssistantStatus
    var size: CGFloat = 22

    var body: some View {
        Image(nsImage: JarvisDragonEyeImage.image())
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .opacity(opacity)
            .frame(width: size, height: size)
            .accessibilityLabel("JARVIS")
    }

    private var opacity: Double {
        switch status {
        case .stopped:
            return 0.62
        case .requestingPermission:
            return 0.78
        case .error:
            return 0.90
        case .listening, .wakeDetected, .recording, .processing, .speaking, .awaitingFollowUp:
            return 1.0
        }
    }
}

enum JarvisDragonEyeImage {
    static func image() -> NSImage {
        if let url = Bundle.main.url(forResource: "JARVISAppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = false
            return image
        }

        if let image = NSImage(systemSymbolName: "eye", accessibilityDescription: "JARVIS") {
            image.isTemplate = true
            return image
        }

        let fallback = NSImage(size: NSSize(width: 32, height: 32))
        fallback.lockFocus()
        NSColor.labelColor.setStroke()
        let path = NSBezierPath(ovalIn: NSRect(x: 5, y: 9, width: 22, height: 14))
        path.lineWidth = 2
        path.stroke()
        NSColor.labelColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 13, y: 8, width: 6, height: 16)).fill()
        fallback.unlockFocus()
        return fallback
    }

    static func menuBarImage(opacity: CGFloat = 1.0) -> NSImage {
        let canvasSize = NSSize(width: 27, height: 18)
        let image = NSImage(size: canvasSize)
        image.isTemplate = true

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: canvasSize).fill()

        let source = self.statusImage()
        let sourceRect = nonTransparentBounds(of: source) ?? NSRect(origin: .zero, size: source.size)
        let targetHeight: CGFloat = 15.6
        let targetWidth = min(24.8, targetHeight * sourceRect.width / max(sourceRect.height, 1))
        let targetRect = NSRect(
            x: (canvasSize.width - targetWidth) / 2,
            y: ((canvasSize.height - targetHeight) / 2) - 0.35,
            width: targetWidth,
            height: targetHeight
        )
        source.draw(
            in: targetRect,
            from: sourceRect,
            operation: .sourceOver,
            fraction: opacity,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        image.size = canvasSize
        image.isTemplate = true
        return image
    }

    static func statusImage() -> NSImage {
        if let url = Bundle.main.url(forResource: "JARVISStatusIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            return image
        }
        return image()
    }

    static func orbImage() -> NSImage {
        guard let url = Bundle.main.url(forResource: "JARVISAppIcon", withExtension: "png"),
              let source = NSImage(contentsOf: url) else {
            return image()
        }

        let outputSize = NSSize(width: 128, height: 128)
        let image = NSImage(size: outputSize)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: outputSize).fill()

        let clipPath = NSBezierPath(ovalIn: NSRect(origin: .zero, size: outputSize))
        clipPath.addClip()

        let sourceSide = min(source.size.width, source.size.height)
        let cropSide = sourceSide * 0.72
        let sourceRect = NSRect(
            x: (source.size.width - cropSide) / 2,
            y: (source.size.height - cropSide) / 2,
            width: cropSide,
            height: cropSide
        )
        source.draw(
            in: NSRect(origin: .zero, size: outputSize),
            from: sourceRect,
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        image.isTemplate = false
        return image
    }

    private static func nonTransparentBounds(of image: NSImage) -> NSRect? {
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }

        var minX = bitmap.pixelsWide
        var minY = bitmap.pixelsHigh
        var maxX = 0
        var maxY = 0

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                guard alpha > 0.04 else {
                    continue
                }
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        guard minX <= maxX, minY <= maxY else {
            return nil
        }

        return NSRect(
            x: CGFloat(minX),
            y: CGFloat(minY),
            width: CGFloat(maxX - minX + 1),
            height: CGFloat(maxY - minY + 1)
        )
    }
}
