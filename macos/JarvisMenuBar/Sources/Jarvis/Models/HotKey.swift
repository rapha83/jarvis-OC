import AppKit
import Carbon
import Foundation

struct HotKey: Codable, Equatable, Hashable {
    static let supportedModifierFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    static let defaultVoice = HotKey(keyCode: 38, modifiers: [.command, .option, .control])
    static let defaultText = HotKey(keyCode: 40, modifiers: [.command, .option, .control])

    let keyCode: UInt32
    let modifierFlagsRaw: UInt

    init(keyCode: UInt32, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifierFlagsRaw = modifiers.intersection(Self.supportedModifierFlags).rawValue
    }

    init?(event: NSEvent) {
        guard event.keyCode != 53 else {
            return nil
        }
        let modifiers = event.modifierFlags.intersection(Self.supportedModifierFlags)
        guard !modifiers.isEmpty else {
            return nil
        }
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRaw)
            .intersection(Self.supportedModifierFlags)
    }

    var carbonModifiers: UInt32 {
        var modifiers: UInt32 = 0
        let flags = modifierFlags
        if flags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        if flags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if flags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }
        if flags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        return modifiers
    }

    var displayName: String {
        let symbols = [
            modifierFlags.contains(.control) ? "⌃" : "",
            modifierFlags.contains(.option) ? "⌥" : "",
            modifierFlags.contains(.shift) ? "⇧" : "",
            modifierFlags.contains(.command) ? "⌘" : ""
        ].joined()
        return "\(symbols)\(Self.keyName(for: keyCode))"
    }

    static func keyName(for keyCode: UInt32) -> String {
        keyNames[keyCode] ?? "Key \(keyCode)"
    }

    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";",
        42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}

enum HotKeyCaptureTarget: Equatable {
    case voice
    case text
}
