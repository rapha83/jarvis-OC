import Foundation

struct TranscriptionResponse: Decodable {
    let type: String
    let transcription: String?
    let originalTranscription: String?
    let normalizedTranscription: String?
    let normalizationCorrections: [String]?
    let message: String?
}
