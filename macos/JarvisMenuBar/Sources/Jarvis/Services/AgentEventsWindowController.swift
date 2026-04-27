import AppKit
import SwiftUI

@MainActor
final class AgentEventsWindowController {
    static let shared = AgentEventsWindowController()

    private var window: NSWindow?

    func show(model: JarvisAppModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = AgentEventsWindowView(model: model)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Eventos do Agente"
        window.setContentSize(NSSize(width: 760, height: 520))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}

private struct AgentEventsWindowView: View {
    @ObservedObject var model: JarvisAppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Eventos do Agente", systemImage: "list.bullet.rectangle")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button {
                    model.clearAgentEvents()
                } label: {
                    Label("Limpar", systemImage: "trash")
                }
                .disabled(model.agentEvents.isEmpty)
            }
            .padding(18)
            .background(.bar)

            Divider()

            if model.agentEvents.isEmpty {
                ContentUnavailableView(
                    "Sem eventos ainda",
                    systemImage: "waveform.path.ecg",
                    description: Text("Os eventos aparecem quando o Jarvis transcreve, envia ao OpenClaw, recebe resposta ou troca de agente.")
                )
            } else {
                List(model.agentEvents) { event in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(color(for: event.severity))
                                .frame(width: 8, height: 8)
                            Text(event.title)
                                .font(.headline)
                            Spacer()
                            Text(event.date, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(event.detail)
                            .foregroundStyle(.secondary)

                        Text(event.agentID)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
    }

    private func color(for severity: AgentEventRecord.Severity) -> Color {
        switch severity {
        case .info:
            return .blue
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
