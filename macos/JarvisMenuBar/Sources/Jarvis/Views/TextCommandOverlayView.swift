import SwiftUI

struct TextCommandOverlayView: View {
    @ObservedObject var state: TextCommandOverlayState
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: state.phase == .input ? 0 : 10) {
            HStack(spacing: 14) {
                eye

                if state.phase == .input {
                    TextField("Digite um comando para o JARVIS", text: $state.text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18, weight: .medium))
                        .focused($isFocused)
                        .onSubmit {
                            onSubmit(state.text)
                        }

                    Button {
                        onSubmit(state.text)
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 30, height: 30)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.white)
                    .background(.red.opacity(0.85), in: Circle())
                    .help("Enviar")
                } else {
                    Text(state.command)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)

                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 24, height: 24)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .background(.quaternary.opacity(0.55), in: Circle())
                    .help("Fechar")
                }
            }

            if state.phase != .input {
                Text(responseText)
                    .font(.system(size: 15, weight: state.phase == .processing ? .regular : .medium))
                    .foregroundStyle(responseColor)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 56)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(minWidth: 420, maxWidth: .infinity, minHeight: 86, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(borderColor.opacity(0.34), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 28, x: 0, y: 18)
        .animation(.snappy(duration: 0.16), value: state.phase)
        .animation(.snappy(duration: 0.16), value: state.response)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFocused = true
            }
        }
        .onExitCommand {
            onCancel()
        }
    }

    private var eye: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.14))
                .frame(width: 42, height: 42)
                .background(.thinMaterial, in: Circle())
            Image(nsImage: JarvisDragonEyeImage.orbImage())
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 31, height: 31)
                .clipShape(Circle())
        }
    }

    private var responseText: String {
        let trimmed = state.response.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Processando..." : trimmed
    }

    private var responseColor: Color {
        switch state.phase {
        case .processing:
            return .secondary
        case .error:
            return .red
        default:
            return .primary
        }
    }

    private var borderColor: Color {
        state.phase == .error ? .red : .red
    }
}
