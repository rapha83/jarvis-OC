import Foundation

struct VoiceDirective: Decodable, Equatable {
    let speak: Bool?
    let expectingReply: Bool?
    let tone: String?
}
