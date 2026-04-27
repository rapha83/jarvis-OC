import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: JarvisAppModel
    @State private var selection: SettingsPane = .connection

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Assistente") {
                    sidebarRow(.connection)
                    sidebarRow(.voice)
                    sidebarRow(.hotkeys)
                }

                Section("Contexto") {
                    sidebarRow(.screen)
                }

                Section("Mac") {
                    sidebarRow(.system)
                    sidebarRow(.diagnostics)
                    sidebarRow(.events)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            VStack(spacing: 0) {
                SettingsHeader(pane: selection)
                Divider()
                detailContent
            }
            .frame(minWidth: 580, idealWidth: 620, minHeight: 560)
        }
        .frame(width: 840, height: 620)
        .background(
            SettingsWindowAccessor { window in
                SettingsWindowFocusService.configure(window)
            }
        )
    }

    private func sidebarRow(_ pane: SettingsPane) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(pane.title)
                    .lineLimit(1)
                Text(pane.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: pane.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
        }
        .tag(pane)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        case .connection:
            connectionPane
        case .voice:
            voicePane
        case .hotkeys:
            hotkeysPane
        case .screen:
            screenPane
        case .system:
            systemPane
        case .diagnostics:
            diagnosticsPane
        case .events:
            eventsPane
        }
    }

    private var connectionPane: some View {
        Form {
            Section("OpenClaw") {
                LabeledContent("Gateway nativo") {
                    TextField("http://127.0.0.1:18789", text: $model.nativeOpenClawURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 320)
                }

                LabeledContent("Agente") {
                    Picker("", selection: $model.agentID) {
                        ForEach(model.agentPickerOptions, id: \.self) { agent in
                            Text(agent).tag(agent)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 320)
                }

                LabeledContent("ID personalizado") {
                    HStack {
                        TextField(JarvisAppModel.defaultAgentID, text: $model.agentID)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 260)

                        Button {
                            model.resetAgentToDefault()
                        } label: {
                            Label("Padrao", systemImage: "arrow.uturn.backward")
                        }
                        .labelStyle(.iconOnly)
                        .help("Voltar para \(JarvisAppModel.defaultAgentID)")

                        Button {
                            model.refreshAgentOptions()
                        } label: {
                            Label("Atualizar agentes", systemImage: "arrow.clockwise")
                        }
                        .labelStyle(.iconOnly)
                        .help("Recarregar agentes do OpenClaw")
                    }
                }
            }
        }
        .settingsFormStyle()
    }

    private var voicePane: some View {
        Form {
            Section("Escuta") {
                LabeledContent("Wake words") {
                    TextField("Jarvis", text: $model.wakeWordsText)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 320)
                }

                Picker("Motor wake word", selection: $model.localWakeWordEngine) {
                    ForEach(LocalWakeWordEngine.allCases) { engine in
                        Text(engine.title).tag(engine)
                    }
                }

                LabeledContent("Status da escuta") {
                    Text(model.wakeWordRuntimeStatus)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if model.localWakeWordEngine == .coreMLKeywordSpotter {
                    Button {
                        model.openWakeWordModelFolder()
                    } label: {
                        Label("Abrir pasta do modelo JarvisWakeWord", systemImage: "folder")
                    }
                }

                Picker("Idioma", selection: $model.speechLocaleID) {
                    ForEach(JarvisAppModel.supportedSpeechLocales, id: \.self) { locale in
                        Text(locale).tag(locale)
                    }
                }

                LabeledContent("Microfone") {
                    HStack {
                        Picker("", selection: $model.selectedMicrophoneUID) {
                            Text("Padrao do sistema").tag("")
                            ForEach(model.microphonePickerOptions) { device in
                                Text(device.title).tag(device.id)
                            }
                        }
                        .labelsHidden()
                        .frame(minWidth: 320)

                        Button {
                            model.refreshAudioInputs()
                        } label: {
                            Label("Atualizar microfones", systemImage: "arrow.clockwise")
                        }
                        .labelStyle(.iconOnly)
                    }
                }

                LabeledContent("Entrada atual") {
                    Text(model.micDescription)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Section("Resposta") {
                Picker("Motor STT", selection: $model.localSTTEngine) {
                    ForEach(LocalSTTEngine.allCases) { engine in
                        Text(engine.title).tag(engine)
                    }
                }

                if model.localSTTEngine == .speechAnalyzer || model.localWakeWordEngine == .speechAnalyzer {
                    LabeledContent("SpeechAnalyzer") {
                        Text(model.speechAnalyzerStatus)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    LabeledContent("Assets") {
                        Text(model.speechAnalyzerAssetStatus)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }

                    HStack {
                        Button {
                            model.refreshSpeechAnalyzerAssets()
                        } label: {
                            Label("Verificar assets", systemImage: "arrow.clockwise")
                        }

                        Button {
                            model.installSpeechAnalyzerAssets()
                        } label: {
                            Label(model.isInstallingSpeechAnalyzerAssets ? "Instalando..." : "Baixar assets", systemImage: "icloud.and.arrow.down")
                        }
                        .disabled(model.isInstallingSpeechAnalyzerAssets)
                    }
                }

                Picker("Motor TTS", selection: $model.localTTSEngine) {
                    ForEach(LocalTTSEngine.allCases) { engine in
                        Text(engine.title).tag(engine)
                    }
                }

                if model.localTTSEngine == .ttsKitNeural {
                    Picker("Voz neural", selection: $model.neuralTTSVoiceID) {
                        ForEach(JarvisAppModel.neuralTTSVoiceOptions) { voice in
                            Text(voice.title).tag(voice.id)
                        }
                    }

                    LabeledContent("Perfil") {
                        Text(JarvisAppModel.neuralTTSVoiceOptions.first { $0.id == model.neuralTTSVoiceID }?.detail ?? "-")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        model.openTTSKitModelFolder()
                    } label: {
                        Label("Abrir pasta de modelos TTSKit", systemImage: "folder")
                    }
                }

                if model.localTTSEngine == .azureNeural {
                    LabeledContent("Regiao/endpoint") {
                        TextField("brazilsouth", text: $model.azureSpeechRegion)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 320)
                    }

                    LabeledContent("Chave F0") {
                        SecureField("Azure Speech key", text: $model.azureSpeechKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 320)
                    }

                    Picker("Voz Azure", selection: $model.azureSpeechVoiceID) {
                        ForEach(JarvisAppModel.azureSpeechVoiceOptions) { voice in
                            Text(voice.title).tag(voice.id)
                        }
                    }

                    LabeledContent("Perfil") {
                        Text(JarvisAppModel.azureSpeechVoiceOptions.first { $0.id == model.azureSpeechVoiceID }?.detail ?? model.azureSpeechVoiceID)
                            .foregroundStyle(.secondary)
                    }

                    Text("Use um recurso Azure AI Speech no tier Free F0. O app nao consegue validar o tier da conta; se a cota acabar, o Azure pode retornar erro e o Jarvis cai para Apple Neural/Enhanced.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if model.localTTSEngine == .customCommand {
                    LabeledContent("Comando") {
                        TextField("/usr/local/bin/meu-tts --text {{text}} --out {{output}}", text: $model.customTTSCommand)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 320)
                    }

                    LabeledContent("Timeout") {
                        Stepper(
                            "\(Int(model.customTTSTimeoutSeconds)) s",
                            value: $model.customTTSTimeoutSeconds,
                            in: 5...180,
                            step: 5
                        )
                    }

                    Text("Placeholders: {{text}}, {{output}}, {{outputDir}} e {{outputBase}}. O comando deve gerar um arquivo de audio no caminho {{output}}.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if model.localSTTEngine == .whisperCoreML {
                    Button {
                        model.openWhisperModelFolder()
                    } label: {
                        Label("Abrir pasta de modelos Whisper/Core ML", systemImage: "folder")
                    }
                }
                Toggle("STT local/offline obrigatorio", isOn: $model.strictLocalSTTEnabled)
                Toggle("Responder por voz", isOn: $model.voiceResponsesEnabled)
                Toggle("Interromper fala ao falar por cima", isOn: $model.interruptSpeechEnabled)
            }

            Section("Teste de voz") {
                LabeledContent("Status") {
                    Text(model.voiceTestStatus)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                ProgressView(value: Double(min(max(model.voiceTestLevel, 0), 1)))

                if !model.voiceTestOriginalTranscript.isEmpty,
                   model.voiceTestOriginalTranscript != model.voiceTestTranscript {
                    LabeledContent("Original") {
                        Text(model.voiceTestOriginalTranscript)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                LabeledContent("Transcricao") {
                    Text(model.voiceTestTranscript.isEmpty ? "-" : model.voiceTestTranscript)
                        .foregroundStyle(model.voiceTestTranscript.isEmpty ? .secondary : .primary)
                        .lineLimit(3)
                }

                if !model.voiceTestCorrections.isEmpty {
                    LabeledContent("Normalizacao") {
                        Text(model.voiceTestCorrections.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Button {
                    model.runVoiceCalibration()
                } label: {
                    Label("Testar microfone e STT", systemImage: "waveform.and.magnifyingglass")
                }
            }
        }
        .settingsFormStyle()
    }

    private var hotkeysPane: some View {
        Form {
            Section("Ativacao por voz") {
                Toggle("Ativar atalho de voz", isOn: $model.voiceHotKeyEnabled)

                LabeledContent("Combinacao") {
                    HStack {
                        Button {
                            model.beginHotKeyCapture(.voice)
                        } label: {
                            Text(model.voiceHotKeyDisplayName)
                                .frame(minWidth: 132)
                        }
                        .disabled(!model.voiceHotKeyEnabled)

                        Button {
                            model.resetVoiceHotKey()
                        } label: {
                            Label("Padrao", systemImage: "arrow.uturn.backward")
                        }
                        .labelStyle(.iconOnly)
                        .disabled(!model.voiceHotKeyEnabled)
                    }
                }

                Toggle("Control direito", isOn: $model.pushToTalkEnabled)
            }

            Section("Comando por texto") {
                Toggle("Ativar caixa de texto por atalho", isOn: $model.textHotKeyEnabled)

                Picker("Resposta", selection: $model.textOverlayResponseMode) {
                    ForEach(TextOverlayResponseMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!model.textHotKeyEnabled)

                LabeledContent("Combinacao") {
                    HStack {
                        Button {
                            model.beginHotKeyCapture(.text)
                        } label: {
                            Text(model.textHotKeyDisplayName)
                                .frame(minWidth: 132)
                        }
                        .disabled(!model.textHotKeyEnabled)

                        Button {
                            model.resetTextHotKey()
                        } label: {
                            Label("Padrao", systemImage: "arrow.uturn.backward")
                        }
                        .labelStyle(.iconOnly)
                        .disabled(!model.textHotKeyEnabled)
                    }
                }
            }
        }
        .settingsFormStyle()
    }

    private var screenPane: some View {
        Form {
            Section("Captura e OCR") {
                Toggle("Usar contexto da tela", isOn: $model.screenContextEnabled)

                Picker("Modo", selection: $model.screenContextMode) {
                    ForEach(ScreenContextMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!model.screenContextEnabled)

                LabeledContent("Descricao") {
                    Text(model.screenContextMode.detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Toggle("Ler texto com OCR local", isOn: $model.screenOCREnabled)
                    .disabled(!model.screenContextEnabled)

                Picker("Tela", selection: $model.screenDisplayIndex) {
                    if model.availableDisplays.isEmpty {
                        Text("Tela principal").tag(0)
                    } else {
                        ForEach(model.availableDisplays) { display in
                            Text("\(display.title) - \(display.size)").tag(display.id)
                        }
                    }
                }
                .disabled(!model.screenContextEnabled)

                LabeledContent("Largura maxima") {
                    Stepper(
                        "\(Int(model.screenMaxWidth)) px",
                        value: $model.screenMaxWidth,
                        in: 800...2400,
                        step: 100
                    )
                    .disabled(!model.screenContextEnabled)
                }

                Toggle("Incluir cursor na captura", isOn: $model.screenIncludeCursor)
                    .disabled(!model.screenContextEnabled)

                LabeledContent("Status") {
                    Text(model.screenContextStatus)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Section("Permissao") {
                HStack {
                    Button {
                        model.requestScreenRecordingPermission()
                    } label: {
                        Label("Solicitar permissao", systemImage: "rectangle.on.rectangle")
                    }

                    Button {
                        model.openScreenRecordingSettings()
                    } label: {
                        Label("Abrir Gravacao de Tela", systemImage: "gear")
                    }

                    Button {
                        model.refreshDisplays()
                    } label: {
                        Label("Atualizar telas", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .settingsFormStyle()
    }

    private var systemPane: some View {
        Form {
            Section("Inicializacao") {
                Toggle("Abrir ao iniciar sessao", isOn: $model.launchAtLoginEnabled)

                Button {
                    SystemSettingsOpener.openLoginItems()
                } label: {
                    Label("Abrir Itens de Inicio", systemImage: "gear")
                }
            }

            Section("Permissoes") {
                LabeledContent("Resumo") {
                    Text(model.permissionSnapshot.summary)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack {
                    Button {
                        model.openMicrophoneSettings()
                    } label: {
                        Label("Microfone", systemImage: "mic")
                    }

                    Button {
                        model.openSpeechRecognitionSettings()
                    } label: {
                        Label("Reconhecimento de Fala", systemImage: "waveform.and.magnifyingglass")
                    }

                    Button {
                        model.refreshPermissions()
                    } label: {
                        Label("Atualizar", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .settingsFormStyle()
    }

    private var diagnosticsPane: some View {
        Form {
            Section("Status") {
                LabeledContent("Runtime") {
                    Text(model.backendStatus)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                LabeledContent("Portas") {
                    Text(model.portDiagnosticsStatus)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                LabeledContent("OpenClaw") {
                    Text(model.openClawConfigStatus)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                LabeledContent("Runtime nativo") {
                    Text(model.nativeRuntimeStatus)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Section("Privacidade") {
                Toggle("Logging detalhado", isOn: $model.detailedLoggingEnabled)

                Text("Quando ativado, logs e diagnosticos podem incluir comandos de voz, respostas do agente, eventos, nomes de apps/janelas e trechos de OCR. Desative antes de compartilhar logs publicamente; os eventos continuam existindo, mas campos sensiveis sao mascarados.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Acoes") {
                HStack {
                    Button {
                        model.refreshHealth()
                        model.refreshPortDiagnostics()
                    } label: {
                        Label("Atualizar", systemImage: "arrow.clockwise")
                    }

                    Button {
                        model.copyDiagnosticsReport()
                    } label: {
                        Label("Copiar diagnostico", systemImage: "doc.on.clipboard")
                    }

                    Button {
                        model.exportDiagnosticsBundle()
                    } label: {
                        Label("Exportar logs", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        model.openDiagnosticsLog()
                    } label: {
                        Label("Abrir logs", systemImage: "doc.text.magnifyingglass")
                    }

                    Button {
                        model.openAgentEventsWindow()
                    } label: {
                        Label("Eventos", systemImage: "list.bullet.rectangle")
                    }
                }
            }
        }
        .settingsFormStyle()
    }

    private var eventsPane: some View {
        Form {
            Section("Eventos do agente") {
                HStack {
                    Button {
                        model.openAgentEventsWindow()
                    } label: {
                        Label("Abrir janela de eventos", systemImage: "macwindow.badge.plus")
                    }

                    Button {
                        model.clearAgentEvents()
                    } label: {
                        Label("Limpar", systemImage: "trash")
                    }
                    .disabled(model.agentEvents.isEmpty)
                }

                if model.agentEvents.isEmpty {
                    Text("Sem eventos recentes.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.agentEvents.prefix(8)) { event in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label(event.title, systemImage: event.severity.systemImage)
                                    .foregroundStyle(event.severity.color)
                                Spacer()
                                Text(event.date.formatted(date: .omitted, time: .standard))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(event.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(event.agentID)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section("Fallback de TTS") {
                if model.ttsAttempts.isEmpty {
                    Text("Sem tentativas de TTS nesta sessao.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.ttsAttempts.prefix(10)) { attempt in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(attempt.provider)
                                    .font(.callout.weight(.medium))
                                Spacer()
                                Text("\(attempt.durationMs) ms")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(attempt.voice) - \(attempt.characterCount) caracteres - \(attempt.result)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let fallback = attempt.fallbackReason, !fallback.isEmpty {
                                Text(fallback)
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .settingsFormStyle()
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case connection
    case voice
    case hotkeys
    case screen
    case system
    case diagnostics
    case events

    var id: String { rawValue }

    var title: String {
        switch self {
        case .connection:
            return "Conexao"
        case .voice:
            return "Voz"
        case .hotkeys:
            return "Atalhos"
        case .screen:
            return "Tela e OCR"
        case .system:
            return "Sistema"
        case .diagnostics:
            return "Diagnostico"
        case .events:
            return "Eventos"
        }
    }

    var subtitle: String {
        switch self {
        case .connection:
            return "Gateway e agente"
        case .voice:
            return "Escuta, audio e teste"
        case .hotkeys:
            return "Teclas e overlay"
        case .screen:
            return "Contexto visual"
        case .system:
            return "macOS e permissoes"
        case .diagnostics:
            return "Logs e saude"
        case .events:
            return "Agente e TTS"
        }
    }

    var systemImage: String {
        switch self {
        case .connection:
            return "network"
        case .voice:
            return "waveform.circle"
        case .hotkeys:
            return "keyboard"
        case .screen:
            return "text.viewfinder"
        case .system:
            return "macwindow"
        case .diagnostics:
            return "stethoscope"
        case .events:
            return "list.bullet.rectangle"
        }
    }
}

private extension AgentEventRecord.Severity {
    var systemImage: String {
        switch self {
        case .info:
            return "info.circle"
        case .success:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.octagon"
        }
    }

    var color: Color {
        switch self {
        case .info:
            return .secondary
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

private struct SettingsHeader: View {
    let pane: SettingsPane

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: pane.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.red)
                .frame(width: 34, height: 34)
                .background(.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(pane.title)
                    .font(.title3.weight(.semibold))
                Text(pane.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.bar)
    }
}

private extension View {
    func settingsFormStyle() -> some View {
        self
            .formStyle(.grouped)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
    }
}
