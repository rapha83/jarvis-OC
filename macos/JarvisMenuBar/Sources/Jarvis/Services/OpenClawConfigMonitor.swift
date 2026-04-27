import Foundation

enum OpenClawConfigMonitor {
    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".openclaw", isDirectory: true)
            .appendingPathComponent("openclaw.json", isDirectory: false)
    }

    static func summary() -> String {
        let url = configURL
        guard let root = loadRoot() else {
            return "Config OpenClaw nao encontrada em \(url.path)"
        }
        guard
            let gateway = root["gateway"] as? [String: Any],
            let auth = gateway["auth"] as? [String: Any]
        else {
            return "Config OpenClaw encontrada, mas formato inesperado"
        }

        let mode = auth["mode"] as? String ?? "desconhecido"
        let token = (auth["token"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenDescription: String
        if token.isEmpty {
            tokenDescription = "sem token"
        } else {
            tokenDescription = "token ..." + token.suffix(4)
        }
        return "auth.mode=\(mode), \(tokenDescription)"
    }

    static func authToken() -> String {
        guard
            let root = loadRoot(),
            let gateway = root["gateway"] as? [String: Any],
            let auth = gateway["auth"] as? [String: Any]
        else {
            return ""
        }
        return (auth["token"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func agentIDs(defaultID: String) -> [String] {
        guard let root = loadRoot() else {
            return [defaultID]
        }

        var ids: [String] = []
        var seen = Set<String>()

        func append(_ raw: String?) {
            guard let raw else { return }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en-US"))
                .lowercased()
            guard !trimmed.isEmpty, seen.insert(key).inserted else {
                return
            }
            ids.append(trimmed)
        }

        guard let agents = root["agents"] as? [String: Any] else {
            return [defaultID]
        }

        if let entries = agents["list"] as? [[String: Any]] {
            for entry in entries {
                append(entry["id"] as? String)
            }
        } else if let entries = agents["list"] as? [String] {
            for entry in entries {
                append(entry)
            }
        }

        return ids.isEmpty ? [defaultID] : ids
    }

    private static func loadRoot() -> [String: Any]? {
        guard let data = try? Data(contentsOf: configURL) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
