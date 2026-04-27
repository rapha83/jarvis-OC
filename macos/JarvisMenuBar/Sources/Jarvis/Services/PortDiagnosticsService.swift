import Foundation

enum PortDiagnosticsService {
    static func makeSummary(serverURL: String) async -> String {
        await Task.detached {
            let jarvisPort = URL(string: serverURL)?.port ?? 8765
            let jarvis = listeners(on: jarvisPort)
            let openclaw = listeners(on: 18789)
            return [
                "Jarvis \(jarvisPort): \(jarvis)",
                "OpenClaw 18789: \(openclaw)"
            ].joined(separator: " | ")
        }.value
    }

    private static func listeners(on port: Int) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-iTCP:\(port)", "-sTCP:LISTEN", "-Fpnc"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            let parsed = parse(text: text)
            return parsed.isEmpty ? "sem listener" : parsed.joined(separator: ", ")
        } catch {
            return "erro: \(error.localizedDescription)"
        }
    }

    private static func parse(text: String) -> [String] {
        var output: [String] = []
        var pid = ""
        var command = ""

        func flush() {
            guard !pid.isEmpty || !command.isEmpty else {
                return
            }
            output.append("\(command.isEmpty ? "processo" : command) pid \(pid.isEmpty ? "?" : pid)")
            pid = ""
            command = ""
        }

        for line in text.split(separator: "\n").map(String.init) {
            guard let prefix = line.first else {
                continue
            }
            let value = String(line.dropFirst())
            switch prefix {
            case "p":
                flush()
                pid = value
            case "c":
                command = value
            default:
                continue
            }
        }
        flush()
        return output
    }
}
