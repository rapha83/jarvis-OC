import Foundation

struct BackendHealth: Decodable, Equatable {
    let status: String
    let agent: String?
    let defaultAgent: String?
    let openclawURL: String?
    let hasOpenClawToken: Bool?
    let openclawTokenSource: String?
    let ttsVoice: String?
    let whisperModel: String?
    let whisperBeamSize: Int?
    let whisperVadMinSilenceMs: Int?
    let whisperNoSpeechThreshold: Double?
    let sttNormalizationEnabled: Bool?
}
