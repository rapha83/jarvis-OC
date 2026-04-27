import Foundation

enum DiagnosticsReportBuilder {
    @MainActor
    static func makeReport(model: JarvisAppModel) -> String {
        let nativeHealth = model.nativeHealth
        let detailed = model.detailedLoggingEnabled
        let recent = model.recentInteractions.prefix(5).map { record in
            let text = detailed ? record.transcript : "[redacted]"
            return "- \(record.date.formatted(date: .omitted, time: .standard)) [\(record.source)] \(text)"
        }.joined(separator: "\n")
        let voiceTestOriginal = detailed ? model.voiceTestOriginalTranscript : "[redacted]"
        let voiceTestTranscript = detailed ? model.voiceTestTranscript : "[redacted]"
        let lastTranscription = detailed ? model.transcription : "[redacted]"
        let lastResponse = detailed ? model.response : "[redacted]"

        return """
        JARVIS diagnostics
        Status: \(model.status.title) - \(model.status.detail)
        Enabled: \(model.isEnabled)
        Native OpenClaw URL: \(model.nativeOpenClawURL)
        Native runtime: \(model.nativeRuntimeStatus)
        Mac voice runtime: native only
        Wake word engine: \(model.localWakeWordEngine.title)
        STT engine: \(model.localSTTEngine.title)
        TTS engine: \(model.localTTSEngine.title)
        Azure Speech region: \(model.azureSpeechRegion)
        Azure Speech voice: \(model.azureSpeechVoiceID)
        Azure Speech key configured: \(!model.azureSpeechKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Strict local STT enabled: \(model.strictLocalSTTEnabled)
        Native health operational: \(model.nativeHealthOperational)
        Native gateway: \(nativeHealth?.gateway ?? "unknown")
        Native token: \(nativeHealth?.token ?? "unknown")
        Detailed logging: \(model.detailedLoggingEnabled)
        Native wake word: \(nativeHealth?.wakeWord ?? "unknown")
        Wake word runtime status: \(model.wakeWordRuntimeStatus)
        Native speech: \(nativeHealth?.speech ?? "unknown")
        SpeechAnalyzer status: \(model.speechAnalyzerStatus)
        SpeechAnalyzer assets: \(model.speechAnalyzerAssetStatus)
        Native Whisper/Core ML: \(nativeHealth?.whisper ?? "unknown")
        Native TTS: \(nativeHealth?.tts ?? "unknown")
        Native mic: \(nativeHealth?.microphone ?? "unknown")
        Native screen: \(nativeHealth?.screen ?? "unknown")
        Wake words: \(model.wakeWordsText)
        Voice responses: \(model.voiceResponsesEnabled)
        Interrupt speech: \(model.interruptSpeechEnabled)
        Right Control shortcut: \(model.pushToTalkEnabled)
        Voice hotkey: \(model.voiceHotKeyEnabled) \(model.voiceHotKey.displayName)
        Text hotkey: \(model.textHotKeyEnabled) \(model.textHotKey.displayName)
        Text overlay response: \(model.textOverlayResponseMode.title)
        Launch at login: \(model.launchAtLoginEnabled)
        Screen context enabled: \(model.screenContextEnabled)
        Screen context mode: \(model.screenContextMode.title)
        OCR enabled: \(model.screenOCREnabled)
        Screen display index: \(model.screenDisplayIndex)
        Screen max width: \(Int(model.screenMaxWidth))
        Screen include cursor: \(model.screenIncludeCursor)
        Screen status: \(model.screenContextStatus)
        Permissions: \(model.permissionSnapshot.summary)
        Port diagnostics: \(model.portDiagnosticsStatus)
        OpenClaw local config: \(model.openClawConfigStatus)
        Runtime: \(model.backendStatus)
        Selected agent: \(model.resolvedAgentID)
        Mic: \(model.micDescription)
        Preferred mic UID: \(model.selectedMicrophoneUID.isEmpty ? "system-default" : model.selectedMicrophoneUID)
        Speech locale: \(model.speechLocaleID)
        Voice test status: \(model.voiceTestStatus)
        Voice test original: \(voiceTestOriginal)
        Voice test transcript: \(voiceTestTranscript)
        Voice test corrections: \(model.voiceTestCorrections.joined(separator: ","))
        Diagnostics log: \(DiagnosticsFileLog.logURL.path)
        Last source: \(model.lastCommandSource)
        Mac context: \(MacContextService.currentSummary())
        Last transcription: \(lastTranscription)
        Last response: \(lastResponse)
        Last error: \(model.lastError)

        Recent interactions:
        \(recent.isEmpty ? "- none" : recent)
        """
    }
}
