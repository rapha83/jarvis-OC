import AppKit
import Carbon
import Foundation

@MainActor
final class GlobalHotKeyService {
    private enum HotKeyID {
        static let voice: UInt32 = 1
        static let text: UInt32 = 2
    }

    private let signature = OSType(0x4A415256) // JARV
    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]

    func start(
        voice: HotKey?,
        text: HotKey?,
        onVoice: @escaping () -> Void,
        onText: @escaping () -> Void
    ) throws {
        stop()
        guard voice != nil || text != nil else {
            return
        }

        try installHandlerIfNeeded()

        if let voice {
            try register(voice, id: HotKeyID.voice)
            actions[HotKeyID.voice] = onVoice
        }
        if let text {
            try register(text, id: HotKeyID.text)
            actions[HotKeyID.text] = onText
        }
    }

    func stop() {
        for reference in hotKeyRefs.values {
            UnregisterEventHotKey(reference)
        }
        hotKeyRefs.removeAll()
        actions.removeAll()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    private func installHandlerIfNeeded() throws {
        guard eventHandler == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else {
                    return noErr
                }
                let service = Unmanaged<GlobalHotKeyService>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr {
                    Task { @MainActor in
                        service.fire(id: hotKeyID.id)
                    }
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )

        guard status == noErr else {
            throw HotKeyError.installFailed(status)
        }
    }

    private func register(_ hotKey: HotKey, id: UInt32) throws {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr, let reference else {
            throw HotKeyError.registerFailed(hotKey.displayName, status)
        }
        hotKeyRefs[id] = reference
    }

    private func fire(id: UInt32) {
        actions[id]?()
    }
}

enum HotKeyError: LocalizedError {
    case installFailed(OSStatus)
    case registerFailed(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .installFailed(let status):
            return "Nao consegui registrar o listener de atalhos (erro \(status))."
        case .registerFailed(let hotKey, let status):
            return "Nao consegui registrar o atalho \(hotKey) (erro \(status))."
        }
    }
}
