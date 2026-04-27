import Foundation

enum AssistantStatus: Equatable {
    case stopped
    case requestingPermission
    case listening
    case wakeDetected
    case recording
    case processing
    case speaking
    case awaitingFollowUp
    case error(String)

    var title: String {
        switch self {
        case .stopped:
            return "Pausado"
        case .requestingPermission:
            return "Pedindo permissao"
        case .listening:
            return "Ouvindo Jarvis"
        case .wakeDetected:
            return "Jarvis detectado"
        case .recording:
            return "Gravando"
        case .processing:
            return "Processando"
        case .speaking:
            return "Falando"
        case .awaitingFollowUp:
            return "Aguardando resposta"
        case .error:
            return "Erro"
        }
    }

    var detail: String {
        switch self {
        case .stopped:
            return "Escuta desativada"
        case .requestingPermission:
            return "Autorize microfone e reconhecimento de fala"
        case .listening:
            return "Diga Jarvis para iniciar"
        case .wakeDetected:
            return "Pode falar"
        case .recording:
            return "Ouvindo seu comando"
        case .processing:
            return "Enviando para o OpenClaw"
        case .speaking:
            return "Reproduzindo resposta"
        case .awaitingFollowUp:
            return "Pode confirmar sem dizer Jarvis"
        case .error(let message):
            return message
        }
    }

    var systemImage: String {
        switch self {
        case .stopped:
            return "brain.head.profile"
        case .requestingPermission:
            return "lock.shield"
        case .listening:
            return "brain.head.profile"
        case .wakeDetected:
            return "dot.radiowaves.left.and.right"
        case .recording:
            return "waveform.circle.fill"
        case .processing:
            return "cpu"
        case .speaking:
            return "message.and.waveform"
        case .awaitingFollowUp:
            return "bubble.left.and.bubble.right"
        case .error:
            return "exclamationmark.triangle"
        }
    }
}
