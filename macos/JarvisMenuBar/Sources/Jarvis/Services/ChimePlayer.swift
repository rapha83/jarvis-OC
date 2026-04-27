import AVFoundation
import AppKit
import Foundation

enum JarvisChime {
    case wake
    case listen
    case sent
    case followUp
    case error

    var tones: [(frequency: Double, duration: Double)] {
        switch self {
        case .wake:
            return [(880, 0.07), (1320, 0.09)]
        case .listen:
            return [(1180, 0.08)]
        case .sent:
            return [(660, 0.06), (990, 0.08)]
        case .followUp:
            return [(720, 0.08), (720, 0.08)]
        case .error:
            return [(320, 0.12), (240, 0.16)]
        }
    }
}

@MainActor
final class ChimePlayer {
    private var player: AVAudioPlayer?

    func play(_ chime: JarvisChime) {
        guard let data = Self.makeWav(for: chime) else {
            NSSound.beep()
            return
        }

        do {
            let player = try AVAudioPlayer(data: data)
            self.player = player
            player.volume = 0.45
            player.prepareToPlay()
            player.play()
        } catch {
            NSSound.beep()
        }
    }

    private static func makeWav(for chime: JarvisChime) -> Data? {
        let sampleRate = 44_100
        var pcm = Data()

        for tone in chime.tones {
            let frameCount = Int(tone.duration * Double(sampleRate))
            for frame in 0..<frameCount {
                let t = Double(frame) / Double(sampleRate)
                let envelope = min(1, Double(frame) / 800) * min(1, Double(frameCount - frame) / 1200)
                let value = sin(2 * Double.pi * tone.frequency * t) * 0.35 * envelope
                var sample = Int16(max(-1, min(1, value)) * Double(Int16.max)).littleEndian
                pcm.append(Data(bytes: &sample, count: MemoryLayout<Int16>.size))
            }

            let gapFrames = Int(0.025 * Double(sampleRate))
            for _ in 0..<gapFrames {
                var sample = Int16(0)
                pcm.append(Data(bytes: &sample, count: MemoryLayout<Int16>.size))
            }
        }

        return WavWriter.makeWav(pcm16: pcm, sampleRate: sampleRate)
    }
}
