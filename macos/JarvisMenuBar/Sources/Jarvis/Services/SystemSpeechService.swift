import AVFoundation
import Foundation

@MainActor
final class SystemSpeechService: NSObject, AVSpeechSynthesizerDelegate {
    private var synthesizer: AVSpeechSynthesizer?
    private var continuation: CheckedContinuation<PlaybackResult, Never>?
    private var watchdogTask: Task<Void, Never>?
    private(set) var lastVoiceSummary = "Voz nao usada nesta sessao"

    func speak(
        _ text: String,
        localeID: String = "pt-BR",
        engine: LocalTTSEngine = .appleSystem
    ) async -> PlaybackResult {
        let clean = Self.stripEmoji(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return .failed
        }

        stop()

        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        self.synthesizer = synthesizer

        let utterance = AVSpeechUtterance(string: clean)
        if let voice = Self.selectVoice(localeID: localeID, engine: engine) {
            utterance.voice = voice
            lastVoiceSummary = "\(voice.name) (\(voice.language), \(Self.qualityName(voice.quality)))"
        } else {
            lastVoiceSummary = "Indisponivel para \(localeID)"
        }
        utterance.rate = 0.48
        utterance.pitchMultiplier = 0.88
        utterance.volume = 0.96
        utterance.postUtteranceDelay = 0.04

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            synthesizer.speak(utterance)

            watchdogTask = Task { [weak self] in
                let seconds = min(max(Double(clean.count) / 12.0, 2.0) + 4.0, 180.0)
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                await MainActor.run {
                    guard let self, self.continuation != nil else {
                        return
                    }
                    self.finish(.failed)
                }
            }
        }
    }

    func stop() {
        synthesizer?.stopSpeaking(at: .immediate)
        finish(.stopped)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.synthesizer === synthesizer else {
                return
            }
            self.finish(.finished)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard self.synthesizer === synthesizer else {
                return
            }
            self.finish(.stopped)
        }
    }

    private func finish(_ result: PlaybackResult) {
        watchdogTask?.cancel()
        watchdogTask = nil
        synthesizer?.delegate = nil
        synthesizer = nil
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }

    static func voiceSummary(localeID: String, engine: LocalTTSEngine) -> String {
        guard let voice = selectVoice(localeID: localeID, engine: engine) else {
            return "Indisponivel para \(localeID)"
        }
        let quality = qualityName(voice.quality)
        switch engine {
        case .ttsKitNeural:
            return "Fallback Apple \(voice.name) (\(voice.language), \(quality))"
        case .azureNeural:
            return "Fallback Apple para Azure \(voice.name) (\(voice.language), \(quality))"
        case .customCommand:
            return "Fallback Apple para comando local \(voice.name) (\(voice.language), \(quality))"
        case .appleSystem:
            return "OK \(voice.name) (\(voice.language), \(quality))"
        case .appleNeuralEnhanced:
            let isHighQuality = voice.quality.rawValue > AVSpeechSynthesisVoiceQuality.default.rawValue
            return isHighQuality
                ? "OK \(voice.name) (\(voice.language), \(quality))"
                : "OK \(voice.name) (\(voice.language)); voz enhanced/premium nao instalada"
        }
    }

    private static func selectVoice(localeID: String, engine: LocalTTSEngine) -> AVSpeechSynthesisVoice? {
        let localePrefix = localeID.split(separator: "-").first.map(String.init) ?? localeID

        let voices = AVSpeechSynthesisVoice.speechVoices()
        let exact = voices.filter { $0.language.caseInsensitiveCompare(localeID) == .orderedSame }
        let prefix = voices.filter {
            $0.language.lowercased().hasPrefix(localePrefix.lowercased())
        }
        let candidates = (exact + prefix).deduplicatedByIdentifier()
        let defaultVoice = AVSpeechSynthesisVoice(language: localeID)
            ?? AVSpeechSynthesisVoice(language: localePrefix)

        guard !candidates.isEmpty else {
            return defaultVoice
        }

        return candidates.max { lhs, rhs in
            voiceScore(lhs, engine: engine) < voiceScore(rhs, engine: engine)
        } ?? defaultVoice
    }

    private static func qualityName(_ quality: AVSpeechSynthesisVoiceQuality) -> String {
        switch quality.rawValue {
        case AVSpeechSynthesisVoiceQuality.default.rawValue:
            return "default"
        case AVSpeechSynthesisVoiceQuality.enhanced.rawValue:
            return "enhanced"
        default:
            return "premium"
        }
    }

    private static func stripEmoji(_ text: String) -> String {
        String(text.unicodeScalars.filter { scalar in
            let value = scalar.value
            return !(
                (0x1F000...0x1FAFF).contains(value)
                || (0x2600...0x27BF).contains(value)
                || value == 0x200D
                || value == 0xFE0E
                || value == 0xFE0F
            )
        })
    }

    private static func voiceScore(_ voice: AVSpeechSynthesisVoice, engine: LocalTTSEngine) -> Int {
        let name = voice.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        let identifier = voice.identifier.lowercased()
        let quality = voice.quality.rawValue
        let maleBonus = masculineVoiceRank(name: name, identifier: identifier)
        let femininePenalty = feminineVoicePenalty(name: name, identifier: identifier)
        let qualityWeight = engine == .appleNeuralEnhanced ? 120 : 30
        return maleBonus + (quality * qualityWeight) - femininePenalty
    }

    private static func masculineVoiceRank(name: String, identifier: String) -> Int {
        let rankedNames = [
            "felipe": 1_100,
            "thiago": 1_080,
            "joao": 1_060,
            "daniel": 1_030,
            "alex": 1_020,
            "eddy": 990,
            "reed": 980,
            "rocko": 970,
            "grandpa": 940,
            "fred": 920,
            "thomas": 900
        ]
        for (candidate, score) in rankedNames where name.contains(candidate) || identifier.contains(candidate) {
            return score
        }
        return 0
    }

    private static func feminineVoicePenalty(name: String, identifier: String) -> Int {
        let feminineNames = ["luciana", "joana", "flo", "grandma", "sandy", "shelley", "maria", "helena"]
        return feminineNames.contains { name.contains($0) || identifier.contains($0) } ? 700 : 0
    }
}

private extension Array where Element == AVSpeechSynthesisVoice {
    func deduplicatedByIdentifier() -> [AVSpeechSynthesisVoice] {
        var seen = Set<String>()
        return filter { voice in
            seen.insert(voice.identifier).inserted
        }
    }
}
