import Foundation

struct CommandPreflightResult: Equatable {
    let shouldSend: Bool
    let reason: String
    let prompt: String

    static let accepted = CommandPreflightResult(
        shouldSend: true,
        reason: "accepted",
        prompt: ""
    )
}

enum CommandPreflightFilter {
    static func evaluate(_ text: String, allowsShortReply: Bool = false) -> CommandPreflightResult {
        let normalized = normalize(text)
        let words = normalized
            .split(separator: " ")
            .map(String.init)

        guard !normalized.isEmpty else {
            return reject("empty", prompt: "Não ouvi nada. Pode repetir?")
        }

        let letterCount = normalized.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letterCount >= 2 else {
            return reject("no_letters", prompt: "Não entendi. Pode repetir?")
        }

        if allowsShortReply, isShortReply(normalized) {
            return .accepted
        }

        if words.count == 1 {
            if isSingleWordCommand(words[0]) {
                return .accepted
            }
            return reject("single_unclear_word", prompt: "Peguei só uma palavra. Pode repetir o comando?")
        }

        if words.count == 2, words.allSatisfy(isFillerWord) {
            return reject("fillers_only", prompt: "Acho que não peguei o comando. Pode repetir?")
        }

        if let last = words.last, danglingTerms.contains(last) {
            return reject("dangling_\(last)", prompt: "A frase parece ter ficado incompleta. Pode repetir?")
        }

        if hasRepeatedNoise(normalized) {
            return reject("repeated_noise", prompt: "Não entendi com confiança. Pode repetir?")
        }

        return .accepted
    }

    private static func reject(_ reason: String, prompt: String) -> CommandPreflightResult {
        CommandPreflightResult(shouldSend: false, reason: reason, prompt: prompt)
    }

    private static func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt-BR"))
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9\s]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isShortReply(_ text: String) -> Bool {
        shortReplies.contains(text)
    }

    private static func isSingleWordCommand(_ word: String) -> Bool {
        singleWordCommands.contains(word)
    }

    private static func isFillerWord(_ word: String) -> Bool {
        fillerWords.contains(word)
    }

    private static func hasRepeatedNoise(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 5 else {
            return false
        }
        return compact.range(of: #"([a-z0-9])\1{4,}"#, options: .regularExpression) != nil
    }

    private static let shortReplies: Set<String> = [
        "sim",
        "nao",
        "não",
        "ok",
        "okay",
        "isso",
        "certo",
        "pode",
        "pode sim",
        "claro",
        "confirma",
        "confirmo",
        "continua",
        "cancela",
        "cancelar"
    ]

    private static let singleWordCommands: Set<String> = [
        "sim",
        "nao",
        "não",
        "ok",
        "pare",
        "para",
        "cancela",
        "cancelar",
        "continua",
        "luz",
        "temperatura",
        "hora",
        "data",
        "status"
    ]

    private static let fillerWords: Set<String> = [
        "e",
        "a",
        "o",
        "ah",
        "hum",
        "hã",
        "hmm",
        "tipo",
        "entao",
        "então",
        "assim"
    ]

    private static let danglingTerms: Set<String> = [
        "de",
        "do",
        "da",
        "dos",
        "das",
        "em",
        "no",
        "na",
        "nos",
        "nas",
        "para",
        "pra",
        "por",
        "com",
        "sem",
        "sobre",
        "qual",
        "quais",
        "que",
        "como",
        "quando",
        "onde",
        "porque",
        "por que",
        "the",
        "of",
        "to",
        "for",
        "with",
        "about"
    ]
}
