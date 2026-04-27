import AppKit
import SwiftUI

@MainActor
final class TextCommandOverlayState: ObservableObject {
    @Published var text = ""
    @Published var command = ""
    @Published var response = ""
    @Published var phase: TextCommandOverlayPhase = .input
}

@MainActor
final class TextCommandOverlayController {
    static let shared = TextCommandOverlayController()

    private let state = TextCommandOverlayState()
    private var panel: TextCommandPanel?
    private var hideTask: Task<Void, Never>?
    private var onSubmit: ((String) -> Void)?

    var shouldNotifyOnCompletion: Bool {
        !NSApp.isActive || !(panel?.isVisible ?? false)
    }

    func show(onSubmit: @escaping (String) -> Void) {
        hideTask?.cancel()
        state.text = ""
        state.command = ""
        state.response = ""
        state.phase = .input
        self.onSubmit = onSubmit

        let view = TextCommandOverlayView(state: state) { [weak self] text in
            self?.submit(text)
        } onCancel: { [weak self] in
            self?.hide()
        }

        if panel == nil {
            let panel = TextCommandPanel(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 86),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            self.panel = panel
        }

        let hostingView = NSHostingView(rootView: view)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = 30
        hostingView.layer?.cornerCurve = .continuous
        panel?.contentView = hostingView
        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func updateResponse(_ text: String, isFinal: Bool = false) {
        hideTask?.cancel()
        state.response = text
        state.phase = isFinal ? .done : .responding
        positionPanel()
    }

    func updateStatus(_ text: String) {
        hideTask?.cancel()
        state.response = text
        state.phase = .processing
        positionPanel()
    }

    func showError(_ text: String) {
        hideTask?.cancel()
        state.response = text
        state.phase = .error
        positionPanel()
    }

    func hide(after delay: TimeInterval = 0) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            await MainActor.run {
                self?.panel?.orderOut(nil)
                self?.onSubmit = nil
            }
        }
    }

    private func submit(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            hide()
            return
        }
        state.command = trimmed
        state.text = ""
        state.response = "Enviando..."
        state.phase = .processing
        positionPanel()
        let action = onSubmit
        action?(trimmed)
    }

    private func positionPanel() {
        guard let panel else {
            return
        }

        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(720, max(420, visibleFrame.width - 96))
        let size = NSSize(width: width, height: preferredHeight(width: width))
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 30
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private func preferredHeight(width: CGFloat) -> CGFloat {
        guard state.phase != .input else {
            return 86
        }
        let text = state.response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return 112
        }
        let usableWidth = max(width - 94, 320)
        let estimatedCharactersPerLine = max(Int(usableWidth / 8.8), 36)
        let estimatedLines = min(3, max(1, Int(ceil(Double(text.count) / Double(estimatedCharactersPerLine)))))
        return 104 + CGFloat(estimatedLines * 24)
    }
}

private final class TextCommandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum TextCommandOverlayPhase: Equatable {
    case input
    case processing
    case responding
    case done
    case error
}
