import AVFoundation
import Foundation

enum PlaybackResult: Equatable {
    case finished
    case stopped
    case failed
}

@MainActor
final class AudioPlaybackService: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var continuation: CheckedContinuation<PlaybackResult, Never>?
    private var watchdogTask: Task<Void, Never>?

    func play(data: Data) async throws -> PlaybackResult {
        guard !data.isEmpty else {
            return .failed
        }

        stop()

        let player = try AVAudioPlayer(data: data)
        self.player = player
        player.delegate = self
        player.prepareToPlay()

        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            guard player.play() else {
                finish(.failed)
                return
            }

            let duration = max(player.duration, 0.1)
            watchdogTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 650_000_000)
                await MainActor.run {
                    guard let self, self.player === player, self.continuation != nil else {
                        return
                    }
                    if !player.isPlaying && player.currentTime <= 0.05 {
                        self.finish(.failed)
                    }
                }

                let timeout = min(duration + 2.0, 300.0)
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                await MainActor.run {
                    guard let self, self.player === player, self.continuation != nil else {
                        return
                    }
                    self.finish(.failed)
                }
            }
        }
    }

    func stop() {
        if let player, player.isPlaying {
            player.stop()
        }
        finish(.stopped)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else {
                return
            }
            self.finish(flag ? .finished : .failed)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            guard self.player === player else {
                return
            }
            self.finish(.failed)
        }
    }

    private func finish(_ result: PlaybackResult) {
        watchdogTask?.cancel()
        watchdogTask = nil
        player?.delegate = nil
        player = nil
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(returning: result)
    }
}
