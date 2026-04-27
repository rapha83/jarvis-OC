import Foundation

struct InteractionRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let date: Date
    let source: String
    let transcript: String
    let response: String

    init(id: UUID = UUID(), date: Date = Date(), source: String, transcript: String, response: String) {
        self.id = id
        self.date = date
        self.source = source
        self.transcript = transcript
        self.response = response
    }
}
