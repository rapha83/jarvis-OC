import AppKit
import Foundation

@MainActor
final class JarvisAppModel: ObservableObject {
    static let defaultAgentID = "it-infrastructure-specialist"

    @Published var status: AssistantStatus = .stopped
    @Published var transcription = ""
    @Published var response = ""
    @Published var isEnabled = false
    @Published var voiceResponsesEnabled = true {
        didSet { UserDefaults.standard.set(voiceResponsesEnabled, forKey: "voiceResponsesEnabled") }
    }
    @Published var interruptSpeechEnabled = false {
        didSet { UserDefaults.standard.set(interruptSpeechEnabled, forKey: "interruptSpeechEnabled") }
    }
    @Published var pushToTalkEnabled = false {
        didSet {
            UserDefaults.standard.set(pushToTalkEnabled, forKey: "pushToTalkEnabled")
            configurePushToTalk()
        }
    }
    @Published var voiceHotKeyEnabled = true {
        didSet {
            UserDefaults.standard.set(voiceHotKeyEnabled, forKey: "voiceHotKeyEnabled")
            configureGlobalHotKeys()
        }
    }
    @Published var textHotKeyEnabled = true {
        didSet {
            UserDefaults.standard.set(textHotKeyEnabled, forKey: "textHotKeyEnabled")
            configureGlobalHotKeys()
        }
    }
    @Published var voiceHotKey: HotKey {
        didSet {
            Self.saveHotKey(voiceHotKey, key: "voiceHotKey")
            configureGlobalHotKeys()
        }
    }
    @Published var textHotKey: HotKey {
        didSet {
            Self.saveHotKey(textHotKey, key: "textHotKey")
            configureGlobalHotKeys()
        }
    }
    @Published var hotKeyCaptureTarget: HotKeyCaptureTarget?
    @Published var textOverlayResponseMode: TextOverlayResponseMode = .text {
        didSet { UserDefaults.standard.set(textOverlayResponseMode.rawValue, forKey: "textOverlayResponseMode") }
    }
    @Published var launchAtLoginEnabled = false {
        didSet {
            guard !isApplyingLaunchAtLoginState else {
                return
            }
            guard launchAtLoginEnabled != oldValue else {
                return
            }
            do {
                try LaunchAtLoginService.setEnabled(launchAtLoginEnabled)
            } catch {
                lastError = error.localizedDescription
                isApplyingLaunchAtLoginState = true
                launchAtLoginEnabled = oldValue
                isApplyingLaunchAtLoginState = false
            }
        }
    }
    @Published var wakeWordsText: String {
        didSet {
            UserDefaults.standard.set(wakeWordsText, forKey: "wakeWordsText")
            if isEnabled, status == .listening {
                stopWakeWordServices()
                restartWakeWordListening(after: 0.2)
            }
        }
    }
    @Published var lastError = ""
    @Published var micDescription = "Microfone nao verificado"
    @Published var micLevel: Float = 0
    @Published var availableMicrophones: [AudioInputDevice] = AudioInputDeviceObserver.inputDevices()
    @Published var selectedMicrophoneUID: String {
        didSet { UserDefaults.standard.set(selectedMicrophoneUID, forKey: "selectedMicrophoneUID") }
    }
    @Published var speechLocaleID: String {
        didSet {
            UserDefaults.standard.set(speechLocaleID, forKey: "speechLocaleID")
            if isEnabled, status == .listening {
                stopWakeWordServices()
                restartWakeWordListening(after: 0.2)
            }
            refreshHealth()
        }
    }
    @Published var backendStatus = "Servidor nao verificado"
    @Published var backendHealth: BackendHealth?
    @Published var nativeOpenClawURL: String {
        didSet { UserDefaults.standard.set(nativeOpenClawURL, forKey: "nativeOpenClawURL") }
    }
    @Published var nativeRuntimeStatus = "Texto nativo pronto"
    @Published var nativeVoiceRuntimeEnabled = true {
        didSet { UserDefaults.standard.set(nativeVoiceRuntimeEnabled, forKey: "nativeVoiceRuntimeEnabled") }
    }
    @Published var strictLocalSTTEnabled = true {
        didSet {
            UserDefaults.standard.set(strictLocalSTTEnabled, forKey: "strictLocalSTTEnabled")
            if isEnabled, status == .listening {
                stopWakeWordServices()
                restartWakeWordListening(after: 0.2)
            }
            refreshHealth()
        }
    }
    @Published var localSTTEngine: LocalSTTEngine = .appleSpeech {
        didSet {
            UserDefaults.standard.set(localSTTEngine.rawValue, forKey: "localSTTEngine")
            refreshHealth()
        }
    }
    @Published var localTTSEngine: LocalTTSEngine = .ttsKitNeural {
        didSet {
            UserDefaults.standard.set(localTTSEngine.rawValue, forKey: "localTTSEngine")
            refreshHealth()
            warmUpNeuralTTSIfNeeded()
        }
    }
    @Published var neuralTTSVoiceID: String {
        didSet {
            UserDefaults.standard.set(neuralTTSVoiceID, forKey: "neuralTTSVoiceID")
            warmUpNeuralTTSIfNeeded()
        }
    }
    @Published var azureSpeechRegion: String {
        didSet {
            UserDefaults.standard.set(azureSpeechRegion, forKey: "azureSpeechRegion")
            refreshHealth()
        }
    }
    @Published var azureSpeechKey: String {
        didSet {
            KeychainStore.set(azureSpeechKey, for: "azureSpeechKey")
            refreshHealth()
        }
    }
    @Published var azureSpeechVoiceID: String {
        didSet {
            UserDefaults.standard.set(azureSpeechVoiceID, forKey: "azureSpeechVoiceID")
            refreshHealth()
        }
    }
    @Published var customTTSCommand: String {
        didSet {
            UserDefaults.standard.set(customTTSCommand, forKey: "customTTSCommand")
            refreshHealth()
        }
    }
    @Published var customTTSTimeoutSeconds: Double {
        didSet {
            UserDefaults.standard.set(customTTSTimeoutSeconds, forKey: "customTTSTimeoutSeconds")
            refreshHealth()
        }
    }
    @Published var localWakeWordEngine: LocalWakeWordEngine = .appleSpeech {
        didSet {
            UserDefaults.standard.set(localWakeWordEngine.rawValue, forKey: "localWakeWordEngine")
            if isEnabled, status == .listening {
                stopWakeWordServices()
                restartWakeWordListening(after: 0.2)
            }
            refreshHealth()
        }
    }
    @Published var lastCommandSource = ""
    @Published var recentInteractions: [InteractionRecord] = []
    @Published var screenContextEnabled = false {
        didSet {
            UserDefaults.standard.set(screenContextEnabled, forKey: "screenContextEnabled")
            screenContextStatus = screenContextEnabled ? screenContextMode.detail : "Desligado"
        }
    }
    @Published var screenOCREnabled = true {
        didSet { UserDefaults.standard.set(screenOCREnabled, forKey: "screenOCREnabled") }
    }
    @Published var screenContextMode: ScreenContextMode = .onDemand {
        didSet {
            UserDefaults.standard.set(screenContextMode.rawValue, forKey: "screenContextMode")
            if screenContextEnabled {
                screenContextStatus = screenContextMode.detail
            }
        }
    }
    @Published var screenContextStatus = "Desligado"
    @Published var screenDisplayIndex: Int {
        didSet { UserDefaults.standard.set(screenDisplayIndex, forKey: "screenDisplayIndex") }
    }
    @Published var screenMaxWidth: Double {
        didSet { UserDefaults.standard.set(Int(screenMaxWidth), forKey: "screenMaxWidth") }
    }
    @Published var screenIncludeCursor = true {
        didSet { UserDefaults.standard.set(screenIncludeCursor, forKey: "screenIncludeCursor") }
    }
    @Published var availableDisplays: [ScreenDisplayOption] = []
    @Published var voiceTestStatus = "Nao testado"
    @Published var voiceTestTranscript = ""
    @Published var voiceTestOriginalTranscript = ""
    @Published var voiceTestCorrections: [String] = []
    @Published var voiceTestLevel: Float = 0
    @Published var speechAnalyzerStatus = "Nao testado"
    @Published var speechAnalyzerAssetStatus = "Nao verificado"
    @Published var isInstallingSpeechAnalyzerAssets = false
    @Published var wakeWordRuntimeStatus = "Nao iniciado"
    @Published var permissionSnapshot = PermissionsService.snapshot()
    @Published var portDiagnosticsStatus = "Nao verificado"
    @Published var openClawConfigStatus = OpenClawConfigMonitor.summary()
    @Published var availableAgentIDs: [String] = OpenClawConfigMonitor.agentIDs(defaultID: defaultAgentID)
    @Published var agentEvents: [AgentEventRecord] = []
    @Published var ttsAttempts: [TTSProviderAttempt] = []
    @Published var nativeHealth: NativeHealthSnapshot?
    @Published var nativeHealthOperational = false
    @Published var detailedLoggingEnabled = true {
        didSet {
            UserDefaults.standard.set(detailedLoggingEnabled, forKey: "detailedLoggingEnabled")
        }
    }

    @Published var serverURL: String {
        didSet {
            UserDefaults.standard.set(serverURL, forKey: "serverURL")
            refreshHealth()
            refreshPortDiagnostics()
        }
    }

    @Published var clientToken: String {
        didSet {
            KeychainStore.set(clientToken, for: "clientToken")
            refreshHealth()
        }
    }
    @Published var agentID: String {
        didSet {
            UserDefaults.standard.set(agentID, forKey: "agentID")
            refreshHealth()
        }
    }

    private let wakeWordService = WakeWordService()
    private let dedicatedWakeWordService = DedicatedWakeWordService()
    private let coreMLWakeWordService = CoreMLWakeWordService()
    private let speechAnalyzerWakeWordService = SpeechAnalyzerWakeWordService()
    private let recorder = CommandRecorder()
    private let nativeSpeechRecognizer = NativeSpeechCommandRecognizer()
    private let speechAnalyzerRecognizer = SpeechAnalyzerCommandRecognizer()
    private let whisperCoreMLRuntime = WhisperCoreMLRuntime.shared
    private let neuralTTSRuntime = NeuralTTSRuntime.shared
    private let nativeOpenClaw = NativeOpenClawClient()
    private let playback = AudioPlaybackService()
    private let systemSpeech = SystemSpeechService()
    private let azureNeuralTTS = AzureNeuralTTSService()
    private let customCommandTTS = CustomCommandTTSService()
    private lazy var sentenceSpeechStreamer = NativeSentenceSpeechStreamer(
        speak: { [weak self] text in
            guard let self else { return .failed }
            return await self.speakLocally(text)
        },
        stop: { [weak self] in
            self?.stopLocalSpeech()
        }
    )
    private let chimePlayer = ChimePlayer()
    private let audioDeviceObserver = AudioInputDeviceObserver()
    private let pushToTalkService = PushToTalkService()
    private let globalHotKeyService = GlobalHotKeyService()
    private let speechInterruptionMonitor = SpeechInterruptionMonitor()
    private let screenContextService = ScreenContextService()
    private let overlay = VoiceOverlayController.shared
    private let textCommandOverlay = TextCommandOverlayController.shared
    private let sessionID: String
    private var commandTask: Task<Void, Never>?
    private var voiceTestTask: Task<Void, Never>?
    private var healthTask: Task<Void, Never>?
    private var wakeRestartTask: Task<Void, Never>?
    private var localMonitorTask: Task<Void, Never>?
    private var ttsWarmupTask: Task<Void, Never>?
    private var hotKeyCaptureMonitor: Any?
    private var isApplyingLaunchAtLoginState = false
    private var flowGeneration = 0
    private var lastNativeSTTEngineUsed = ""
    private var speechAnalyzerCooldownUntil: Date?
    private let speechAnalyzerFallbackCooldown: TimeInterval = 300
    private let voiceRuntime = VoiceRuntime.shared

    static let supportedSpeechLocales = [
        "pt-BR",
        "en-US",
        "es-ES"
    ]

    static let neuralTTSVoiceOptions = [
        NeuralTTSVoice(id: "aiden", title: "Aiden", detail: "Masculina clara; padrao para portugues"),
        NeuralTTSVoice(id: "ryan", title: "Ryan", detail: "Masculina mais expressiva"),
        NeuralTTSVoice(id: "uncle-fu", title: "Uncle Fu", detail: "Masculina grave"),
        NeuralTTSVoice(id: "dylan", title: "Dylan", detail: "Masculina jovem"),
        NeuralTTSVoice(id: "eric", title: "Eric", detail: "Masculina levemente rouca")
    ]

    static let azureSpeechVoiceOptions = [
        NeuralTTSVoice(id: "pt-BR-AntonioNeural", title: "Antonio", detail: "Masculina PT-BR; boa primeira opcao no F0"),
        NeuralTTSVoice(id: "pt-BR-FabioNeural", title: "Fabio", detail: "Masculina PT-BR alternativa"),
        NeuralTTSVoice(id: "pt-BR-DonatoNeural", title: "Donato", detail: "Masculina PT-BR mais grave"),
        NeuralTTSVoice(id: "pt-BR-HumbertoNeural", title: "Humberto", detail: "Masculina PT-BR clara"),
        NeuralTTSVoice(id: "pt-BR-JulioNeural", title: "Julio", detail: "Masculina PT-BR neutra"),
        NeuralTTSVoice(id: "pt-BR-NicolauNeural", title: "Nicolau", detail: "Masculina PT-BR alternativa"),
        NeuralTTSVoice(id: "pt-BR-ValerioNeural", title: "Valerio", detail: "Masculina PT-BR alternativa"),
        NeuralTTSVoice(id: "en-GB-RyanNeural", title: "Ryan EN-GB", detail: "Masculina em ingles; estilo mais proximo de assistente britanico"),
        NeuralTTSVoice(id: "en-GB-ThomasNeural", title: "Thomas EN-GB", detail: "Masculina em ingles britanico"),
        NeuralTTSVoice(id: "en-US-GuyNeural", title: "Guy EN-US", detail: "Masculina em ingles americano")
    ]

    init() {
        serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "https://localhost:8765"
        nativeOpenClawURL = UserDefaults.standard.string(forKey: "nativeOpenClawURL") ?? "http://127.0.0.1:18789"
        clientToken = KeychainStore.migrateUserDefaultsValue(key: "clientToken", account: "clientToken")
        agentID = UserDefaults.standard.string(forKey: "agentID") ?? Self.defaultAgentID
        selectedMicrophoneUID = UserDefaults.standard.string(forKey: "selectedMicrophoneUID") ?? ""
        speechLocaleID = UserDefaults.standard.string(forKey: "speechLocaleID") ?? "pt-BR"
        neuralTTSVoiceID = UserDefaults.standard.string(forKey: "neuralTTSVoiceID") ?? "aiden"
        azureSpeechRegion = UserDefaults.standard.string(forKey: "azureSpeechRegion") ?? "brazilsouth"
        azureSpeechKey = KeychainStore.migrateUserDefaultsValue(key: "azureSpeechKey", account: "azureSpeechKey")
        azureSpeechVoiceID = UserDefaults.standard.string(forKey: "azureSpeechVoiceID") ?? "pt-BR-AntonioNeural"
        customTTSCommand = UserDefaults.standard.string(forKey: "customTTSCommand") ?? ""
        customTTSTimeoutSeconds = UserDefaults.standard.object(forKey: "customTTSTimeoutSeconds") as? Double ?? 35
        detailedLoggingEnabled = UserDefaults.standard.object(forKey: "detailedLoggingEnabled") as? Bool ?? true
        wakeWordsText = UserDefaults.standard.string(forKey: "wakeWordsText") ?? "Jarvis"
        voiceResponsesEnabled = UserDefaults.standard.object(forKey: "voiceResponsesEnabled") as? Bool ?? true
        interruptSpeechEnabled = UserDefaults.standard.object(forKey: "interruptSpeechEnabled") as? Bool ?? false
        pushToTalkEnabled = UserDefaults.standard.object(forKey: "pushToTalkEnabled") as? Bool ?? true
        voiceHotKeyEnabled = UserDefaults.standard.object(forKey: "voiceHotKeyEnabled") as? Bool ?? true
        textHotKeyEnabled = UserDefaults.standard.object(forKey: "textHotKeyEnabled") as? Bool ?? true
        nativeVoiceRuntimeEnabled = UserDefaults.standard.object(forKey: "nativeVoiceRuntimeEnabled") as? Bool ?? true
        strictLocalSTTEnabled = UserDefaults.standard.object(forKey: "strictLocalSTTEnabled") as? Bool ?? true
        if let rawSTTEngine = UserDefaults.standard.string(forKey: "localSTTEngine"),
           let savedSTTEngine = LocalSTTEngine(rawValue: rawSTTEngine) {
            localSTTEngine = savedSTTEngine
        }
        if let rawTTSEngine = UserDefaults.standard.string(forKey: "localTTSEngine"),
           let savedTTSEngine = LocalTTSEngine(rawValue: rawTTSEngine) {
            localTTSEngine = savedTTSEngine
        } else {
            localTTSEngine = .ttsKitNeural
        }
        if UserDefaults.standard.object(forKey: "didMigrateDefaultTTSToTTSKit") == nil {
            localTTSEngine = .ttsKitNeural
            UserDefaults.standard.set(true, forKey: "didMigrateDefaultTTSToTTSKit")
        }
        if let rawWakeEngine = UserDefaults.standard.string(forKey: "localWakeWordEngine"),
           let savedWakeEngine = LocalWakeWordEngine(rawValue: rawWakeEngine) {
            localWakeWordEngine = savedWakeEngine
        }
        voiceHotKey = Self.loadHotKey(key: "voiceHotKey", fallback: .defaultVoice)
        textHotKey = Self.loadHotKey(key: "textHotKey", fallback: .defaultText)
        if let rawTextOverlayMode = UserDefaults.standard.string(forKey: "textOverlayResponseMode"),
           let savedTextOverlayMode = TextOverlayResponseMode(rawValue: rawTextOverlayMode) {
            textOverlayResponseMode = savedTextOverlayMode
        }
        launchAtLoginEnabled = LaunchAtLoginService.isEnabled
        sessionID = UserDefaults.standard.string(forKey: "sessionID") ?? UUID().uuidString
        UserDefaults.standard.set(sessionID, forKey: "sessionID")
        screenContextEnabled = UserDefaults.standard.object(forKey: "screenContextEnabled") as? Bool ?? false
        screenOCREnabled = UserDefaults.standard.object(forKey: "screenOCREnabled") as? Bool ?? true
        screenDisplayIndex = UserDefaults.standard.object(forKey: "screenDisplayIndex") as? Int ?? 0
        screenMaxWidth = Double(UserDefaults.standard.object(forKey: "screenMaxWidth") as? Int ?? 1400)
        screenIncludeCursor = UserDefaults.standard.object(forKey: "screenIncludeCursor") as? Bool ?? true
        if let rawMode = UserDefaults.standard.string(forKey: "screenContextMode"),
           let savedMode = ScreenContextMode(rawValue: rawMode) {
            screenContextMode = savedMode
        }
        screenContextStatus = screenContextEnabled ? screenContextMode.detail : "Desligado"
        recentInteractions = Self.loadHistory()
        updateMicDescription()
        startLocalMonitors()
        configureGlobalHotKeys()
        refreshPortDiagnostics()
        Task { [weak self] in
            await MainActor.run {
                self?.start()
            }
        }
        warmUpNeuralTTSIfNeeded()
    }

    func start() {
        guard !isEnabled else {
            return
        }
        isEnabled = true
        lastError = ""
        flowGeneration += 1
        commandTask?.cancel()
        commandTask = Task { [weak self] in
            await self?.prepareAndListen()
        }
    }

    func stop() {
        isEnabled = false
        flowGeneration += 1
        wakeRestartTask?.cancel()
        wakeRestartTask = nil
        voiceTestTask?.cancel()
        voiceTestTask = nil
        healthTask?.cancel()
        ttsWarmupTask?.cancel()
        ttsWarmupTask = nil
        stopWakeWordServices()
        recorder.stop()
        nativeSpeechRecognizer.stop()
        speechAnalyzerRecognizer.stop()
        playback.stop()
        sentenceSpeechStreamer.stop()
        stopLocalSpeech()
        speechInterruptionMonitor.stop()
        pushToTalkService.stop()
        audioDeviceObserver.stop()
        textCommandOverlay.hide()
        stopHotKeyCapture()
        overlay.hide()
        commandTask?.cancel()
        commandTask = nil
        micLevel = 0
        status = .stopped
    }

    func toggleVoiceResponses() {
        voiceResponsesEnabled.toggle()
    }

    func testCommandRecording() {
        guard isEnabled else {
            start()
            return
        }
        showOverlay()
        beginCommandFlow(source: .testButton)
    }

    func cancelCurrentInteraction() {
        flowGeneration += 1
        commandTask?.cancel()
        wakeRestartTask?.cancel()
        voiceTestTask?.cancel()
        stopWakeWordServices()
        recorder.stop()
        nativeSpeechRecognizer.stop()
        speechAnalyzerRecognizer.stop()
        playback.stop()
        sentenceSpeechStreamer.stop()
        stopLocalSpeech()
        speechInterruptionMonitor.stop()
        chimePlayer.play(.error)
        micLevel = 0
        textCommandOverlay.hide()
        overlay.hide()

        guard isEnabled else {
            status = .stopped
            return
        }
        restartWakeWordListening(after: 0.25)
    }

    // MARK: - Settings and Diagnostics

    func refreshHealth() {
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            await self?.refreshBackendHealth()
        }
    }

    func clearHistory() {
        recentInteractions = []
        persistHistory()
    }

    func copyDiagnosticsReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(DiagnosticsReportBuilder.makeReport(model: self), forType: .string)
    }

    func exportDiagnosticsBundle() {
        do {
            let report = DiagnosticsReportBuilder.makeReport(model: self)
            let url = try DiagnosticsFileLog.exportBundle(report: report)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            DiagnosticsFileLog.shared.log(
                category: "diagnostics",
                event: "exported",
                fields: ["path": url.path]
            )
        } catch {
            lastError = "Nao consegui exportar diagnosticos: \(error.localizedDescription)"
        }
    }

    func refreshPermissions() {
        permissionSnapshot = PermissionsService.snapshot()
    }

    func refreshAudioInputs() {
        availableMicrophones = AudioInputDeviceObserver.inputDevices()
        updateMicDescription()
    }

    func refreshDisplays() {
        Task { [weak self] in
            await self?.refreshDisplaysNow()
        }
    }

    func refreshPortDiagnostics() {
        Task { [weak self] in
            await self?.refreshPortDiagnosticsNow()
        }
    }

    func openMicrophoneSettings() {
        SystemSettingsOpener.openMicrophone()
    }

    func openSpeechRecognitionSettings() {
        SystemSettingsOpener.openSpeechRecognition()
    }

    func openScreenRecordingSettings() {
        SystemSettingsOpener.openScreenRecording()
    }

    func requestScreenRecordingPermission() {
        Task { [weak self] in
            let granted = await PermissionsService.requestScreenRecording()
            await MainActor.run {
                guard let self else {
                    return
                }
                self.permissionSnapshot = PermissionsService.snapshot()
                self.screenContextStatus = granted
                    ? "Permissao de tela OK"
                    : "Autorize Gravacao de Tela no macOS"
                if granted {
                    self.refreshDisplays()
                }
                if !granted {
                    SystemSettingsOpener.openScreenRecording()
                }
            }
        }
    }

    func openDiagnosticsLog() {
        do {
            let url = try DiagnosticsFileLog.ensureLogFileExists()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSWorkspace.shared.open(DiagnosticsFileLog.logDirectoryURL)
            lastError = "Nao consegui abrir os logs: \(error.localizedDescription)"
        }
    }

    func openWhisperModelFolder() {
        do {
            let url = try whisperCoreMLRuntime.ensureModelDirectory()
            NSWorkspace.shared.open(url)
        } catch {
            lastError = "Nao consegui abrir a pasta do Whisper/Core ML: \(error.localizedDescription)"
        }
    }

    func openTTSKitModelFolder() {
        do {
            let url = try neuralTTSRuntime.ensureModelDirectory()
            NSWorkspace.shared.open(url)
        } catch {
            lastError = "Nao consegui abrir a pasta do TTSKit: \(error.localizedDescription)"
        }
    }

    func openWakeWordModelFolder() {
        do {
            let url = try coreMLWakeWordService.ensureModelDirectory()
            NSWorkspace.shared.open(url)
        } catch {
            lastError = "Nao consegui abrir a pasta do wake word Core ML: \(error.localizedDescription)"
        }
    }

    func resetAgentToDefault() {
        agentID = Self.defaultAgentID
    }

    func refreshAgentOptions() {
        availableAgentIDs = OpenClawConfigMonitor.agentIDs(defaultID: Self.defaultAgentID)
    }

    func openAgentEventsWindow() {
        AgentEventsWindowController.shared.show(model: self)
    }

    func clearAgentEvents() {
        agentEvents = []
    }

    func runVoiceCalibration() {
        voiceTestTask?.cancel()
        voiceTestTask = Task { [weak self] in
            await self?.runVoiceCalibrationNow()
        }
    }

    func refreshSpeechAnalyzerAssets() {
        Task { [weak self] in
            guard let self else { return }
            let summary = await SpeechAnalyzerAssetService.status(localeID: self.speechLocaleID)
            await MainActor.run {
                self.speechAnalyzerAssetStatus = summary.message
                if summary.isAvailable {
                    self.speechAnalyzerCooldownUntil = nil
                }
            }
        }
    }

    func installSpeechAnalyzerAssets() {
        guard !isInstallingSpeechAnalyzerAssets else {
            return
        }
        isInstallingSpeechAnalyzerAssets = true
        speechAnalyzerAssetStatus = "Solicitando assets SpeechAnalyzer para \(speechLocaleID)..."
        Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await SpeechAnalyzerAssetService.install(localeID: self.speechLocaleID)
                await MainActor.run {
                    self.speechAnalyzerAssetStatus = summary.message
                    self.speechAnalyzerStatus = summary.isAvailable
                        ? "Assets prontos; teste o STT novamente"
                        : "Assets indisponiveis; fallback Apple Speech"
                    if summary.isAvailable {
                        self.speechAnalyzerCooldownUntil = nil
                    }
                    self.isInstallingSpeechAnalyzerAssets = false
                    self.refreshHealth()
                }
            } catch {
                await MainActor.run {
                    self.speechAnalyzerAssetStatus = "Falha ao instalar assets: \(error.localizedDescription)"
                    self.speechAnalyzerStatus = "Assets indisponiveis; fallback Apple Speech"
                    self.isInstallingSpeechAnalyzerAssets = false
                }
            }
        }
    }

    func beginHotKeyCapture(_ target: HotKeyCaptureTarget) {
        stopHotKeyCapture()
        hotKeyCaptureTarget = target
        hotKeyCaptureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleHotKeyCapture(event: event, target: target)
            }
            return nil
        }
    }

    func resetVoiceHotKey() {
        voiceHotKey = .defaultVoice
    }

    func resetTextHotKey() {
        textHotKey = .defaultText
    }

    private func prepareAndListen() async {
        status = .requestingPermission
        let granted = await PermissionsService.requestVoicePermissions()
        guard granted else {
            fail("Permissao de microfone/fala negada")
            return
        }

        updateMicDescription()
        applyPreferredMicrophone()
        audioDeviceObserver.start { [weak self] in
            Task { @MainActor in
                self?.handleAudioDeviceChange()
            }
        }
        configurePushToTalk()
        refreshHealth()
        startWakeWordListening()
    }

    private func startLocalMonitors() {
        localMonitorTask?.cancel()
        localMonitorTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                await self?.refreshLocalState(tick: tick)
                tick += 1
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func refreshLocalState(tick: Int) async {
        permissionSnapshot = PermissionsService.snapshot()
        openClawConfigStatus = OpenClawConfigMonitor.summary()
        availableAgentIDs = OpenClawConfigMonitor.agentIDs(defaultID: Self.defaultAgentID)
        availableMicrophones = AudioInputDeviceObserver.inputDevices()
        if tick == 0 || (tick % 12 == 0 && (localSTTEngine == .speechAnalyzer || localWakeWordEngine == .speechAnalyzer)) {
            speechAnalyzerAssetStatus = await SpeechAnalyzerAssetService.status(localeID: speechLocaleID).message
        }
        if tick % 6 == 0 {
            await refreshBackendHealth()
            await refreshPortDiagnosticsNow()
            await refreshDisplaysNow()
        }
    }

    private func refreshPortDiagnosticsNow() async {
        portDiagnosticsStatus = await PortDiagnosticsService.makeSummary(serverURL: serverURL)
    }

    // MARK: - STT and Calibration

    private func runVoiceCalibrationNow() async {
        flowGeneration += 1
        wakeRestartTask?.cancel()
        commandTask?.cancel()
        stopWakeWordServices()
        recorder.stop()
        nativeSpeechRecognizer.stop()
        speechAnalyzerRecognizer.stop()
        playback.stop()
        sentenceSpeechStreamer.stop()
        stopLocalSpeech()
        speechInterruptionMonitor.stop()
        applyPreferredMicrophone()

        let turn = await voiceRuntime.beginTurn(source: "Calibracao", agentID: resolvedAgentID)
        voiceTestStatus = "1/4 Verificando audio..."
        voiceTestTranscript = ""
        voiceTestOriginalTranscript = ""
        voiceTestCorrections = []
        voiceTestLevel = 0
        status = .recording
        await runNativeVoiceCalibration(turn: turn)
    }

    private func runNativeVoiceCalibration(turn: VoiceTurn) async {
        do {
            voiceTestStatus = "2/4 Fale uma frase curta..."
            let rawTranscript: String?
            switch localSTTEngine {
            case .appleSpeech:
                lastNativeSTTEngineUsed = LocalSTTEngine.appleSpeech.rawValue
                rawTranscript = try await nativeSpeechRecognizer.recognizeUntilSilence(
                    localeID: speechLocaleID,
                    requiresOnDeviceRecognition: strictLocalSTTEnabled,
                    contextualStrings: speechContextualStrings,
                    onLevel: { [weak self] level in
                        self?.voiceTestLevel = level
                    }
                )
            case .speechAnalyzer:
                rawTranscript = try await recognizeWithSpeechAnalyzerFallback { [weak self] level in
                    self?.voiceTestLevel = level
                }
            case .whisperCoreML:
                lastNativeSTTEngineUsed = LocalSTTEngine.whisperCoreML.rawValue
                rawTranscript = try await recordAndTranscribeWithWhisperCoreML { [weak self] level in
                    self?.voiceTestLevel = level
                }
            }
            let transcript = (rawTranscript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else {
                voiceTestStatus = "Nenhuma fala detectada pelo STT nativo"
                await voiceRuntime.endTurn(turn, outcome: "native_calibration_no_speech")
                finishVoiceCalibration()
                return
            }

            voiceTestTranscript = transcript
            voiceTestOriginalTranscript = transcript
            voiceTestCorrections = []
            voiceTestStatus = "3/4 STT nativo OK"
            _ = await speakLocally("Teste de áudio concluído.")
            voiceTestStatus = "4/4 Teste guiado concluido"
            await voiceRuntime.endTurn(turn, outcome: "native_calibration_completed", fields: [
                "text": transcript,
                "engine": actualNativeSTTEngine()
            ])
            DiagnosticsFileLog.shared.log(
                category: "diagnostics",
                event: "guided_audio_test_completed",
                fields: ["engine": actualNativeSTTEngine(), "text": transcript]
            )
        } catch {
            voiceTestStatus = "STT nativo indisponivel: \(error.localizedDescription)"
            await voiceRuntime.endTurn(turn, outcome: "native_calibration_error", fields: [
                "message": error.localizedDescription
            ])
        }

        finishVoiceCalibration()
    }

    private func finishVoiceCalibration() {
        voiceTestLevel = 0
        if isEnabled {
            restartWakeWordListening(after: 0.5)
        } else {
            status = .stopped
        }
    }

    private func recordAndTranscribeWithWhisperCoreML(
        onLevel: @escaping @MainActor (Float) -> Void
    ) async throws -> String? {
        nativeRuntimeStatus = "Whisper/Core ML gravando"
        status = .recording
        guard let wav = try await recorder.recordUntilSilence(onLevel: { level in
            Task { @MainActor in
                onLevel(level)
            }
        }), !wav.isEmpty else {
            return nil
        }

        nativeRuntimeStatus = "Whisper/Core ML transcrevendo"
        status = .processing
        return try await whisperCoreMLRuntime.transcribe(wavData: wav, localeID: speechLocaleID)
    }

    private func recognizeWithSpeechAnalyzerFallback(
        onLevel: @escaping @MainActor (Float) -> Void
    ) async throws -> String? {
        if let cooldownUntil = speechAnalyzerCooldownUntil, cooldownUntil > Date() {
            lastNativeSTTEngineUsed = "appleSpeechFallback"
            let remainingSeconds = Int(cooldownUntil.timeIntervalSinceNow.rounded(.up))
            speechAnalyzerStatus = "SpeechAnalyzer em cooldown; Apple Speech direto (\(remainingSeconds)s)"
            DiagnosticsFileLog.shared.log(
                category: "speech-analyzer",
                event: "cooldown_skip_to_apple_speech",
                fields: [
                    "locale": speechLocaleID,
                    "remainingSeconds": "\(remainingSeconds)"
                ]
            )
            return try await recognizeWithAppleSpeechFallback(onLevel: onLevel)
        }

        do {
            nativeRuntimeStatus = "SpeechAnalyzer escutando"
            let transcript = try await speechAnalyzerRecognizer.recognizeUntilSilence(
                localeID: speechLocaleID,
                contextualStrings: speechContextualStrings,
                emptyTimeout: 1.1,
                onLevel: onLevel
            )?
            .trimmingCharacters(in: .whitespacesAndNewlines)

            if let transcript, !transcript.isEmpty {
                lastNativeSTTEngineUsed = LocalSTTEngine.speechAnalyzer.rawValue
                speechAnalyzerCooldownUntil = nil
                speechAnalyzerStatus = "SpeechAnalyzer OK: \(transcript.count) caracteres"
                return transcript
            }

            lastNativeSTTEngineUsed = "appleSpeechFallback"
            speechAnalyzerCooldownUntil = Date().addingTimeInterval(speechAnalyzerFallbackCooldown)
            speechAnalyzerStatus = "SpeechAnalyzer retornou vazio; Apple Speech direto por 5 min"
            DiagnosticsFileLog.shared.log(
                category: "speech-analyzer",
                event: "empty_fallback_to_apple_speech",
                fields: [
                    "locale": speechLocaleID,
                    "cooldownSeconds": "\(Int(speechAnalyzerFallbackCooldown))"
                ]
            )
        } catch let error as CancellationError {
            throw error
        } catch {
            lastNativeSTTEngineUsed = "appleSpeechFallback"
            speechAnalyzerCooldownUntil = Date().addingTimeInterval(speechAnalyzerFallbackCooldown)
            speechAnalyzerStatus = "SpeechAnalyzer falhou; Apple Speech direto por 5 min: \(error.localizedDescription)"
            DiagnosticsFileLog.shared.log(
                category: "speech-analyzer",
                event: "error_fallback_to_apple_speech",
                fields: [
                    "locale": speechLocaleID,
                    "error": error.localizedDescription,
                    "cooldownSeconds": "\(Int(speechAnalyzerFallbackCooldown))"
                ]
            )
        }

        nativeRuntimeStatus = "SpeechAnalyzer indisponivel; Apple Speech fallback"
        return try await recognizeWithAppleSpeechFallback(onLevel: onLevel)
    }

    private func recognizeWithAppleSpeechFallback(
        onLevel: @escaping @MainActor (Float) -> Void
    ) async throws -> String? {
        lastNativeSTTEngineUsed = "appleSpeechFallback"
        return try await nativeSpeechRecognizer.recognizeUntilSilence(
            localeID: speechLocaleID,
            requiresOnDeviceRecognition: strictLocalSTTEnabled,
            contextualStrings: speechContextualStrings,
            onLevel: onLevel
        )
    }

    private func actualNativeSTTEngine() -> String {
        lastNativeSTTEngineUsed.isEmpty ? localSTTEngine.rawValue : lastNativeSTTEngineUsed
    }

    // MARK: - Audio Input and Screen

    private func refreshDisplaysNow() async {
        guard PermissionsService.isScreenRecordingAuthorized() else {
            availableDisplays = []
            return
        }
        do {
            availableDisplays = try await screenContextService.availableDisplays()
        } catch {
            availableDisplays = []
        }
    }

    private func applyPreferredMicrophone() {
        let uid = selectedMicrophoneUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uid.isEmpty else {
            return
        }
        let current = AudioInputDeviceObserver.defaultInputDeviceUID()
        guard current != uid else {
            return
        }
        if AudioInputDeviceObserver.setDefaultInputDevice(uid: uid) {
            DiagnosticsFileLog.shared.log(
                category: "audio",
                event: "microphone_selected",
                fields: ["uid": uid]
            )
            refreshAudioInputs()
        } else {
            lastError = "Nao consegui selecionar o microfone configurado"
            DiagnosticsFileLog.shared.log(
                category: "audio",
                event: "microphone_select_failed",
                fields: ["uid": uid]
            )
        }
    }

    private func configurePushToTalk() {
        pushToTalkService.stop()
        guard isEnabled, pushToTalkEnabled else {
            return
        }
        pushToTalkService.start { [weak self] in
            self?.handlePushToTalk()
        }
    }

    private func configureGlobalHotKeys() {
        globalHotKeyService.stop()

        let voice = voiceHotKeyEnabled ? voiceHotKey : nil
        let text = textHotKeyEnabled ? textHotKey : nil
        if let voice, let text, voice == text {
            lastError = "Use atalhos diferentes para voz e texto."
            return
        }

        do {
            try globalHotKeyService.start(
                voice: voice,
                text: text,
                onVoice: { [weak self] in
                    self?.handleVoiceHotKey()
                },
                onText: { [weak self] in
                    self?.showTextCommandPrompt()
                }
            )
        } catch {
            lastError = error.localizedDescription
            DiagnosticsFileLog.shared.log(
                category: "hotkey",
                event: "registration_failed",
                fields: ["error": error.localizedDescription]
            )
        }
    }

    private func stopHotKeyCapture() {
        if let hotKeyCaptureMonitor {
            NSEvent.removeMonitor(hotKeyCaptureMonitor)
            self.hotKeyCaptureMonitor = nil
        }
        hotKeyCaptureTarget = nil
    }

    private func handleHotKeyCapture(event: NSEvent, target: HotKeyCaptureTarget) {
        if event.keyCode == 53 {
            stopHotKeyCapture()
            return
        }

        guard let hotKey = HotKey(event: event) else {
            lastError = "Atalho precisa ter pelo menos um modificador."
            return
        }

        switch target {
        case .voice:
            guard hotKey != textHotKey else {
                lastError = "Use atalhos diferentes para voz e texto."
                stopHotKeyCapture()
                return
            }
            voiceHotKey = hotKey
        case .text:
            guard hotKey != voiceHotKey else {
                lastError = "Use atalhos diferentes para voz e texto."
                stopHotKeyCapture()
                return
            }
            textHotKey = hotKey
        }
        stopHotKeyCapture()
    }

    private func startWakeWordListening() {
        guard isEnabled else {
            status = .stopped
            return
        }

        wakeRestartTask?.cancel()
        stopWakeWordServices()
        recorder.stop()
        nativeSpeechRecognizer.stop()
        speechAnalyzerRecognizer.stop()
        playback.stop()
        sentenceSpeechStreamer.stop()
        stopLocalSpeech()
        speechInterruptionMonitor.stop()
        micLevel = 0
        overlay.hide(after: 0.15)

        do {
            applyPreferredMicrophone()
            var activeWakeEngineTitle = localWakeWordEngine.title
            switch localWakeWordEngine {
            case .appleSpeech:
                try startAppleSpeechWakeWord()
                wakeWordRuntimeStatus = "Apple Speech ativo"
            case .speechAnalyzer:
                // SpeechAnalyzer is still inconsistent for continuous wake detection
                // on macOS 26. Keep it selectable for STT experiments, but do not let
                // it leave the assistant apparently listening and deaf.
                activeWakeEngineTitle = "SpeechAnalyzer -> Apple Speech"
                wakeWordRuntimeStatus = "SpeechAnalyzer wake experimental; usando Apple Speech fallback"
                DiagnosticsFileLog.shared.log(
                    category: "wake-word",
                    event: "speech_analyzer_wake_fallback",
                    fields: ["reason": "continuous_wake_unreliable"]
                )
                try startAppleSpeechWakeWord()
            case .appleCommandRecognizer:
                activeWakeEngineTitle = "Detector dedicado -> Apple Speech"
                wakeWordRuntimeStatus = "Detector dedicado legado; usando Apple Speech fallback"
                DiagnosticsFileLog.shared.log(
                    category: "wake-word",
                    event: "dedicated_wake_fallback",
                    fields: ["reason": "ns_speech_recognizer_prompts_legacy_downloads"]
                )
                try startAppleSpeechWakeWord()
            case .coreMLKeywordSpotter:
                let coreMLStatus = coreMLWakeWordService.status()
                if coreMLStatus.isRuntimeAvailable {
                    try coreMLWakeWordService.start(
                        wakeWords: wakeWords,
                        confidenceThreshold: 0.78
                    ) { [weak self] detection in
                        Task { @MainActor in
                            self?.handleWakeWord(detection)
                        }
                    }
                    wakeWordRuntimeStatus = "Core ML Jarvis ativo"
                } else {
                    activeWakeEngineTitle = "Core ML Jarvis -> Apple Speech"
                    wakeWordRuntimeStatus = "\(coreMLStatus.summary); usando Apple Speech fallback"
                    DiagnosticsFileLog.shared.log(
                        category: "wake-word",
                        event: "coreml_wake_fallback",
                        fields: ["reason": coreMLStatus.summary]
                    )
                    lastError = coreMLStatus.summary + "; usando Apple Speech."
                    try startAppleSpeechWakeWord()
                }
            }
            status = .listening
            lastCommandSource = "Wake word (\(activeWakeEngineTitle))"
        } catch {
            wakeWordRuntimeStatus = "Erro na escuta: \(error.localizedDescription)"
            fail(error.localizedDescription)
        }
    }

    private func startAppleSpeechWakeWord() throws {
        let onWake: (WakeWordDetection) -> Void = { [weak self] detection in
            Task { @MainActor in
                self?.handleWakeWord(detection)
            }
        }

        do {
            try wakeWordService.start(
                wakeWords: wakeWords,
                localeID: speechLocaleID,
                requiresOnDeviceRecognition: strictLocalSTTEnabled,
                onWake: onWake
            )
        } catch WakeWordError.onDeviceUnavailable(_) where strictLocalSTTEnabled {
            DiagnosticsFileLog.shared.log(
                category: "wake-word",
                event: "apple_speech_cloud_fallback",
                fields: ["locale": speechLocaleID]
            )
            lastError = "Wake word on-device indisponivel para \(speechLocaleID); usando Apple Speech."
            wakeWordRuntimeStatus = "Apple Speech ativo sem on-device para \(speechLocaleID)"
            try wakeWordService.start(
                wakeWords: wakeWords,
                localeID: speechLocaleID,
                requiresOnDeviceRecognition: false,
                onWake: onWake
            )
        }
    }

    // MARK: - Wake Word

    private func restartWakeWordListening(after delay: TimeInterval = 0.35) {
        wakeRestartTask?.cancel()
        wakeRestartTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                guard let self, self.isEnabled else {
                    return
                }
                self.startWakeWordListening()
            }
        }
    }

    private func handleWakeWord(_ detection: WakeWordDetection) {
        guard isEnabled else {
            return
        }
        chimePlayer.play(.wake)
        status = .wakeDetected
        showOverlay()
        updateOverlay()
        let commandHint = detection.commandHint?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let commandHint, !commandHint.isEmpty {
            beginCommandFlow(source: .wakeWordInline, initialText: commandHint)
        } else {
            beginCommandFlow(source: .wakeWord)
        }
    }

    private func handlePushToTalk() {
        guard isEnabled else {
            return
        }
        showOverlay()
        beginCommandFlow(source: .pushToTalk)
    }

    private func handleVoiceHotKey() {
        guard isEnabled else {
            start()
            return
        }
        showOverlay()
        beginCommandFlow(source: .voiceHotKey)
    }

    private func showTextCommandPrompt() {
        textCommandOverlay.show { [weak self] text in
            Task { @MainActor in
                self?.handleTextHotKey(text)
            }
        }
    }

    private func handleTextHotKey(_ text: String) {
        transcription = text
        switch textOverlayResponseMode {
        case .voice:
            textCommandOverlay.hide()
            showOverlay()
            beginNativeTextVoiceFlow(text)
        case .text:
            beginTextOverlayFlow(text)
        }
    }

    // MARK: - Text and Agent Commands

    private func beginNativeTextVoiceFlow(_ text: String) {
        flowGeneration += 1
        let generation = flowGeneration
        commandTask?.cancel()
        wakeRestartTask?.cancel()
        stopWakeWordServices()
        recorder.stop()
        nativeSpeechRecognizer.stop()
        speechAnalyzerRecognizer.stop()
        playback.stop()
        sentenceSpeechStreamer.stop()
        stopLocalSpeech()
        speechInterruptionMonitor.stop()
        commandTask = Task { [weak self] in
            await self?.runNativeTextVoiceFlow(text: text, generation: generation)
        }
    }

    private func runNativeTextVoiceFlow(text: String, generation: Int) async {
        guard shouldContinueText(generation) else {
            return
        }

        lastCommandSource = "\(CommandSource.textHotKey.title) nativo"
        transcription = text
        response = ""
        status = .processing
        updateOverlay(transcript: text)
        let turn = await voiceRuntime.beginTurn(source: lastCommandSource, agentID: resolvedAgentID)
        await voiceRuntime.mark("native_text_voice_command", turn: turn, fields: ["text": text])
        if await handleLocalControlCommandIfNeeded(
            text: text,
            generation: generation,
            turn: turn,
            surface: .voiceOverlay
        ) {
            return
        }
        sentenceSpeechStreamer.begin()

        do {
            let screenContext = await prepareScreenContext(for: text, generation: generation, requiresVoiceRuntime: false)
            guard shouldContinueText(generation) else {
                await voiceRuntime.endTurn(turn, outcome: "cancelled")
                return
            }

            let result = try await sendNativeTextRequest(
                text: text,
                screenContext: screenContext
            ) { [weak self] partial in
                self?.response = partial
                self?.updateOverlay(transcript: partial)
                self?.sentenceSpeechStreamer.observe(partial)
            }

            transcription = result.transcription ?? text
            response = result.text ?? response
            appendHistory(source: lastCommandSource, transcript: transcription, response: response)
            updateOverlay(transcript: response.isEmpty ? "Sem resposta." : response)
            if result.directive?.speak != false, !response.isEmpty {
                status = .speaking
                updateOverlay(transcript: response)
                startSpeechInterruptionMonitor()
                await sentenceSpeechStreamer.finish(finalText: response)
                speechInterruptionMonitor.stop()
            } else {
                sentenceSpeechStreamer.stop()
            }
            if !NSApp.isActive {
                NativeNotificationService.shared.notify(title: "JARVIS", body: response)
            }
            await voiceRuntime.endTurn(turn, outcome: "completed")
            overlay.hide(after: 1.0)
            if isEnabled {
                restartWakeWordListening(after: 0.2)
            }
        } catch is CancellationError {
            sentenceSpeechStreamer.stop()
            await voiceRuntime.endTurn(turn, outcome: "cancelled")
            return
        } catch {
            sentenceSpeechStreamer.stop()
            lastError = error.localizedDescription
            status = .error(error.localizedDescription)
            updateOverlay(transcript: error.localizedDescription)
            if !NSApp.isActive {
                NativeNotificationService.shared.notify(title: "JARVIS", body: error.localizedDescription)
            }
            await voiceRuntime.endTurn(turn, outcome: "error", fields: ["message": error.localizedDescription])
            overlay.hide(after: 2.0)
            if isEnabled {
                restartWakeWordListening(after: 0.4)
            }
        }
    }

    private func beginTextOverlayFlow(_ text: String) {
        flowGeneration += 1
        let generation = flowGeneration
        commandTask?.cancel()
        wakeRestartTask?.cancel()
        stopWakeWordServices()
        recorder.stop()
        nativeSpeechRecognizer.stop()
        speechAnalyzerRecognizer.stop()
        playback.stop()
        sentenceSpeechStreamer.stop()
        stopLocalSpeech()
        speechInterruptionMonitor.stop()
        commandTask = Task { [weak self] in
            await self?.runTextOverlayFlow(text: text, generation: generation)
        }
    }

    private func runTextOverlayFlow(text: String, generation: Int) async {
        guard shouldContinueText(generation) else {
            return
        }

        lastCommandSource = CommandSource.textHotKey.title
        transcription = text
        response = ""
        status = .processing
        textCommandOverlay.updateStatus("Sincronizando com OpenClaw...")
        let turn = await voiceRuntime.beginTurn(source: CommandSource.textHotKey.title, agentID: resolvedAgentID)
        await voiceRuntime.mark("text_overlay_command", turn: turn, fields: ["text": text])
        if await handleLocalControlCommandIfNeeded(
            text: text,
            generation: generation,
            turn: turn,
            surface: .textOverlay
        ) {
            return
        }

        do {
            let screenContext = await prepareScreenContext(for: text, generation: generation, requiresVoiceRuntime: false)
            guard shouldContinueText(generation) else {
                await voiceRuntime.endTurn(turn, outcome: "cancelled")
                return
            }

            let result: VoiceResponse
            result = try await sendNativeTextRequest(
                text: text,
                screenContext: screenContext
            ) { [weak self] partial in
                self?.response = partial
                self?.textCommandOverlay.updateResponse(partial)
            }

            transcription = result.transcription ?? text
            response = result.text ?? response
            appendHistory(source: lastCommandSource, transcript: transcription, response: response)
            textCommandOverlay.updateResponse(response.isEmpty ? "Sem resposta." : response, isFinal: true)
            if textCommandOverlay.shouldNotifyOnCompletion {
                NativeNotificationService.shared.notify(title: "JARVIS", body: response)
            }
            await voiceRuntime.endTurn(turn, outcome: "completed")
            if isEnabled {
                restartWakeWordListening(after: 0.2)
            }
        } catch is CancellationError {
            await voiceRuntime.endTurn(turn, outcome: "cancelled")
            return
        } catch {
            textCommandOverlay.showError(error.localizedDescription)
            NativeNotificationService.shared.notify(title: "JARVIS", body: error.localizedDescription)
            await voiceRuntime.endTurn(turn, outcome: "error", fields: ["message": error.localizedDescription])
            lastError = error.localizedDescription
            if isEnabled {
                restartWakeWordListening(after: 0.4)
            }
        }
    }

    private func sendNativeTextRequest(
        text: String,
        screenContext: String?,
        onText: @escaping @MainActor (String) -> Void
    ) async throws -> VoiceResponse {
        nativeRuntimeStatus = "Texto nativo em uso"
        recordAgentEvent(
            title: "Enviando ao agente",
            detail: String(text.prefix(220)),
            severity: .info
        )
        let result = try await nativeOpenClaw.streamTextCommand(
            text: text,
            gatewayURL: nativeOpenClawURL,
            token: OpenClawConfigMonitor.authToken(),
            agentID: resolvedAgentID,
            sessionID: sessionID,
            screenContext: screenContext,
            onText: onText
        )
        recordAgentEvent(
            title: "Resposta recebida",
            detail: String((result.text ?? "Sem texto").prefix(220)),
            severity: result.type == "error" ? .error : .success
        )
        return result
    }

    private func handleAudioDeviceChange() {
        updateMicDescription()
        guard isEnabled else {
            return
        }
        if status == .listening {
            stopWakeWordServices()
            restartWakeWordListening(after: 0.7)
        }
    }

    private func stopWakeWordServices() {
        wakeWordService.stop()
        dedicatedWakeWordService.stop()
        coreMLWakeWordService.stop()
        speechAnalyzerWakeWordService.stop()
    }

    private func cleanCommandTranscript(_ transcript: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stripped = WakeWordGate.stripWakeWord(from: trimmed)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !stripped.isEmpty else {
            return trimmed
        }
        return stripped
    }

    private func handleLocalControlCommandIfNeeded(
        text: String,
        generation: Int,
        turn: VoiceTurn,
        surface: LocalControlSurface
    ) async -> Bool {
        let stillActive = surface == .textOverlay
            ? shouldContinueText(generation)
            : shouldContinue(generation)
        guard stillActive else {
            await voiceRuntime.endTurn(turn, outcome: "cancelled")
            return true
        }

        let outcome = AgentSwitchCommand.parse(
            text,
            availableAgents: agentPickerOptions,
            defaultAgentID: Self.defaultAgentID
        )

        let message: String
        let eventTitle: String
        let eventSeverity: AgentEventRecord.Severity

        switch outcome {
        case .none:
            return false
        case .switchTo(let nextAgent):
            agentID = nextAgent
            message = "Agente alterado para \(nextAgent)."
            eventTitle = "Agente alterado"
            eventSeverity = .success
            chimePlayer.play(.sent)
        case .reset:
            agentID = Self.defaultAgentID
            message = "Agente padrao restaurado: \(Self.defaultAgentID)."
            eventTitle = "Agente padrao restaurado"
            eventSeverity = .success
            chimePlayer.play(.sent)
        case .list:
            let agents = agentPickerOptions.joined(separator: ", ")
            message = agents.isEmpty
                ? "Nao encontrei agentes cadastrados."
                : "Agentes disponiveis: \(agents)."
            eventTitle = "Lista de agentes"
            eventSeverity = .info
        case .unknown(let requested):
            let agents = agentPickerOptions.joined(separator: ", ")
            message = "Nao encontrei o agente \(requested). Disponiveis: \(agents)."
            eventTitle = "Agente nao encontrado"
            eventSeverity = .warning
            chimePlayer.play(.error)
        }

        transcription = text
        response = message
        status = surface == .voiceOverlay && voiceResponsesEnabled ? .speaking : .processing
        nativeRuntimeStatus = "Comando local: agente"
        appendHistory(source: "Controle local", transcript: text, response: message)
        recordAgentEvent(title: eventTitle, detail: message, severity: eventSeverity)
        await voiceRuntime.mark("local_agent_command", turn: turn, fields: [
            "text": text,
            "outcome": "\(outcome)",
            "agentID": resolvedAgentID
        ])

        switch surface {
        case .textOverlay:
            textCommandOverlay.updateResponse(message, isFinal: true)
            if textCommandOverlay.shouldNotifyOnCompletion {
                NativeNotificationService.shared.notify(title: "JARVIS", body: message)
            }
        case .voiceOverlay:
            updateOverlay(transcript: message)
            if voiceResponsesEnabled {
                _ = await speakLocally(message)
            }
            overlay.hide(after: 1.0)
        }

        await voiceRuntime.endTurn(turn, outcome: "local_agent_command")
        if isEnabled {
            restartWakeWordListening(after: 0.2)
        }
        return true
    }

    // MARK: - TTS

    private func speakLocally(_ text: String) async -> PlaybackResult {
        let characterCount = text.count
        switch localTTSEngine {
        case .ttsKitNeural:
            let started = Date()
            do {
                try await neuralTTSRuntime.speak(
                    text,
                    localeID: speechLocaleID,
                    voiceID: neuralTTSVoiceID
                )
                recordTTSAttempt(
                    provider: "TTSKit Neural",
                    voice: neuralTTSVoiceID,
                    characterCount: characterCount,
                    started: started,
                    result: .finished
                )
                return .finished
            } catch {
                DiagnosticsFileLog.shared.log(
                    category: "tts",
                    event: "neural_fallback",
                    fields: ["reason": error.localizedDescription]
                )
                recordTTSAttempt(
                    provider: "TTSKit Neural",
                    voice: neuralTTSVoiceID,
                    characterCount: characterCount,
                    started: started,
                    result: .failed,
                    fallbackReason: error.localizedDescription
                )
                let fallbackStarted = Date()
                let fallback = await systemSpeech.speak(text, localeID: speechLocaleID, engine: .appleNeuralEnhanced)
                recordTTSAttempt(
                    provider: "Apple Neural/Enhanced",
                    voice: systemSpeech.lastVoiceSummary,
                    characterCount: characterCount,
                    started: fallbackStarted,
                    result: fallback,
                    fallbackReason: "fallback de TTSKit"
                )
                return fallback
            }
        case .azureNeural:
            let started = Date()
            let result = await azureNeuralTTS.speak(
                text,
                regionOrEndpoint: azureSpeechRegion,
                subscriptionKey: azureSpeechKey,
                voiceID: azureSpeechVoiceID,
                localeID: speechLocaleID
            )
            if result == .failed {
                DiagnosticsFileLog.shared.log(
                    category: "tts",
                    event: "azure_neural_fallback",
                    fields: ["voice": azureSpeechVoiceID, "region": azureSpeechRegion]
                )
                recordTTSAttempt(
                    provider: "Azure Neural",
                    voice: azureSpeechVoiceID,
                    characterCount: characterCount,
                    started: started,
                    result: result,
                    fallbackReason: azureNeuralTTS.lastVoiceSummary
                )
                let fallbackStarted = Date()
                let fallback = await systemSpeech.speak(text, localeID: speechLocaleID, engine: .appleNeuralEnhanced)
                recordTTSAttempt(
                    provider: "Apple Neural/Enhanced",
                    voice: systemSpeech.lastVoiceSummary,
                    characterCount: characterCount,
                    started: fallbackStarted,
                    result: fallback,
                    fallbackReason: "fallback de Azure"
                )
                return fallback
            }
            recordTTSAttempt(
                provider: "Azure Neural",
                voice: azureSpeechVoiceID,
                characterCount: characterCount,
                started: started,
                result: result
            )
            return result
        case .customCommand:
            let started = Date()
            let result = await customCommandTTS.speak(
                text,
                commandTemplate: customTTSCommand,
                timeoutSeconds: customTTSTimeoutSeconds
            )
            if result == .failed {
                recordTTSAttempt(
                    provider: "TTS local por comando",
                    voice: "custom",
                    characterCount: characterCount,
                    started: started,
                    result: result,
                    fallbackReason: customCommandTTS.lastVoiceSummary
                )
                let fallbackStarted = Date()
                let fallback = await systemSpeech.speak(text, localeID: speechLocaleID, engine: .appleNeuralEnhanced)
                recordTTSAttempt(
                    provider: "Apple Neural/Enhanced",
                    voice: systemSpeech.lastVoiceSummary,
                    characterCount: characterCount,
                    started: fallbackStarted,
                    result: fallback,
                    fallbackReason: "fallback de comando local"
                )
                return fallback
            }
            recordTTSAttempt(
                provider: "TTS local por comando",
                voice: "custom",
                characterCount: characterCount,
                started: started,
                result: result
            )
            return result
        case .appleSystem, .appleNeuralEnhanced:
            let started = Date()
            let result = await systemSpeech.speak(text, localeID: speechLocaleID, engine: localTTSEngine)
            recordTTSAttempt(
                provider: localTTSEngine.title,
                voice: systemSpeech.lastVoiceSummary,
                characterCount: characterCount,
                started: started,
                result: result
            )
            return result
        }
    }

    private func speakGreeting(_ text: String) async -> PlaybackResult {
        await speakLocally(text)
    }

    private func warmUpNeuralTTSIfNeeded() {
        guard localTTSEngine == .ttsKitNeural else {
            ttsWarmupTask?.cancel()
            ttsWarmupTask = nil
            return
        }
        ttsWarmupTask?.cancel()
        let localeID = speechLocaleID
        let voiceID = neuralTTSVoiceID
        ttsWarmupTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else {
                return
            }
            await self?.neuralTTSRuntime.prepare(localeID: localeID, voiceID: voiceID)
        }
    }

    private func stopLocalSpeech() {
        neuralTTSRuntime.stop()
        azureNeuralTTS.stop()
        customCommandTTS.stop()
        systemSpeech.stop()
    }

    private func recordTTSAttempt(
        provider: String,
        voice: String,
        characterCount: Int,
        started: Date,
        result: PlaybackResult,
        fallbackReason: String? = nil
    ) {
        let attempt = TTSProviderAttempt(
            provider: provider,
            voice: voice,
            characterCount: characterCount,
            durationMs: Int(Date().timeIntervalSince(started) * 1000),
            result: "\(result)",
            fallbackReason: fallbackReason
        )
        ttsAttempts.insert(attempt, at: 0)
        if ttsAttempts.count > 20 {
            ttsAttempts = Array(ttsAttempts.prefix(20))
        }
        var fields = [
            "provider": provider,
            "voice": voice,
            "chars": "\(characterCount)",
            "durationMs": "\(attempt.durationMs)",
            "result": attempt.result
        ]
        if let fallbackReason {
            fields["fallbackReason"] = fallbackReason
        }
        DiagnosticsFileLog.shared.log(category: "tts", event: "provider_attempt", fields: fields)
    }

    private func recordAgentEvent(
        title: String,
        detail: String,
        severity: AgentEventRecord.Severity = .info
    ) {
        let event = AgentEventRecord(
            title: title,
            detail: detail,
            agentID: resolvedAgentID,
            severity: severity
        )
        agentEvents.insert(event, at: 0)
        if agentEvents.count > 80 {
            agentEvents = Array(agentEvents.prefix(80))
        }
        DiagnosticsFileLog.shared.log(
            category: "agent",
            event: title
                .lowercased()
                .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "pt-BR"))
                .replacingOccurrences(of: " ", with: "_"),
            fields: [
                "agentID": resolvedAgentID,
                "severity": severity.rawValue,
                "detail": detail
            ]
        )
    }

    private func updateMicDescription() {
        micDescription = AudioInputDeviceObserver.defaultInputDeviceSummary()
    }

    // MARK: - Voice Flow

    private func beginCommandFlow(source: CommandSource, initialText: String? = nil) {
        guard isEnabled else {
            return
        }

        flowGeneration += 1
        let generation = flowGeneration
        commandTask?.cancel()
        wakeRestartTask?.cancel()
        stopWakeWordServices()
        recorder.stop()
        nativeSpeechRecognizer.stop()
        speechAnalyzerRecognizer.stop()
        playback.stop()
        sentenceSpeechStreamer.stop()
        stopLocalSpeech()
        speechInterruptionMonitor.stop()
        commandTask = Task { [weak self] in
            await self?.runCommandFlow(source: source, initialText: initialText, generation: generation)
        }
    }

    private func runCommandFlow(source: CommandSource, initialText: String?, generation: Int) async {
        guard shouldContinue(generation) else {
            return
        }

        lastCommandSource = source.title
        let turn = await voiceRuntime.beginTurn(source: source.title, agentID: resolvedAgentID)

        if let initialText, !initialText.isEmpty {
            transcription = initialText
            response = ""
            await voiceRuntime.mark("inline_text", turn: turn, fields: ["text": initialText])
            updateOverlay(transcript: initialText)
            if await handleLocalControlCommandIfNeeded(
                text: initialText,
                generation: generation,
                turn: turn,
                surface: .voiceOverlay
            ) {
                return
            }
        } else {
            await prepareRecorderFor(source: source, generation: generation)
        }

        guard shouldContinue(generation) else {
            return
        }

        do {
            let result: VoiceResponse
            if let initialText, !initialText.isEmpty {
                let preflight = CommandPreflightFilter.evaluate(
                    initialText,
                    allowsShortReply: source == .followUp
                )
                guard preflight.shouldSend else {
                    await rejectCommandBeforeAgent(
                        preflight,
                        transcript: initialText,
                        generation: generation,
                        turn: turn
                    )
                    return
                }

                status = .processing
                response = ""
                updateOverlay(transcript: initialText)
                sentenceSpeechStreamer.begin()
                let screenContext = await prepareScreenContext(for: initialText, generation: generation)
                guard shouldContinue(generation) else {
                    sentenceSpeechStreamer.stop()
                    return
                }
                result = try await sendNativeTextRequest(
                    text: initialText,
                    screenContext: screenContext
                ) { [weak self] partial in
                    self?.response = partial
                    self?.updateOverlay(transcript: partial)
                    self?.sentenceSpeechStreamer.observe(partial)
                }
            } else {
                if await runNativeVoiceCommand(source: source, generation: generation, turn: turn) {
                    return
                }
                await voiceRuntime.endTurn(turn, outcome: "native_voice_unavailable")
                fail("Runtime nativo de voz indisponivel")
                return
            }

            await voiceRuntime.mark("agent_response", turn: turn, fields: [
                "expectingReply": "\(result.expectingReply == true)",
                "corrections": (result.normalizationCorrections ?? []).joined(separator: ",")
            ])
            let speechAlreadyHandled = initialText?.isEmpty == false
                ? await finishNativeSpeechStreamIfNeeded(result: result, generation: generation)
                : false
            await handle(result: result, generation: generation, speechAlreadyHandled: speechAlreadyHandled)
            await voiceRuntime.endTurn(turn, outcome: "completed")
        } catch is CancellationError {
            sentenceSpeechStreamer.stop()
            await voiceRuntime.endTurn(turn, outcome: "cancelled")
            return
        } catch {
            sentenceSpeechStreamer.stop()
            await voiceRuntime.endTurn(turn, outcome: "error", fields: ["message": error.localizedDescription])
            fail(error.localizedDescription)
        }
    }

    private func runNativeVoiceCommand(source: CommandSource, generation: Int, turn: VoiceTurn) async -> Bool {
        applyPreferredMicrophone()
        status = .recording
        transcription = ""
        response = ""
        nativeRuntimeStatus = "Voz nativa escutando"
        updateOverlay()

        let commandText: String
        do {
            let transcript: String?
            switch localSTTEngine {
            case .appleSpeech:
                lastNativeSTTEngineUsed = LocalSTTEngine.appleSpeech.rawValue
                transcript = try await nativeSpeechRecognizer.recognizeUntilSilence(
                    localeID: speechLocaleID,
                    requiresOnDeviceRecognition: strictLocalSTTEnabled,
                    contextualStrings: speechContextualStrings,
                    onLevel: { [weak self] level in
                        self?.micLevel = level
                        self?.updateOverlay()
                    }
                )
            case .speechAnalyzer:
                transcript = try await recognizeWithSpeechAnalyzerFallback { [weak self] level in
                    self?.micLevel = level
                    self?.updateOverlay()
                }
            case .whisperCoreML:
                lastNativeSTTEngineUsed = LocalSTTEngine.whisperCoreML.rawValue
                transcript = try await recordAndTranscribeWithWhisperCoreML { [weak self] level in
                    self?.micLevel = level
                    self?.updateOverlay()
                }
            }

            guard shouldContinue(generation) else {
                await voiceRuntime.endTurn(turn, outcome: "cancelled")
                return true
            }

            let trimmed = (transcript ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                await voiceRuntime.endTurn(turn, outcome: "native_no_speech")
                nativeRuntimeStatus = "Voz nativa: nenhuma fala detectada"
                restartWakeWordListening()
                return true
            }
            commandText = cleanCommandTranscript(trimmed)
            if await handleLocalControlCommandIfNeeded(
                text: commandText,
                generation: generation,
                turn: turn,
                surface: .voiceOverlay
            ) {
                return true
            }
            let preflight = CommandPreflightFilter.evaluate(
                commandText,
                allowsShortReply: source == .followUp
            )
            guard preflight.shouldSend else {
                await rejectCommandBeforeAgent(
                    preflight,
                    transcript: commandText,
                    generation: generation,
                    turn: turn
                )
                return true
            }
        } catch is CancellationError {
            await voiceRuntime.endTurn(turn, outcome: "cancelled")
            return true
        } catch {
            nativeRuntimeStatus = "STT nativo indisponivel"
            DiagnosticsFileLog.shared.log(
                category: "native-voice",
                event: "stt_error",
                fields: [
                    "source": source.title,
                    "engine": actualNativeSTTEngine(),
                    "error": error.localizedDescription
                ]
            )
            await voiceRuntime.endTurn(turn, outcome: "native_stt_error", fields: ["message": error.localizedDescription])
            fail(error.localizedDescription)
            return true
        }

        transcription = commandText
        status = .processing
        updateOverlay(transcript: commandText)
        await voiceRuntime.mark("native_transcribed", turn: turn, fields: [
            "text": commandText,
            "engine": actualNativeSTTEngine()
        ])
        sentenceSpeechStreamer.begin()

        do {
            let screenContext = await prepareScreenContext(for: commandText, generation: generation)
            guard shouldContinue(generation) else {
                await voiceRuntime.endTurn(turn, outcome: "cancelled")
                return true
            }

            let result = try await sendNativeTextRequest(
                text: commandText,
                screenContext: screenContext
            ) { [weak self] partial in
                self?.response = partial
                self?.updateOverlay(transcript: partial)
                self?.sentenceSpeechStreamer.observe(partial)
            }

            if localSTTEngine == .speechAnalyzer, speechAnalyzerStatus.hasPrefix("SpeechAnalyzer OK") {
                speechAnalyzerStatus = "SpeechAnalyzer OK: comando processado"
            }
            await voiceRuntime.mark("agent_response", turn: turn, fields: [
                "expectingReply": "\(result.expectingReply == true)",
                "runtime": "native"
            ])
            let spokenByStreamer = await finishNativeSpeechStreamIfNeeded(result: result, generation: generation)
            await handle(result: result, generation: generation, speechAlreadyHandled: spokenByStreamer)
            await voiceRuntime.endTurn(turn, outcome: "completed_native")
            return true
        } catch is CancellationError {
            sentenceSpeechStreamer.stop()
            await voiceRuntime.endTurn(turn, outcome: "cancelled")
            return true
        } catch {
            sentenceSpeechStreamer.stop()
            await voiceRuntime.endTurn(turn, outcome: "native_error", fields: ["message": error.localizedDescription])
            fail(error.localizedDescription)
            return true
        }
    }

    private func rejectCommandBeforeAgent(
        _ preflight: CommandPreflightResult,
        transcript: String,
        generation: Int,
        turn: VoiceTurn
    ) async {
        guard shouldContinue(generation) else {
            await voiceRuntime.endTurn(turn, outcome: "cancelled")
            return
        }

        transcription = transcript
        response = preflight.prompt
        nativeRuntimeStatus = "Filtro local: \(preflight.reason)"
        status = .processing
        updateOverlay(transcript: preflight.prompt)
        chimePlayer.play(.error)
        await voiceRuntime.mark("preflight_rejected", turn: turn, fields: [
            "reason": preflight.reason,
            "text": transcript
        ])
        DiagnosticsFileLog.shared.log(
            category: "native-voice",
            event: "preflight_rejected",
            fields: [
                "reason": preflight.reason,
                "text": transcript,
                "source": turn.source
            ]
        )

        if voiceResponsesEnabled {
            status = .speaking
            updateOverlay(transcript: preflight.prompt)
            _ = await speakLocally(preflight.prompt)
        }

        await voiceRuntime.endTurn(turn, outcome: "preflight_rejected", fields: [
            "reason": preflight.reason
        ])
        overlay.hide(after: 1.0)
        if isEnabled {
            restartWakeWordListening(after: 0.2)
        }
    }

    private func prepareRecorderFor(source: CommandSource, generation: Int) async {
        switch source {
        case .wakeWord:
            status = .wakeDetected
            updateOverlay()
            if voiceResponsesEnabled {
                nativeRuntimeStatus = "Greeting nativo"
                let result = await speakGreeting(NativeGreetingService.nextPhrase())
                if result == .failed {
                    chimePlayer.play(.listen)
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
                chimePlayer.play(.listen)
            } else {
                chimePlayer.play(.listen)
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        case .followUp:
            status = .awaitingFollowUp
            showOverlay()
            updateOverlay()
            chimePlayer.play(.followUp)
            try? await Task.sleep(nanoseconds: 250_000_000)
        case .pushToTalk, .voiceHotKey, .testButton:
            status = .wakeDetected
            updateOverlay()
            chimePlayer.play(.listen)
            try? await Task.sleep(nanoseconds: 180_000_000)
        case .wakeWordInline, .textHotKey:
            break
        }

        guard shouldContinue(generation) else {
            return
        }
        micLevel = 0
    }

    private func prepareScreenContext(
        for commandText: String,
        generation: Int,
        requiresVoiceRuntime: Bool = true
    ) async -> String? {
        guard screenContextEnabled else {
            screenContextStatus = "Desligado"
            return nil
        }

        guard screenContextMode.shouldCapture(for: commandText) else {
            screenContextStatus = "Aguardando comando visual"
            return nil
        }

        guard PermissionsService.isScreenRecordingAuthorized() else {
            permissionSnapshot = PermissionsService.snapshot()
            screenContextStatus = "Permissao de tela pendente"
            DiagnosticsFileLog.shared.log(
                category: "screen",
                event: "permission_missing",
                fields: ["mode": screenContextMode.rawValue]
            )
            return nil
        }

        guard requiresVoiceRuntime ? shouldContinue(generation) : shouldContinueText(generation) else {
            return nil
        }

        screenContextStatus = screenOCREnabled ? "Lendo tela..." : "Capturando tela..."
        updateOverlay(transcript: "\(commandText)\n\(screenContextStatus)")
        DiagnosticsFileLog.shared.log(
            category: "screen",
            event: "capture_started",
            fields: ["mode": screenContextMode.rawValue, "ocr": "\(screenOCREnabled)"]
        )

        do {
            let context = try await screenContextService.makeContext(
                ocrEnabled: screenOCREnabled,
                options: screenCaptureOptions
            )
            guard requiresVoiceRuntime ? shouldContinue(generation) : shouldContinueText(generation) else {
                return nil
            }
            if screenOCREnabled {
                screenContextStatus = "OCR: \(context.characterCount) caracteres"
            } else {
                screenContextStatus = "Tela capturada sem OCR"
            }
            DiagnosticsFileLog.shared.log(
                category: "screen",
                event: "capture_completed",
                fields: [
                    "ocrChars": "\(context.characterCount)",
                    "size": "\(context.imageWidth)x\(context.imageHeight)",
                    "display": "\(context.displayIndex + 1)",
                    "maxWidth": "\(Int(screenMaxWidth))",
                    "cursor": "\(screenIncludeCursor)"
                ]
            )
            return context.promptText
        } catch {
            screenContextStatus = "Tela indisponivel: \(error.localizedDescription)"
            DiagnosticsFileLog.shared.log(
                category: "screen",
                event: "capture_failed",
                fields: ["error": error.localizedDescription]
            )
            return nil
        }
    }

    private func finishNativeSpeechStreamIfNeeded(result: VoiceResponse, generation: Int) async -> Bool {
        let text = (result.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldSpeak = voiceResponsesEnabled && (result.directive?.speak ?? true) && !text.isEmpty
        guard shouldSpeak else {
            sentenceSpeechStreamer.stop()
            return false
        }

        guard shouldContinue(generation) else {
            sentenceSpeechStreamer.stop()
            return true
        }

        status = .speaking
        updateOverlay(transcript: text)
        startSpeechInterruptionMonitor()
        await sentenceSpeechStreamer.finish(finalText: text)
        speechInterruptionMonitor.stop()
        return true
    }

    private func handle(result: VoiceResponse, generation: Int, speechAlreadyHandled: Bool = false) async {
        guard shouldContinue(generation) else {
            return
        }

        if result.type == "no_speech" {
            restartWakeWordListening()
            return
        }

        if result.type == "error" {
            fail(result.message ?? "Erro no backend")
            return
        }

        transcription = result.transcription ?? transcription
        response = result.text ?? ""
        appendHistory(source: lastCommandSource, transcript: transcription, response: response)
        updateOverlay(transcript: response.isEmpty ? transcription : response)

        let shouldSpeak = voiceResponsesEnabled && !speechAlreadyHandled && (result.directive?.speak ?? true)
        if shouldSpeak {
            status = .speaking
            updateOverlay(transcript: response)
            startSpeechInterruptionMonitor()
            if let audio = result.audioData, !audio.isEmpty {
                _ = try? await playback.play(data: audio)
            } else if let text = result.text, !text.isEmpty {
                _ = await speakLocally(text)
            }
            speechInterruptionMonitor.stop()
        }

        guard shouldContinue(generation) else {
            return
        }

        if result.expectingReply == true {
            beginCommandFlow(source: .followUp)
        } else {
            overlay.hide(after: 1.2)
            restartWakeWordListening()
        }
    }

    private func refreshBackendHealth() async {
        let health = await NativeDiagnosticsService.makeSnapshot(
            gatewayURL: nativeOpenClawURL,
            agentID: resolvedAgentID,
            speechLocaleID: speechLocaleID,
            strictLocalSTT: strictLocalSTTEnabled,
            sttEngine: localSTTEngine,
            ttsEngine: localTTSEngine,
            azureSpeechRegion: azureSpeechRegion,
            azureSpeechKey: azureSpeechKey,
            azureSpeechVoiceID: azureSpeechVoiceID,
            wakeWordEngine: localWakeWordEngine
        )
        nativeHealth = health
        nativeHealthOperational = health.isOperational
        backendHealth = nil
        backendStatus = health.summary
        nativeRuntimeStatus = [
            health.gateway,
            "Wake \(localWakeWordEngine.title)",
            health.wakeWord,
            "STT \(localSTTEngine.title)",
            "TTS \(localTTSEngine.title)",
            health.speech,
            health.whisper,
            health.tts
        ].joined(separator: " | ")
    }

    private func shouldContinue(_ generation: Int) -> Bool {
        isEnabled && flowGeneration == generation && !Task.isCancelled
    }

    private func shouldContinueText(_ generation: Int) -> Bool {
        flowGeneration == generation && !Task.isCancelled
    }

    // MARK: - Runtime State

    private func showOverlay() {
        overlay.show { [weak self] in
            Task { @MainActor in
                self?.cancelCurrentInteraction()
            }
        }
    }

    private func updateOverlay(transcript: String? = nil) {
        overlay.update(
            status: status,
            transcript: transcript ?? transcription,
            level: micLevel
        )
    }

    private func startSpeechInterruptionMonitor() {
        let requireWakeWord = !interruptSpeechEnabled
        speechInterruptionMonitor.start(
            delay: requireWakeWord ? 0.25 : 0.8,
            localeID: speechLocaleID,
            lastSpokenText: response,
            wakeWords: wakeWords,
            requireWakeWord: requireWakeWord
        ) { [weak self] in
            self?.interruptActiveSpeech()
        }
    }

    private func interruptActiveSpeech() {
        guard isEnabled, status == .speaking else {
            return
        }
        flowGeneration += 1
        playback.stop()
        sentenceSpeechStreamer.stop()
        stopLocalSpeech()
        speechInterruptionMonitor.stop()
        beginCommandFlow(source: .followUp)
    }

    private var wakeWords: [String] {
        wakeWordsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var speechContextualStrings: [String] {
        var seen = Set<String>()
        let terms = wakeWords + [
            "Jarvis",
            "OpenClaw",
            "Home Assistant",
            resolvedAgentID,
            "líder supremo"
        ]
        return terms
            .flatMap { [$0, $0.lowercased(), $0.capitalized] }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    var resolvedAgentID: String {
        let trimmed = agentID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "openclaw/", with: "")
        return trimmed.isEmpty ? Self.defaultAgentID : trimmed
    }

    var agentPickerOptions: [String] {
        var seen = Set<String>()
        return ([Self.defaultAgentID] + availableAgentIDs + [resolvedAgentID]).filter { option in
            let trimmed = option.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en-US"))
                .lowercased()
            return !trimmed.isEmpty && seen.insert(key).inserted
        }
    }

    var screenCaptureOptions: ScreenCaptureOptions {
        ScreenCaptureOptions(
            displayIndex: screenDisplayIndex,
            maxWidth: Int(screenMaxWidth),
            showsCursor: screenIncludeCursor
        )
    }

    var microphonePickerOptions: [AudioInputDevice] {
        var options = availableMicrophones
        if !selectedMicrophoneUID.isEmpty, !options.contains(where: { $0.id == selectedMicrophoneUID }) {
            options.append(AudioInputDevice(id: selectedMicrophoneUID, name: "Microfone salvo indisponivel", isDefault: false))
        }
        return options
    }

    var voiceHotKeyDisplayName: String {
        hotKeyCaptureTarget == .voice ? "Pressione as teclas..." : voiceHotKey.displayName
    }

    var textHotKeyDisplayName: String {
        hotKeyCaptureTarget == .text ? "Pressione as teclas..." : textHotKey.displayName
    }

    private func fail(_ message: String) {
        lastError = message
        chimePlayer.play(.error)
        status = .error(message)
        isEnabled = false
        flowGeneration += 1
        stopWakeWordServices()
        recorder.stop()
        nativeSpeechRecognizer.stop()
        speechAnalyzerRecognizer.stop()
        playback.stop()
        sentenceSpeechStreamer.stop()
        stopLocalSpeech()
        speechInterruptionMonitor.stop()
        pushToTalkService.stop()
        audioDeviceObserver.stop()
        textCommandOverlay.hide()
        overlay.update(status: status, transcript: message, level: 0)
        overlay.hide(after: 2.0)
    }

    private func appendHistory(source: String, transcript: String, response: String) {
        let record = InteractionRecord(source: source, transcript: transcript, response: response)
        recentInteractions.insert(record, at: 0)
        if recentInteractions.count > 8 {
            recentInteractions = Array(recentInteractions.prefix(8))
        }
        persistHistory()
    }

    private func persistHistory() {
        guard let data = try? JSONEncoder().encode(recentInteractions) else {
            return
        }
        UserDefaults.standard.set(data, forKey: "recentInteractions")
    }

    private static func saveHotKey(_ hotKey: HotKey, key: String) {
        guard let data = try? JSONEncoder().encode(hotKey) else {
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func loadHotKey(key: String, fallback: HotKey) -> HotKey {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let hotKey = try? JSONDecoder().decode(HotKey.self, from: data)
        else {
            return fallback
        }
        return hotKey
    }

    private static func loadHistory() -> [InteractionRecord] {
        guard
            let data = UserDefaults.standard.data(forKey: "recentInteractions"),
            let records = try? JSONDecoder().decode([InteractionRecord].self, from: data)
        else {
            return []
        }
        return records
    }
}

private enum CommandSource {
    case wakeWord
    case wakeWordInline
    case followUp
    case pushToTalk
    case voiceHotKey
    case textHotKey
    case testButton

    var title: String {
        switch self {
        case .wakeWord:
            return "Wake word"
        case .wakeWordInline:
            return "Wake word com comando"
        case .followUp:
            return "Conversa continua"
        case .pushToTalk:
            return "Atalho Option direito"
        case .voiceHotKey:
            return "Atalho de voz"
        case .textHotKey:
            return "Atalho de texto"
        case .testButton:
            return "Botao Testar"
        }
    }
}

private enum LocalControlSurface {
    case voiceOverlay
    case textOverlay
}
