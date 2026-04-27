import Foundation

enum NativeVoiceDirectiveParser {
    static func extract(from text: String) -> (VoiceDirective?, String) {
        let original = text
        let trimmedLeft = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedLeft.hasPrefix("{"),
              let data = trimmedLeft.data(using: .utf8) else {
            return (nil, original)
        }

        let decoder = JSONDecoder()
        if let payload = try? decoder.decode(DirectiveEnvelope.self, from: data),
           let directive = payload.jarvisDirective ?? payload.directive {
            return (directive, "")
        }

        guard let firstLineRange = trimmedLeft.range(of: "\n") else {
            return (nil, original)
        }

        let firstLine = String(trimmedLeft[..<firstLineRange.lowerBound])
        guard let firstLineData = firstLine.data(using: .utf8) else {
            return (nil, original)
        }

        if let payload = try? decoder.decode(DirectiveEnvelope.self, from: firstLineData),
           let directive = payload.jarvisDirective ?? payload.directive {
            let rest = String(trimmedLeft[firstLineRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (directive, rest)
        }

        if let directive = try? decoder.decode(VoiceDirective.self, from: firstLineData) {
            let rest = String(trimmedLeft[firstLineRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (directive, rest)
        }

        return (nil, original)
    }

    private struct DirectiveEnvelope: Decodable {
        let jarvisDirective: VoiceDirective?
        let directive: VoiceDirective?
    }
}
