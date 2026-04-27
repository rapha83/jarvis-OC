import AVFoundation
import CoreGraphics
import Foundation
import Speech

enum PermissionsService {
    static func requestVoicePermissions() async -> Bool {
        let microphoneGranted = await requestMicrophone()
        let speechGranted = await requestSpeechRecognition()
        return microphoneGranted && speechGranted
    }

    static func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            speechRecognition: SFSpeechRecognizer.authorizationStatus() == .authorized,
            screenRecording: isScreenRecordingAuthorized()
        )
    }

    static func isScreenRecordingAuthorized() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @MainActor
    static func requestScreenRecording() async -> Bool {
        if isScreenRecordingAuthorized() {
            return true
        }
        _ = CGRequestScreenCaptureAccess()
        return isScreenRecordingAuthorized()
    }

    private static func requestMicrophone() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func requestSpeechRecognition() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
