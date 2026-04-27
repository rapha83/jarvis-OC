import Foundation

struct AgentEventRecord: Identifiable, Codable, Equatable {
    enum Severity: String, Codable, CaseIterable {
        case info
        case success
        case warning
        case error
    }

    let id: UUID
    let date: Date
    let title: String
    let detail: String
    let agentID: String
    let severity: Severity

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        title: String,
        detail: String,
        agentID: String,
        severity: Severity = .info
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.detail = detail
        self.agentID = agentID
        self.severity = severity
    }
}
