import Foundation

@MainActor
final class NativeSentenceSpeechStreamer {
    private let speak: @MainActor (String) async -> PlaybackResult
    private let stopSpeech: @MainActor () -> Void
    private var generation = 0
    private var sourceText = ""
    private var spokenOffset = 0
    private var queue: [String] = []
    private var isSpeaking = false
    private var finishContinuation: CheckedContinuation<Void, Never>?

    init(
        speak: @escaping @MainActor (String) async -> PlaybackResult,
        stop: @escaping @MainActor () -> Void
    ) {
        self.speak = speak
        self.stopSpeech = stop
    }

    func begin() {
        generation += 1
        sourceText = ""
        spokenOffset = 0
        queue = []
        isSpeaking = false
        finishContinuation?.resume()
        finishContinuation = nil
        stopSpeech()
    }

    func observe(_ text: String) {
        sourceText = text
        enqueueSegments(includeTail: false)
        drainIfNeeded(generation: generation)
    }

    func finish(finalText: String) async {
        sourceText = finalText
        enqueueSegments(includeTail: true)
        drainIfNeeded(generation: generation)

        guard isSpeaking || !queue.isEmpty else {
            return
        }

        await withCheckedContinuation { continuation in
            finishContinuation = continuation
        }
    }

    func stop() {
        generation += 1
        sourceText = ""
        spokenOffset = 0
        queue = []
        isSpeaking = false
        stopSpeech()
        finishContinuation?.resume()
        finishContinuation = nil
    }

    private func enqueueSegments(includeTail: Bool) {
        guard !sourceText.isEmpty else {
            return
        }

        let safeOffset = min(spokenOffset, sourceText.count)
        var cursor = sourceText.index(sourceText.startIndex, offsetBy: safeOffset)
        var segmentStart = cursor
        var newOffset = safeOffset
        var newSegments: [String] = []

        while cursor < sourceText.endIndex {
            let character = sourceText[cursor]
            if character.isJarvisStrongSentenceBoundary {
                let end = sourceText.index(after: cursor)
                appendSegment(sourceText[segmentStart..<end], to: &newSegments)
                segmentStart = end
                newOffset = sourceText.distance(from: sourceText.startIndex, to: end)
            } else if character.isJarvisSoftPhraseBoundary {
                let end = sourceText.index(after: cursor)
                let phrase = sourceText[segmentStart..<end]
                if shouldFlushSoftPhrase(phrase) {
                    appendSegment(phrase, to: &newSegments)
                    segmentStart = end
                    newOffset = sourceText.distance(from: sourceText.startIndex, to: end)
                }
            }
            cursor = sourceText.index(after: cursor)
        }

        if includeTail, segmentStart < sourceText.endIndex {
            appendSegment(sourceText[segmentStart..<sourceText.endIndex], to: &newSegments)
            newOffset = sourceText.count
        }

        spokenOffset = newOffset
        queue.append(contentsOf: newSegments)
    }

    private func appendSegment(_ substring: Substring, to segments: inout [String]) {
        let text = String(substring)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else {
            return
        }
        guard queue.last != text, segments.last != text else {
            return
        }
        segments.append(text)
    }

    private func shouldFlushSoftPhrase(_ substring: Substring) -> Bool {
        let text = String(substring)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 72 else {
            return false
        }
        let words = text.split { $0.isWhitespace || $0.isNewline }
        return words.count >= 9
    }

    private func drainIfNeeded(generation: Int) {
        guard !isSpeaking else {
            return
        }

        guard !queue.isEmpty else {
            finishContinuation?.resume()
            finishContinuation = nil
            return
        }

        isSpeaking = true
        let phrase = queue.removeFirst()
        Task { [weak self] in
            guard let self else {
                return
            }
            _ = await self.speak(phrase)
            await MainActor.run {
                guard self.generation == generation else {
                    return
                }
                self.isSpeaking = false
                self.drainIfNeeded(generation: generation)
            }
        }
    }
}

private extension Character {
    var isJarvisStrongSentenceBoundary: Bool {
        self == "." || self == "!" || self == "?" || self == "\n"
    }

    var isJarvisSoftPhraseBoundary: Bool {
        self == "," || self == ";" || self == ":"
    }
}
