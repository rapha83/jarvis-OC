import Foundation

enum NativeGreetingService {
    private static let phrases = [
        "Sim, líder supremo.",
        "Às suas ordens, líder supremo.",
        "Prontinho, líder supremo.",
        "Diga, líder supremo.",
        "Ouvindo, líder supremo.",
        "Como posso ajudar, líder supremo?",
        "Pode falar, líder supremo.",
        "Estou aqui, líder supremo."
    ]

    static func nextPhrase() -> String {
        phrases.randomElement() ?? "Diga, líder supremo."
    }
}
