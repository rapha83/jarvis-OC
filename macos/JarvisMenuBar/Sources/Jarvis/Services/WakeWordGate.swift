import Foundation
import Speech

struct WakeWordSegment {
    let original: String
    let normalized: String
    let start: TimeInterval
    let duration: TimeInterval
}

enum WakeWordGate {
    private static let locale = Locale(identifier: "pt-BR")
    private static let canonicalWakeWord = "jarvis"
    private static let minPostTriggerGap: TimeInterval = 0.45
    private static let minCommandLength = 1

    static func match(result: SFSpeechRecognitionResult, wakeWords: [String] = [canonicalWakeWord]) -> WakeWordDetection? {
        let transcript = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            return nil
        }
        let normalizedWakeWords = normalizedTriggers(wakeWords)

        let segments = result.bestTranscription.segments.map {
            WakeWordSegment(
                original: $0.substring,
                normalized: normalize($0.substring),
                start: $0.timestamp,
                duration: $0.duration
            )
        }

        if let segmented = matchSegments(transcript: transcript, segments: segments, wakeWords: normalizedWakeWords) {
            return segmented
        }

        return matchTextOnly(transcript: transcript, wakeWords: normalizedWakeWords)
    }

    static func match(transcript: String, wakeWords: [String] = [canonicalWakeWord]) -> WakeWordDetection? {
        let transcript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else {
            return nil
        }
        return matchTextOnly(transcript: transcript, wakeWords: normalizedTriggers(wakeWords))
    }

    static func stripWakeWord(from transcript: String) -> String? {
        match(transcript: transcript, wakeWords: [canonicalWakeWord])?.commandHint
    }

    static func recognitionHints(for wakeWords: [String]) -> [String] {
        Array(Set(normalizedTriggers(wakeWords) + wakeWords))
            .filter { !$0.isEmpty }
    }

    private static func matchSegments(
        transcript: String,
        segments: [WakeWordSegment],
        wakeWords: [String]
    ) -> WakeWordDetection? {
        guard !segments.isEmpty else {
            return nil
        }

        for index in segments.indices where isWakeToken(segments[index].normalized, wakeWords: wakeWords) {
            let trigger = segments[index].original
            let tail = Array(segments.dropFirst(index + 1))
            let command = commandAfterTrigger(trigger: segments[index], tail: tail)
            return WakeWordDetection(transcript: transcript, commandHint: command, trigger: trigger)
        }

        return nil
    }

    private static func commandAfterTrigger(trigger: WakeWordSegment, tail: [WakeWordSegment]) -> String? {
        guard let first = tail.first else {
            return nil
        }

        let triggerEnd = trigger.start + trigger.duration
        guard first.start - triggerEnd >= minPostTriggerGap else {
            return nil
        }

        let command = tail.map(\.original).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalize(command).count >= minCommandLength else {
            return nil
        }
        return command
    }

    private static func matchTextOnly(transcript: String, wakeWords: [String]) -> WakeWordDetection? {
        let normalizedTranscript = normalize(transcript)
        if let phrase = wakeWords.first(where: { $0.count > 7 && normalizedTranscript.hasPrefix($0) }),
           let range = normalizedTranscript.range(of: phrase) {
            let after = normalizedTranscript[range.upperBound...]
            return WakeWordDetection(
                transcript: transcript,
                commandHint: after.count >= minCommandLength ? String(after) : nil,
                trigger: phrase
            )
        }

        let tokens = tokenize(transcript)
        guard let wakeIndex = tokens.indices.first, isWakeToken(tokens[wakeIndex].normalized, wakeWords: wakeWords) else {
            return nil
        }

        let command = tokens
            .dropFirst(wakeIndex + 1)
            .map(\.original)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return WakeWordDetection(
            transcript: transcript,
            commandHint: normalize(command).count >= minCommandLength ? command : nil,
            trigger: tokens[wakeIndex].original
        )
    }

    private static func tokenize(_ text: String) -> [(original: String, normalized: String)] {
        text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .map { ($0, normalize($0)) }
            .filter { !$0.normalized.isEmpty }
    }

    private static func isWakeToken(_ token: String, wakeWords: [String]) -> Bool {
        guard token.count >= 5, token.count <= 7 else {
            return false
        }
        for wakeWord in wakeWords where wakeWord.count <= 7 {
            if token == wakeWord {
                return true
            }
            if levenshteinDistance(token, wakeWord) <= 1 {
                return true
            }
        }
        return false
    }

    private static func normalizedTriggers(_ wakeWords: [String]) -> [String] {
        var normalized = wakeWords
            .map(normalize)
            .filter { !$0.isEmpty }
        if normalized.contains(canonicalWakeWord) {
            normalized.append(contentsOf: [
                "jervis",
                "jarves",
                "jarvys",
                "javis",
                "jarbis",
                "jarviz"
            ])
        }
        normalized = Array(Set(normalized))
        return normalized.isEmpty ? [canonicalWakeWord] : normalized
    }

    private static func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: locale)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }

        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }

        return previous[b.count]
    }
}
