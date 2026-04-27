import Foundation

struct TTSProviderAttempt: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let provider: String
    let voice: String
    let characterCount: Int
    let durationMs: Int
    let result: String
    let fallbackReason: String?

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        provider: String,
        voice: String,
        characterCount: Int,
        durationMs: Int,
        result: String,
        fallbackReason: String? = nil
    ) {
        self.id = id
        self.date = date
        self.provider = provider
        self.voice = voice
        self.characterCount = characterCount
        self.durationMs = durationMs
        self.result = result
        self.fallbackReason = fallbackReason
    }
}
