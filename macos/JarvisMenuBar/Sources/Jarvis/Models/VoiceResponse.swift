import Foundation

struct VoiceResponse: Decodable {
    let type: String
    let transcription: String?
    let originalTranscription: String?
    let normalizationCorrections: [String]?
    let text: String?
    let expectingReply: Bool?
    let audioMime: String?
    let audioBase64: String?
    let message: String?
    let directive: VoiceDirective?

    var audioData: Data? {
        guard let audioBase64, !audioBase64.isEmpty else {
            return nil
        }
        return Data(base64Encoded: audioBase64)
    }
}
