import AppKit
import SwiftUI

enum SettingsWindowFocusService {
    private static let title = "Preferencias - JARVIS"

    @MainActor
    static func configure(_ window: NSWindow) {
        window.title = title
        window.collectionBehavior.insert(.moveToActiveSpace)
        focus(window)
    }

    @MainActor
    static func focusSoon() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            focusKnownWindow()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            focusKnownWindow()
        }
    }

    @MainActor
    private static func focusKnownWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == title || $0.title.localizedCaseInsensitiveContains("settings") }) {
            focus(window)
        }
    }

    @MainActor
    private static func focus(_ window: NSWindow) {
        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

struct SettingsWindowAccessor: NSViewRepresentable {
    let onWindow: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = SettingsWindowProbeView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? SettingsWindowProbeView else {
            return
        }
        view.onWindow = onWindow
        view.reportWindowIfNeeded()
    }
}

private final class SettingsWindowProbeView: NSView {
    var onWindow: (@MainActor (NSWindow) -> Void)?
    private weak var reportedWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportWindowIfNeeded()
    }

    func reportWindowIfNeeded() {
        guard let window else {
            return
        }
        guard reportedWindow !== window else {
            return
        }
        reportedWindow = window
        Task { @MainActor in
            onWindow?(window)
        }
    }
}
