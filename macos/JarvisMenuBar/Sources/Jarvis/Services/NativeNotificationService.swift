import Foundation
import UserNotifications

final class NativeNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NativeNotificationService()

    private let center = UNUserNotificationCenter.current()
    private var delegateInstalled = false

    private override init() {
        super.init()
    }

    func notify(title: String, body: String) {
        Task {
            guard await self.ensureAuthorization() else {
                return
            }
            self.installDelegateIfNeeded()

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = Self.truncate(body)
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "jarvis-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await self.add(request)
        }
    }

    private func installDelegateIfNeeded() {
        guard !delegateInstalled else {
            return
        }
        center.delegate = self
        delegateInstalled = true
    }

    private func ensureAuthorization() async -> Bool {
        let settings = await notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await requestAuthorization()) ?? false
        @unknown default:
            return false
        }
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private func requestAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    private static func truncate(_ text: String) -> String {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard trimmed.count > 220 else {
            return trimmed
        }
        return "\(trimmed.prefix(217))..."
    }
}
