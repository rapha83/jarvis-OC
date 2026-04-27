import SwiftUI

struct VoiceOverlayView: View {
    @ObservedObject var state: VoiceOverlayState
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            EyeCore(status: state.status, color: statusColor)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    StatusChip(status: state.status, color: statusColor)

                    Text(state.detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 22, height: 22)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .background(.quaternary.opacity(0.55), in: Circle())
                    .help("Cancelar")
                }

                Text(displayTranscript)
                    .font(.system(size: 15, weight: state.transcript.isEmpty ? .regular : .medium))
                    .foregroundStyle(state.transcript.isEmpty ? .tertiary : .primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)

                AudioSignalView(level: state.level, color: statusColor)
                    .frame(height: 16)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 460, height: 128)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(statusColor.opacity(borderOpacity), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.20), radius: 24, x: 0, y: 14)
    }

    private var displayTranscript: String {
        let trimmed = state.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? placeholder : trimmed
    }

    private var placeholder: String {
        switch state.status {
        case .listening:
            return "Aguardando wake word"
        case .wakeDetected, .recording, .awaitingFollowUp:
            return "Pode falar"
        case .processing:
            return "Sincronizando com OpenClaw"
        case .speaking:
            return "Respondendo"
        case .requestingPermission:
            return "Aguardando permissao"
        case .stopped:
            return "Escuta pausada"
        case .error:
            return "Verifique o diagnostico"
        }
    }

    private var borderOpacity: Double {
        switch state.status {
        case .recording, .wakeDetected, .awaitingFollowUp:
            return 0.56
        case .processing, .speaking:
            return 0.44
        default:
            return 0.28
        }
    }

    private var statusColor: Color {
        switch state.status {
        case .listening, .awaitingFollowUp:
            return .green
        case .wakeDetected, .recording:
            return .orange
        case .processing:
            return .yellow
        case .speaking, .error:
            return .red
        case .requestingPermission:
            return .blue
        case .stopped:
            return .secondary
        }
    }
}

private struct EyeCore: View {
    let status: AssistantStatus
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.14))
                .frame(width: 56, height: 56)
                .background(.thinMaterial, in: Circle())

            Circle()
                .trim(from: 0.08, to: 0.88)
                .stroke(color.opacity(0.72), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-24))
                .frame(width: 62, height: 62)

            Image(nsImage: JarvisDragonEyeImage.orbImage())
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 45, height: 45)
                .clipShape(Circle())
                .opacity(opacity)
        }
        .frame(width: 72, height: 72)
    }

    private var opacity: Double {
        switch status {
        case .stopped:
            return 0.62
        case .requestingPermission:
            return 0.78
        case .error:
            return 0.90
        case .listening, .wakeDetected, .recording, .processing, .speaking, .awaitingFollowUp:
            return 1.0
        }
    }
}

private struct StatusChip: View {
    let status: AssistantStatus
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(status.title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .stroke(color.opacity(0.24), lineWidth: 1)
        }
    }
}

private struct AudioSignalView: View {
    let level: Float
    let color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<24, id: \.self) { index in
                Capsule()
                    .fill(barColor(index: index))
                    .frame(width: 3, height: barHeight(index: index))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.snappy(duration: 0.16), value: level)
    }

    private func barHeight(index: Int) -> CGFloat {
        let normalized = CGFloat(min(max(level, 0), 1))
        let wave = CGFloat((index % 7) + 1) / 7.0
        let idlePattern = CGFloat([2, 5, 8, 4, 10, 6, 3][index % 7])
        let activeHeight = 4 + (normalized * 16 * wave)
        return max(3, normalized > 0.03 ? activeHeight : idlePattern)
    }

    private func barColor(index: Int) -> Color {
        index < 14 ? color.opacity(0.72) : color.opacity(0.28)
    }
}
