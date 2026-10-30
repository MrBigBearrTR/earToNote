import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class AudioPlayer {
    private(set) var isAvailable = false
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    func load(url: URL) {
        stop()
        guard FileManager.default.fileExists(atPath: url.path),
              let player = try? AVAudioPlayer(contentsOf: url)
        else {
            isAvailable = false
            duration = 0
            currentTime = 0
            return
        }
        player.prepareToPlay()
        self.player = player
        duration = player.duration
        currentTime = 0
        isAvailable = true
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play(from time: TimeInterval? = nil) {
        guard let player else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        if let time {
            player.currentTime = clamped(time)
        }
        if player.play() {
            isPlaying = true
            currentTime = player.currentTime
            startTicker()
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        ticker?.cancel()
        ticker = nil
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        player.currentTime = clamped(time)
        currentTime = player.currentTime
    }

    func skip(by delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        ticker?.cancel()
        ticker = nil
    }

    private func clamped(_ time: TimeInterval) -> TimeInterval {
        min(max(0, time), max(0, duration - 0.05))
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    private func tick() {
        guard let player else { return }
        currentTime = player.currentTime
        if isPlaying, !player.isPlaying {
            isPlaying = false
            ticker?.cancel()
            ticker = nil
        }
    }
}
