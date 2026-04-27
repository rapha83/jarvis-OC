import Foundation

struct PermissionSnapshot: Equatable {
    var microphone = false
    var speechRecognition = false
    var screenRecording = false

    var summary: String {
        let granted = [
            microphone ? "mic" : nil,
            speechRecognition ? "fala" : nil,
            screenRecording ? "tela" : nil
        ].compactMap { $0 }

        if granted.count == 3 {
            return "Todas OK"
        }
        return "OK: \(granted.isEmpty ? "nenhuma" : granted.joined(separator: ", "))"
    }
}
