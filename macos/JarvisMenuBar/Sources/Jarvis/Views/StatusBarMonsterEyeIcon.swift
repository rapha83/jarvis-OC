import AppKit
import SwiftUI

struct StatusBarMonsterEyeIcon: View {
    let status: AssistantStatus

    var body: some View {
        Image(nsImage: StatusBarJarvisIcon.image())
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 19, height: 19)
            .accessibilityLabel("JARVIS")
    }
}

private enum StatusBarJarvisIcon {
    static func image() -> NSImage {
        let size = NSSize(width: 19, height: 19)
        let image = NSImage(size: size)
        image.lockFocus()
        defer {
            image.unlockFocus()
            image.isTemplate = true
        }

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let center = NSPoint(x: 9.5, y: 9.5)
        let outer = NSBezierPath(ovalIn: NSRect(x: 2.35, y: 2.35, width: 14.3, height: 14.3))
        outer.lineWidth = 1.25
        outer.lineCapStyle = .round
        outer.setLineDash([1.3, 2.4], count: 2, phase: 0)
        outer.stroke()

        let centerNode = NSBezierPath(ovalIn: NSRect(x: 6.1, y: 6.1, width: 6.8, height: 6.8))
        centerNode.lineWidth = 1.45
        centerNode.stroke()

        for node in nodes(center: center) {
            let line = NSBezierPath()
            line.move(to: center)
            line.line(to: NSPoint(
                x: center.x + (node.x - center.x) * 0.78,
                y: center.y + (node.y - center.y) * 0.78
            ))
            line.lineWidth = 1.2
            line.lineCapStyle = .round
            line.stroke()

            let dot = NSBezierPath(ovalIn: NSRect(x: node.x - 1.75, y: node.y - 1.75, width: 3.5, height: 3.5))
            dot.lineWidth = 1.35
            dot.stroke()
        }

        return image
    }

    private static func nodes(center: NSPoint) -> [NSPoint] {
        [
            NSPoint(x: center.x, y: 17.0),
            NSPoint(x: 16.0, y: 13.2),
            NSPoint(x: 16.0, y: 5.8),
            NSPoint(x: center.x, y: 2.0),
            NSPoint(x: 3.0, y: 5.8),
            NSPoint(x: 3.0, y: 13.2)
        ]
    }
}
