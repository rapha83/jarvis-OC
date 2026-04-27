import Foundation

struct VoiceTurn: Sendable {
    let id: String
    let source: String
    let agentID: String
    let startedAt: Date
}

actor VoiceRuntime {
    static let shared = VoiceRuntime()

    private var currentTurn: VoiceTurn?

    func beginTurn(source: String, agentID: String) -> VoiceTurn {
        let turn = VoiceTurn(
            id: UUID().uuidString,
            source: source,
            agentID: agentID,
            startedAt: Date()
        )
        currentTurn = turn
        DiagnosticsFileLog.shared.log(
            category: "voice.turn",
            event: "begin",
            fields: ["turn": turn.id, "source": source, "agent": agentID]
        )
        return turn
    }

    func mark(_ event: String, turn: VoiceTurn, fields: [String: String] = [:]) {
        guard currentTurn?.id == turn.id else {
            return
        }
        var merged = fields
        merged["turn"] = turn.id
        merged["source"] = turn.source
        merged["agent"] = turn.agentID
        DiagnosticsFileLog.shared.log(category: "voice.turn", event: event, fields: merged)
    }

    func endTurn(_ turn: VoiceTurn, outcome: String, fields: [String: String] = [:]) {
        guard currentTurn?.id == turn.id else {
            return
        }
        currentTurn = nil
        var merged = fields
        merged["turn"] = turn.id
        merged["source"] = turn.source
        merged["agent"] = turn.agentID
        merged["outcome"] = outcome
        merged["durationMs"] = "\(Int(Date().timeIntervalSince(turn.startedAt) * 1000))"
        DiagnosticsFileLog.shared.log(category: "voice.turn", event: "end", fields: merged)
    }
}
