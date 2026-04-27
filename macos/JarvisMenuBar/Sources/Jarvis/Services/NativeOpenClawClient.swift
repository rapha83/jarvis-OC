import Foundation

final class NativeOpenClawClient {
    private static let defaultAgentID = "it-infrastructure-specialist"

    private let session: URLSession
    private let conversationStore: NativeConversationStore

    init(
        session: URLSession = .shared,
        conversationStore: NativeConversationStore = .shared
    ) {
        self.session = session
        self.conversationStore = conversationStore
    }

    func streamTextCommand(
        text: String,
        gatewayURL: String,
        token: String,
        agentID: String,
        sessionID: String,
        screenContext: String?,
        onText: @escaping @MainActor (String) -> Void
    ) async throws -> VoiceResponse {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return VoiceResponse(
                type: "no_speech",
                transcription: "",
                originalTranscription: "",
                normalizationCorrections: [],
                text: "",
                expectingReply: false,
                audioMime: "",
                audioBase64: "",
                message: nil,
                directive: nil
            )
        }

        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else {
            throw NativeOpenClawError.missingToken
        }
        guard let base = URL(string: gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw NativeOpenClawError.invalidURL
        }

        let messages = await conversationStore.messages(
            sessionID: sessionID,
            userText: trimmedText,
            macContext: MacContextService.currentSummary(),
            screenContext: screenContext ?? ""
        )

        var request = URLRequest(url: base.appendingPathComponent("v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(cleanToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: "openclaw/\(normalizeAgentID(agentID))",
            messages: messages,
            stream: true,
            user: "jarvis-native"
        ))

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NativeOpenClawError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            await conversationStore.rollbackLastUserTurn(sessionID: sessionID)
            throw NativeOpenClawError.httpStatus(http.statusCode)
        }

        var rawResponse = ""
        var visibleResponse = ""
        var directive: VoiceDirective?
        var isHoldingPossibleDirective = false

        for try await line in bytes.lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedLine.hasPrefix("data: ") else {
                continue
            }
            let payload = String(trimmedLine.dropFirst(6))
            if payload == "[DONE]" {
                break
            }
            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(ChatStreamChunk.self, from: data) else {
                continue
            }

            let delta = chunk.choices.first?.delta.content ?? ""
            guard !delta.isEmpty else {
                continue
            }

            rawResponse += delta
            let extraction = NativeVoiceDirectiveParser.extract(from: rawResponse)
            if let parsedDirective = extraction.0 {
                directive = parsedDirective
                visibleResponse = extraction.1
                isHoldingPossibleDirective = false
            } else if rawResponse.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"),
                      !rawResponse.contains("\n"),
                      visibleResponse.isEmpty {
                isHoldingPossibleDirective = true
                continue
            } else if isHoldingPossibleDirective {
                visibleResponse = rawResponse
                isHoldingPossibleDirective = false
            } else {
                visibleResponse = rawResponse
            }

            let cleaned = visibleResponse.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                await MainActor.run {
                    onText(cleaned)
                }
            }
        }

        let finalExtraction = NativeVoiceDirectiveParser.extract(from: rawResponse)
        if let parsedDirective = finalExtraction.0 {
            directive = parsedDirective
            visibleResponse = finalExtraction.1
        }
        visibleResponse = stripEmoji(visibleResponse)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        await conversationStore.appendAssistant(sessionID: sessionID, text: visibleResponse)
        let expectingReply = directive?.expectingReply ?? visibleResponse.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?")

        return VoiceResponse(
            type: "response",
            transcription: trimmedText,
            originalTranscription: trimmedText,
            normalizationCorrections: [],
            text: visibleResponse,
            expectingReply: expectingReply,
            audioMime: "",
            audioBase64: "",
            message: nil,
            directive: directive
        )
    }

    private func normalizeAgentID(_ agentID: String) -> String {
        let trimmed = agentID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "openclaw/", with: "")
        return trimmed.isEmpty ? Self.defaultAgentID : trimmed
    }

    private func stripEmoji(_ text: String) -> String {
        String(text.unicodeScalars.filter { scalar in
            let value = scalar.value
            return !(
                (0x1F000...0x1FAFF).contains(value)
                || (0x2600...0x27BF).contains(value)
                || value == 0x200D
                || value == 0xFE0E
                || value == 0xFE0F
            )
        })
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [[String: String]]
    let stream: Bool
    let user: String
}

private struct ChatStreamChunk: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let delta: Delta
    }

    struct Delta: Decodable {
        let content: String?
    }
}

enum NativeOpenClawError: LocalizedError {
    case missingToken
    case invalidURL
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Token do OpenClaw nao encontrado em ~/.openclaw/openclaw.json"
        case .invalidURL:
            return "URL nativa do OpenClaw invalida"
        case .invalidResponse:
            return "Resposta invalida do OpenClaw"
        case .httpStatus(let status):
            return "OpenClaw retornou HTTP \(status)"
        }
    }
}
