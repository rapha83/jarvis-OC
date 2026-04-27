import Foundation

struct WakeWordDetection: Equatable {
    let transcript: String
    let commandHint: String?
    let trigger: String

    var hasCommandHint: Bool {
        guard let commandHint else {
            return false
        }
        return !commandHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
