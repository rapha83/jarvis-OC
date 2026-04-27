import Foundation

final class BackendClient {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 120
        session = URLSession(configuration: configuration, delegate: LocalTrustDelegate(), delegateQueue: nil)
    }

    func sendVoiceCommand(
        audioData: Data,
        serverURL: String,
        token: String,
        agentID: String,
        sessionID: String,
        idempotencyKey: String,
        screenContext: String? = nil,
        speak: Bool = true
    ) async throws -> VoiceResponse {
        guard let base = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw BackendError.invalidURL
        }
        let endpoint = base.appendingPathComponent("api/voice")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        applyCommonHeaders(
            to: &request,
            token: token,
            agentID: agentID,
            sessionID: sessionID,
            idempotencyKey: idempotencyKey,
            screenContext: screenContext
        )
        if !speak {
            request.setValue("0", forHTTPHeaderField: "X-Jarvis-Speak")
        }

        let (data, response) = try await session.upload(for: request, from: audioData)
        return try decodeVoiceResponse(data: data, response: response)
    }

    func transcribeVoiceCommand(
        audioData: Data,
        serverURL: String,
        token: String,
        sessionID: String,
        idempotencyKey: String
    ) async throws -> TranscriptionResponse {
        guard let base = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw BackendError.invalidURL
        }
        let endpoint = base.appendingPathComponent("api/transcribe")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        applyCommonHeaders(to: &request, token: token, sessionID: sessionID, idempotencyKey: idempotencyKey)

        let (data, response) = try await session.upload(for: request, from: audioData)
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw BackendError.server(message)
        }
        return try JSONDecoder().decode(TranscriptionResponse.self, from: data)
    }

    func sendTextCommand(
        text: String,
        serverURL: String,
        token: String,
        agentID: String,
        sessionID: String,
        idempotencyKey: String,
        screenContext: String? = nil,
        checkFeedback: Bool = false,
        speak: Bool = true
    ) async throws -> VoiceResponse {
        guard let base = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw BackendError.invalidURL
        }
        let endpoint = base.appendingPathComponent("api/text")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyCommonHeaders(
            to: &request,
            token: token,
            agentID: agentID,
            sessionID: sessionID,
            idempotencyKey: idempotencyKey,
            screenContext: screenContext
        )
        if checkFeedback {
            request.setValue("1", forHTTPHeaderField: "X-Jarvis-Check-Feedback")
        }
        if !speak {
            request.setValue("0", forHTTPHeaderField: "X-Jarvis-Speak")
        }
        request.httpBody = try JSONEncoder().encode(TextCommandRequest(text: text, source: "macos-wake-word"))

        let (data, response) = try await session.data(for: request)
        return try decodeVoiceResponse(data: data, response: response)
    }

    func streamTextCommand(
        text: String,
        serverURL: String,
        token: String,
        agentID: String,
        sessionID: String,
        idempotencyKey: String,
        screenContext: String? = nil,
        onText: @escaping @MainActor (String) -> Void
    ) async throws -> VoiceResponse {
        guard let base = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw BackendError.invalidURL
        }
        let endpoint = base.appendingPathComponent("api/text/stream")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("0", forHTTPHeaderField: "X-Jarvis-Speak")
        applyCommonHeaders(
            to: &request,
            token: token,
            agentID: agentID,
            sessionID: sessionID,
            idempotencyKey: idempotencyKey,
            screenContext: screenContext
        )
        request.httpBody = try JSONEncoder().encode(TextCommandRequest(text: text, source: "macos-text-hotkey"))

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.server("HTTP \(http.statusCode)")
        }

        var finalEvent: TextStreamEvent?
        var responseText = ""
        var transcription = text
        var originalTranscription = text
        var corrections: [String] = []

        for try await line in bytes.lines {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let data = line.data(using: .utf8) else {
                continue
            }
            let event = try JSONDecoder().decode(TextStreamEvent.self, from: data)
            switch event.type {
            case "transcription":
                transcription = event.transcription ?? transcription
                originalTranscription = event.originalTranscription ?? originalTranscription
                corrections = event.normalizationCorrections ?? corrections
            case "status":
                break
            case "delta":
                responseText = event.text ?? "\(responseText) \(event.delta ?? "")"
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let snapshot = responseText
                await MainActor.run {
                    onText(snapshot)
                }
            case "response":
                finalEvent = event
                responseText = event.text ?? responseText
                transcription = event.transcription ?? transcription
                originalTranscription = event.originalTranscription ?? originalTranscription
                corrections = event.normalizationCorrections ?? corrections
                let snapshot = responseText
                await MainActor.run {
                    onText(snapshot)
                }
            case "error":
                throw BackendError.server(event.message ?? "Erro no stream de texto")
            default:
                break
            }
        }

        return VoiceResponse(
            type: "response",
            transcription: transcription,
            originalTranscription: originalTranscription,
            normalizationCorrections: corrections,
            text: responseText,
            expectingReply: finalEvent?.expectingReply ?? false,
            audioMime: "",
            audioBase64: "",
            message: nil,
            directive: finalEvent?.directive
        )
    }

    func fetchHealth(serverURL: String, token: String, agentID: String) async throws -> BackendHealth {
        guard let base = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw BackendError.invalidURL
        }
        let endpoint = base.appendingPathComponent("api/health")
        var request = URLRequest(url: endpoint)
        applyAgentHeader(agentID, to: &request)
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("JARVIS macOS", forHTTPHeaderField: "X-Jarvis-Client")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw BackendError.server(message)
        }
        return try JSONDecoder().decode(BackendHealth.self, from: data)
    }

    private func applyCommonHeaders(
        to request: inout URLRequest,
        token: String,
        agentID: String? = nil,
        sessionID: String,
        idempotencyKey: String,
        screenContext: String? = nil
    ) {
        request.setValue(sessionID, forHTTPHeaderField: "X-Jarvis-Session")
        request.setValue(idempotencyKey, forHTTPHeaderField: "X-Jarvis-Idempotency-Key")
        request.setValue("macos-native", forHTTPHeaderField: "X-Jarvis-Voice-Source")
        request.setValue(Host.current().localizedName ?? "Mac", forHTTPHeaderField: "X-Jarvis-Device")
        request.setValue(MacContextService.currentSummaryBase64(), forHTTPHeaderField: "X-Jarvis-Mac-Context-B64")
        applyAgentHeader(agentID, to: &request)
        if let screenContext, !screenContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let encoded = Data(screenContext.utf8).base64EncodedString()
            request.setValue(encoded, forHTTPHeaderField: "X-Jarvis-Screen-Context-B64")
        }
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func applyAgentHeader(_ agentID: String?, to request: inout URLRequest) {
        guard let agentID else {
            return
        }
        let trimmed = agentID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "openclaw/", with: "")
        if !trimmed.isEmpty {
            request.setValue(trimmed, forHTTPHeaderField: "X-Jarvis-Agent")
        }
    }

    private func decodeVoiceResponse(data: Data, response: URLResponse) throws -> VoiceResponse {
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw BackendError.server(message)
        }
        return try JSONDecoder().decode(VoiceResponse.self, from: data)
    }

    func fetchGreetingAudio(serverURL: String) async -> Data? {
        guard let base = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        do {
            let countURL = base.appendingPathComponent("ack/count")
            let (countData, _) = try await session.data(from: countURL)
            let countPayload = try JSONDecoder().decode(AckCount.self, from: countData)
            guard countPayload.count > 0 else {
                return nil
            }
            let index = Int.random(in: 0..<countPayload.count)
            let audioURL = base.appendingPathComponent("ack/\(index)")
            let (audioData, _) = try await session.data(from: audioURL)
            return audioData
        } catch {
            return nil
        }
    }
}

private struct TextCommandRequest: Encodable {
    let text: String
    let source: String
}

private struct TextStreamEvent: Decodable {
    let type: String
    let message: String?
    let delta: String?
    let text: String?
    let transcription: String?
    let originalTranscription: String?
    let normalizationCorrections: [String]?
    let expectingReply: Bool?
    let directive: VoiceDirective?
}

private struct AckCount: Decodable {
    let count: Int
}

private final class LocalTrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust,
            isLocalHost(challenge.protectionSpace.host)
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    private func isLocalHost(_ host: String) -> Bool {
        host == "localhost"
            || host == "127.0.0.1"
            || host.hasPrefix("192.168.")
            || host.hasPrefix("10.")
            || host.hasPrefix("172.16.")
            || host.hasPrefix("172.17.")
            || host.hasPrefix("172.18.")
            || host.hasPrefix("172.19.")
            || host.hasPrefix("172.2")
            || host.hasPrefix("172.30.")
            || host.hasPrefix("172.31.")
    }
}

enum BackendError: LocalizedError {
    case invalidURL
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL do servidor invalida"
        case .invalidResponse:
            return "Resposta invalida do servidor"
        case .server(let message):
            return message
        }
    }
}
