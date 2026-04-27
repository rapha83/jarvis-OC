import SwiftUI

struct JarvisMenuView: View {
    @ObservedObject var model: JarvisAppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    conversation
                    diagnostics
                    history
                }
                .padding(12)
            }
            .frame(maxHeight: 360)

            Divider()

            footer
        }
        .frame(width: 370)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 12) {
            MonsterEyeIcon(status: model.status, size: 36)
                .frame(width: 38, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text("JARVIS")
                    .font(.system(.title3, design: .rounded, weight: .semibold))

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(model.status.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                model.isEnabled ? model.stop() : model.start()
            } label: {
                Image(systemName: model.isEnabled ? "power.circle.fill" : "power.circle")
                    .font(.system(size: 22, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(model.isEnabled ? Color.accentColor : .secondary)
            .help(model.isEnabled ? "Pausar" : "Ativar")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conversa")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            MessageRow(
                title: "Voce",
                systemImage: "person.wave.2",
                text: model.transcription,
                placeholder: "Sem comando recente"
            )

            MessageRow(
                title: "Jarvis",
                systemImage: "sparkles",
                text: model.response,
                placeholder: model.status.detail
            )
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sistema")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                DiagnosticTile(
                    title: "Microfone",
                    value: model.micDescription,
                    systemImage: "mic",
                    color: micColor
                ) {
                    ProgressView(value: Double(min(max(model.micLevel, 0), 1)))
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }

                DiagnosticTile(
                    title: "Runtime",
                    value: model.backendStatus,
                    systemImage: model.nativeHealthOperational ? "checkmark.circle" : "exclamationmark.triangle",
                    color: model.nativeHealthOperational ? .green : .orange
                )

                DiagnosticTile(
                    title: "Tela",
                    value: model.screenContextStatus,
                    systemImage: model.screenContextEnabled ? "text.viewfinder" : "rectangle.slash",
                    color: screenColor
                )

                DiagnosticTile(
                    title: "Permissoes",
                    value: model.permissionSnapshot.summary,
                    systemImage: "lock.shield",
                    color: permissionsColor
                )

                DiagnosticTile(
                    title: "Entrada",
                    value: model.lastCommandSource.isEmpty ? "Wake word" : model.lastCommandSource,
                    systemImage: "waveform",
                    color: .accentColor
                )

                DiagnosticTile(
                    title: "Voz",
                    value: model.voiceResponsesEnabled ? "Ativa" : "Silenciosa",
                    systemImage: model.voiceResponsesEnabled ? "speaker.wave.2" : "speaker.slash",
                    color: model.voiceResponsesEnabled ? .accentColor : .secondary
                )
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recentes")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !model.recentInteractions.isEmpty {
                    Button {
                        model.clearHistory()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Limpar")
                }
            }

            if model.recentInteractions.isEmpty {
                Text("Sem historico")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(model.recentInteractions.prefix(3)) { record in
                    HistoryRow(record: record)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                model.testCommandRecording()
            } label: {
                Label("Testar", systemImage: "waveform.circle")
            }
            .disabled(!model.isEnabled)
            .keyboardShortcut("t")

            Toggle(isOn: $model.voiceResponsesEnabled) {
                Label("Voz", systemImage: model.voiceResponsesEnabled ? "speaker.wave.2" : "speaker.slash")
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Spacer()

            Button {
                model.refreshHealth()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Atualizar")

            Button {
                model.copyDiagnosticsReport()
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(.borderless)
            .help("Copiar diagnostico")

            Button {
                model.openAgentEventsWindow()
            } label: {
                Image(systemName: "list.bullet.rectangle")
            }
            .buttonStyle(.borderless)
            .help("Eventos")

            Button {
                openSettings()
                SettingsWindowFocusService.focusSoon()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Ajustes")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Sair")
            .keyboardShortcut("q")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var statusColor: Color {
        switch model.status {
        case .listening, .awaitingFollowUp:
            return .green
        case .wakeDetected, .recording:
            return .orange
        case .processing:
            return .yellow
        case .speaking:
            return .red
        case .error:
            return .red
        case .requestingPermission:
            return .blue
        case .stopped:
            return .secondary
        }
    }

    private var micColor: Color {
        model.micLevel > 0.08 ? .green : .secondary
    }

    private var screenColor: Color {
        guard model.screenContextEnabled else {
            return .secondary
        }
        return model.permissionSnapshot.screenRecording ? .accentColor : .orange
    }

    private var permissionsColor: Color {
        let snapshot = model.permissionSnapshot
        return snapshot.microphone && snapshot.speechRecognition && (!model.screenContextEnabled || snapshot.screenRecording)
            ? .green
            : .orange
    }
}

private struct HistoryRow: View {
    let record: InteractionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(record.source)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(record.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(record.transcript)
                .font(.caption)
                .lineLimit(1)

            Text(record.response)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct MessageRow: View {
    let title: String
    let systemImage: String
    let text: String
    let placeholder: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(displayText)
                    .font(.callout)
                    .foregroundStyle(text.isEmpty ? .tertiary : .primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var displayText: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? placeholder : trimmed
    }
}

private struct DiagnosticTile<Accessory: View>: View {
    let title: String
    let value: String
    let systemImage: String
    let color: Color
    @ViewBuilder var accessory: Accessory

    init(
        title: String,
        value: String,
        systemImage: String,
        color: Color,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
        self.color = color
        self.accessory = accessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                    .frame(width: 14)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.primary)
                .frame(minHeight: 28, alignment: .topLeading)

            accessory
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .topLeading)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
