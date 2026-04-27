import Foundation

actor NativeConversationStore {
    static let shared = NativeConversationStore()

    private let maxTurns = 20
    private var historyBySession: [String: [[String: String]]] = [:]

    func messages(
        sessionID: String,
        userText: String,
        macContext: String,
        screenContext: String
    ) -> [[String: String]] {
        var history = historyBySession[sessionID] ?? []
        history.append(["role": "user", "content": userText])
        historyBySession[sessionID] = history
        let visibleHistory = Array(history.suffix(maxTurns))
        return [Self.systemMessage(macContext: macContext, screenContext: screenContext)] + visibleHistory
    }

    func appendAssistant(sessionID: String, text: String) {
        var history = historyBySession[sessionID] ?? []
        history.append(["role": "assistant", "content": text])
        if history.count > maxTurns * 2 {
            history = Array(history.suffix(maxTurns * 2))
        }
        historyBySession[sessionID] = history
    }

    func rollbackLastUserTurn(sessionID: String) {
        var history = historyBySession[sessionID] ?? []
        if history.last?["role"] == "user" {
            history.removeLast()
        }
        historyBySession[sessionID] = history
    }

    private static func systemMessage(macContext: String, screenContext: String) -> [String: String] {
        let now = Date().formatted(date: .numeric, time: .standard)
        let macLine = macContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : "Contexto local do Mac: \(macContext). "
        let screenLine = screenContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? ""
            : "Contexto visual/OCR da tela atual, enviado pelo app nativo:\n\(screenContext)\n"

        return [
            "role": "system",
            "content": """
            Você é o Jarvis, assistente de voz pessoal do líder supremo.
            Está sendo acessado por interface nativa de macOS em português brasileiro.
            \(macLine)\(screenLine)
            A mensagem pode ter vindo por voz ou texto; quando houver ambiguidade real, confirme antes de agir.
            Data/hora atual: \(now).
            REGRAS:
            1) Respostas concisas e diretas.
            2) Use suas ferramentas e acessos disponíveis para buscar informação real.
            3) Quando perguntado sobre casa, sensores, luzes, energia ou infraestrutura, consulte recursos reais.
            4) Evite listas longas, markdown e formatação pesada.
            5) Não use emojis.
            6) Se precisar controlar a interface de voz, coloque apenas na primeira linha um JSON compacto como {"jarvisDirective":{"speak":true,"expectingReply":false}} e depois responda normalmente.
            7) Se houver contexto visual/OCR, trate-o como a tela atual do usuário.
            """
        ]
    }
}
