import AppKit
import Foundation

@MainActor
final class PushToTalkService {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var isRightControlDown = false
    private var onTrigger: (() -> Void)?

    func start(onTrigger: @escaping () -> Void) {
        stop()
        self.onTrigger = onTrigger

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        localMonitor = nil
        globalMonitor = nil
        isRightControlDown = false
        onTrigger = nil
    }

    private func handle(_ event: NSEvent) {
        // Right Control on Apple keyboards.
        guard event.keyCode == 62 else {
            return
        }

        let isDown = event.modifierFlags.contains(.control)
        if isDown && !isRightControlDown {
            isRightControlDown = true
            onTrigger?()
        } else if !isDown {
            isRightControlDown = false
        }
    }
}
