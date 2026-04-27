import Foundation

struct AgentSwitchCommand {
    enum Outcome: Equatable {
        case none
        case switchTo(String)
        case reset
        case list
        case unknown(String)
    }

    static func parse(_ text: String, availableAgents: [String], defaultAgentID: String) -> Outcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .none
        }

        let normalized = normalize(trimmed)
        if normalized.contains("quais agentes")
            || normalized.contains("listar agentes")
            || normalized.contains("lista de agentes")
            || normalized.contains("mostre os agentes") {
            return .list
        }

        if normalized.contains("agente padrao")
            || normalized.contains("agente padrão")
            || normalized.contains("volte para o padrao")
            || normalized.contains("volta para o padrao") {
            return .reset
        }

        let patterns = [
            "altere para o agente",
            "alterar para o agente",
            "troque para o agente",
            "trocar para o agente",
            "mude para o agente",
            "mudar para o agente",
            "use o agente",
            "usar o agente",
            "selecionar agente",
            "selecione agente",
            "mude agente para",
            "troque agente para",
            "alterar agente para",
            "altere agente para"
        ]

        guard let rawName = extractAgentName(from: trimmed, normalized: normalized, patterns: patterns) else {
            return .none
        }

        if let match = bestMatch(rawName, availableAgents: availableAgents, defaultAgentID: defaultAgentID) {
            return .switchTo(match)
        }
        return .unknown(rawName)
    }

    private static func extractAgentName(from text: String, normalized: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let range = normalized.range(of: normalize(pattern)) else {
                continue
            }

            let distance = normalized.distance(from: normalized.startIndex, to: range.upperBound)
            let rawIndex = text.index(text.startIndex, offsetBy: min(distance, text.count))
            let suffix = String(text[rawIndex...])
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            if !suffix.isEmpty {
                return suffix
            }
        }
        return nil
    }

    private static func bestMatch(_ spoken: String, availableAgents: [String], defaultAgentID: String) -> String? {
        let allAgents = ([defaultAgentID] + availableAgents).deduplicated()
        let normalizedSpoken = compactAgentID(spoken)
        guard !normalizedSpoken.isEmpty else {
            return nil
        }

        if let exact = allAgents.first(where: { compactAgentID($0) == normalizedSpoken }) {
            return exact
        }

        return allAgents
            .map { agent in
                (agent: agent, distance: levenshteinDistance(normalizedSpoken, compactAgentID(agent)))
            }
            .filter { !$0.agent.isEmpty && $0.distance <= max(2, normalizedSpoken.count / 5) }
            .min { lhs, rhs in lhs.distance < rhs.distance }?
            .agent
    }

    private static func compactAgentID(_ text: String) -> String {
        normalize(text)
            .replacingOccurrences(of: "openclaw", with: "")
            .replacingOccurrences(of: "underscore", with: "")
            .replacingOccurrences(of: "underline", with: "")
            .replacingOccurrences(of: "hifen", with: "")
            .replacingOccurrences(of: "traco", with: "")
            .replacingOccurrences(of: "traço", with: "")
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt-BR"))
            .lowercased()
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

private extension Array where Element == String {
    func deduplicated() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
