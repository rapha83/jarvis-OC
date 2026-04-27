import AppKit
import SwiftUI

@MainActor
final class VoiceOverlayState: ObservableObject {
    @Published var title = "JARVIS"
    @Published var detail = ""
    @Published var transcript = ""
    @Published var level: Float = 0
    @Published var status: AssistantStatus = .stopped
}

@MainActor
final class VoiceOverlayController {
    static let shared = VoiceOverlayController()

    private let state = VoiceOverlayState()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private var onCancel: (() -> Void)?

    func show(onCancel: @escaping () -> Void) {
        hideTask?.cancel()
        self.onCancel = onCancel

        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 128),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
            let hostingView = NSHostingView(rootView: VoiceOverlayView(state: state) { [weak self] in
                self?.onCancel?()
            })
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            hostingView.layer?.cornerRadius = 22
            hostingView.layer?.cornerCurve = .continuous
            hostingView.layer?.masksToBounds = true
            panel.contentView = hostingView
            self.panel = panel
        }

        positionPanel()
        panel?.orderFrontRegardless()
    }

    func update(status: AssistantStatus, transcript: String, level: Float) {
        state.status = status
        state.title = status.title
        state.detail = status.detail
        state.transcript = transcript
        state.level = level
    }

    func hide(after delay: TimeInterval = 0) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            await MainActor.run {
                self?.panel?.orderOut(nil)
            }
        }
    }

    private func positionPanel() {
        guard let panel else {
            return
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = panel.frame.size
        let x = screen.midX - size.width / 2
        let y = screen.maxY - size.height - 24
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
