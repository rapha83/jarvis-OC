import Foundation

@MainActor
final class AzureNeuralTTSService {
    private let playback = AudioPlaybackService()
    private var generation = 0
    private(set) var lastVoiceSummary = "Azure Neural nao usado nesta sessao"

    func speak(
        _ text: String,
        regionOrEndpoint: String,
        subscriptionKey: String,
        voiceID: String,
        localeID: String
    ) async -> PlaybackResult {
        let clean = Self.stripEmoji(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return .failed
        }

        let key = subscriptionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = regionOrEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let voice = voiceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "pt-BR-AntonioNeural"
            : voiceID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !key.isEmpty, !region.isEmpty else {
            lastVoiceSummary = "Azure Neural sem regiao/endpoint ou chave"
            return .failed
        }

        guard let url = Self.endpointURL(from: region) else {
            lastVoiceSummary = "Azure Neural endpoint invalido"
            return .failed
        }

        generation += 1
        let currentGeneration = generation
        playback.stop()

        do {
            let audio = try await synthesize(
                text: clean,
                url: url,
                subscriptionKey: key,
                voiceID: voice,
                localeID: Self.localeID(forVoiceID: voice, fallback: localeID)
            )
            guard currentGeneration == generation else {
                return .stopped
            }
            lastVoiceSummary = "\(voice) via \(Self.displayRegion(from: region))"
            return try await playback.play(data: audio)
        } catch is CancellationError {
            return .stopped
        } catch {
            lastVoiceSummary = "Azure Neural falhou: \(error.localizedDescription)"
            DiagnosticsFileLog.shared.log(
                category: "tts",
                event: "azure_neural_error",
                fields: ["message": error.localizedDescription]
            )
            return .failed
        }
    }

    func stop() {
        generation += 1
        playback.stop()
    }

    static func configurationSummary(regionOrEndpoint: String, subscriptionKey: String, voiceID: String) -> String {
        let region = regionOrEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = subscriptionKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let voice = voiceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "pt-BR-AntonioNeural"
            : voiceID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !region.isEmpty else {
            return "Azure Neural: regiao/endpoint nao configurado"
        }
        guard !key.isEmpty else {
            return "Azure Neural: chave F0 nao configurada"
        }
        guard endpointURL(from: region) != nil else {
            return "Azure Neural: endpoint invalido"
        }
        return "Azure Neural OK: \(voice) em \(displayRegion(from: region))"
    }

    private func synthesize(
        text: String,
        url: URL,
        subscriptionKey: String,
        voiceID: String,
        localeID: String
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue(subscriptionKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue("audio-24khz-48kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
        request.setValue("JARVIS", forHTTPHeaderField: "User-Agent")
        request.httpBody = Self.ssml(text: text, voiceID: voiceID, localeID: localeID).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AzureNeuralTTSError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode), !data.isEmpty else {
            let message = String(data: data.prefix(800), encoding: .utf8)
            throw AzureNeuralTTSError.httpStatus(http.statusCode, message)
        }
        return data
    }

    private static func endpointURL(from regionOrEndpoint: String) -> URL? {
        let trimmed = regionOrEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            guard var components = URLComponents(string: trimmed) else {
                return nil
            }
            if components.path.isEmpty || components.path == "/" {
                components.path = "/cognitiveservices/v1"
            }
            return components.url
        }
        let region = trimmed
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9-]"#, with: "", options: .regularExpression)
        guard !region.isEmpty else {
            return nil
        }
        return URL(string: "https://\(region).tts.speech.microsoft.com/cognitiveservices/v1")
    }

    private static func displayRegion(from regionOrEndpoint: String) -> String {
        if let url = URL(string: regionOrEndpoint), let host = url.host {
            return host
        }
        return regionOrEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func localeID(forVoiceID voiceID: String, fallback: String) -> String {
        let parts = voiceID.split(separator: "-")
        guard parts.count >= 2 else {
            return fallback
        }
        return "\(parts[0])-\(parts[1])"
    }

    private static func ssml(text: String, voiceID: String, localeID: String) -> String {
        """
        <speak version="1.0" xml:lang="\(xmlEscape(localeID))" xmlns="http://www.w3.org/2001/10/synthesis">
          <voice name="\(xmlEscape(voiceID))">
            <prosody rate="+0%" pitch="-2%">
              \(xmlEscape(text))
            </prosody>
          </voice>
        </speak>
        """
    }

    private static func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func stripEmoji(_ text: String) -> String {
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

private enum AzureNeuralTTSError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Resposta invalida do Azure Speech"
        case .httpStatus(let status, let message):
            if let message, !message.isEmpty {
                return "Azure Speech HTTP \(status): \(message)"
            }
            return "Azure Speech HTTP \(status)"
        }
    }
}
