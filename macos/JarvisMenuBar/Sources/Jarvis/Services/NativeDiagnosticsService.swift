import AVFoundation
import Foundation
import Speech

struct NativeHealthSnapshot: Equatable {
    let isOperational: Bool
    let summary: String
    let gateway: String
    let token: String
    let agent: String
    let wakeWord: String
    let speech: String
    let whisper: String
    let tts: String
    let permissions: String
    let microphone: String
    let screen: String
}

enum NativeDiagnosticsService {
    private static let defaultAgentID = "it-infrastructure-specialist"

    @MainActor
    static func makeSnapshot(
        gatewayURL: String,
        agentID: String,
        speechLocaleID: String,
        strictLocalSTT: Bool,
        sttEngine: LocalSTTEngine,
        ttsEngine: LocalTTSEngine,
        azureSpeechRegion: String,
        azureSpeechKey: String,
        azureSpeechVoiceID: String,
        wakeWordEngine: LocalWakeWordEngine
    ) async -> NativeHealthSnapshot {
        async let gateway = probeGateway(gatewayURL: gatewayURL)
        let token = tokenSummary()
        let speech = speechSummary(localeID: speechLocaleID, strictLocalSTT: strictLocalSTT)
        let whisperStatus = WhisperCoreMLRuntime.shared.status()
        let whisper = whisperStatus.summary
        let coreMLWakeStatus = CoreMLWakeWordService.status()
        let wakeWord = wakeWordSummary(
            engine: wakeWordEngine,
            speechSummary: speech,
            coreMLStatus: coreMLWakeStatus
        )
        let ttsStatus = NeuralTTSRuntime.shared.status()
        let tts = ttsSummary(
            language: speechLocaleID,
            engine: ttsEngine,
            neuralStatus: ttsStatus,
            azureSpeechRegion: azureSpeechRegion,
            azureSpeechKey: azureSpeechKey,
            azureSpeechVoiceID: azureSpeechVoiceID
        )
        let permissionSnapshot = PermissionsService.snapshot()
        let microphone = AudioInputDeviceObserver.defaultInputDeviceSummary()
        let screen = permissionSnapshot.screenRecording ? "Tela/OCR autorizado" : "Tela/OCR sem permissao"

        let gatewaySummary = await gateway
        let tokenOK = !OpenClawConfigMonitor.authToken().isEmpty
        let speechOK: Bool
        switch sttEngine {
        case .appleSpeech, .speechAnalyzer:
            speechOK = !speech.hasPrefix("Indisponivel") && !(strictLocalSTT && speech.contains("sem on-device"))
        case .whisperCoreML:
            speechOK = whisperStatus.isRuntimeAvailable
        }
        let wakeWordOK: Bool
        switch wakeWordEngine {
        case .appleSpeech, .speechAnalyzer, .appleCommandRecognizer:
            wakeWordOK = !speech.hasPrefix("Indisponivel") && !(strictLocalSTT && speech.contains("sem on-device"))
        case .coreMLKeywordSpotter:
            wakeWordOK = coreMLWakeStatus.isRuntimeAvailable
                || (!speech.hasPrefix("Indisponivel") && !(strictLocalSTT && speech.contains("sem on-device")))
        }
        let ttsOK: Bool
        switch ttsEngine {
        case .ttsKitNeural:
            ttsOK = ttsStatus.isRuntimeAvailable
        case .azureNeural:
            ttsOK = !azureSpeechRegion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !azureSpeechKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .customCommand:
            ttsOK = true
        case .appleSystem, .appleNeuralEnhanced:
            ttsOK = !tts.hasPrefix("Indisponivel")
        }
        let needsSpeechPermission = sttEngine == .appleSpeech
            || sttEngine == .speechAnalyzer
            || wakeWordEngine == .appleSpeech
            || wakeWordEngine == .speechAnalyzer
        let permissionsOK = permissionSnapshot.microphone && (!needsSpeechPermission || permissionSnapshot.speechRecognition)
        let operational = gatewaySummary.hasPrefix("OK") && tokenOK && speechOK && wakeWordOK && ttsOK && permissionsOK

        let agent = agentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultAgentID
            : agentID
        let summary = operational
            ? "Runtime nativo OK - \(agent)"
            : "Runtime nativo requer atencao"

        return NativeHealthSnapshot(
            isOperational: operational,
            summary: summary,
            gateway: gatewaySummary,
            token: token,
            agent: agent,
            wakeWord: wakeWord,
            speech: speech,
            whisper: whisper,
            tts: tts,
            permissions: permissionSnapshot.summary,
            microphone: microphone,
            screen: screen
        )
    }

    private static func probeGateway(gatewayURL: String) async -> String {
        let token = OpenClawConfigMonitor.authToken()
        guard !token.isEmpty else {
            return "Token ausente"
        }
        guard let base = URL(string: gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return "URL invalida"
        }

        var request = URLRequest(url: base.appendingPathComponent("v1/models"))
        request.httpMethod = "GET"
        request.timeoutInterval = 4
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return "Resposta invalida"
            }
            switch http.statusCode {
            case 200..<300:
                return "OK \(base.host ?? "gateway")"
            case 401, 403:
                return "Nao autorizado HTTP \(http.statusCode)"
            case 404:
                return "OK gateway ativo (sem /v1/models)"
            default:
                return "HTTP \(http.statusCode)"
            }
        } catch {
            return "Indisponivel: \(error.localizedDescription)"
        }
    }

    private static func tokenSummary() -> String {
        let token = OpenClawConfigMonitor.authToken()
        guard !token.isEmpty else {
            return "Nao configurado"
        }
        return "Configurado (...\(token.suffix(4)))"
    }

    private static func speechSummary(localeID: String, strictLocalSTT: Bool) -> String {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)), recognizer.isAvailable else {
            return "Indisponivel para \(localeID)"
        }
        if recognizer.supportsOnDeviceRecognition {
            return strictLocalSTT ? "On-device obrigatorio para \(localeID)" : "On-device disponivel para \(localeID)"
        }
        return strictLocalSTT
            ? "Indisponivel: \(localeID) sem on-device"
            : "Disponivel via Speech framework para \(localeID)"
    }

    private static func wakeWordSummary(
        engine: LocalWakeWordEngine,
        speechSummary: String,
        coreMLStatus: CoreMLWakeWordStatus
    ) -> String {
        switch engine {
        case .coreMLKeywordSpotter:
            return coreMLStatus.isRuntimeAvailable
                ? coreMLStatus.summary
                : "\(coreMLStatus.summary); fallback Apple Speech"
        case .speechAnalyzer:
            return "SpeechAnalyzer experimental; fallback Apple Speech: \(speechSummary)"
        case .appleSpeech:
            return "Apple Speech: \(speechSummary)"
        case .appleCommandRecognizer:
            return "\(DedicatedWakeWordService.runtimeSummary()); fallback Apple Speech para evitar downloads legados"
        }
    }

    @MainActor
    private static func ttsSummary(
        language: String,
        engine: LocalTTSEngine,
        neuralStatus: NeuralTTSRuntimeStatus,
        azureSpeechRegion: String,
        azureSpeechKey: String,
        azureSpeechVoiceID: String
    ) -> String {
        switch engine {
        case .ttsKitNeural:
            return neuralStatus.summary
        case .azureNeural:
            return AzureNeuralTTSService.configurationSummary(
                regionOrEndpoint: azureSpeechRegion,
                subscriptionKey: azureSpeechKey,
                voiceID: azureSpeechVoiceID
            )
        case .customCommand:
            return CustomCommandTTSService.configurationSummary(
                commandTemplate: UserDefaults.standard.string(forKey: "customTTSCommand") ?? ""
            )
        case .appleSystem, .appleNeuralEnhanced:
            return SystemSpeechService.voiceSummary(localeID: language, engine: engine)
        }
    }
}
