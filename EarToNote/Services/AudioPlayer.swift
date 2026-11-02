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

    @ObservationIgnored private var url: URL?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    /// Loading the same file again keeps the position, so the view can call this every time it appears.
    func load(url: URL) {
        if self.url == url, player != nil { return }
        stop()
        self.url = url
        guard let player = makePlayer(for: url) else {
            isAvailable = false
            duration = 0
            currentTime = 0
            return
        }
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
        guard let player = readyPlayer() else { return }
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
        guard let player = readyPlayer() else { return }
        player.currentTime = clamped(time)
        currentTime = player.currentTime
    }

    func skip(by delta: TimeInterval) {
        seek(to: currentTime + delta)
    }

    /// Releases the file. A later `play` or `seek` opens it again at the last position.
    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        ticker?.cancel()
        ticker = nil
    }

    private func makePlayer(for url: URL) -> AVAudioPlayer? {
        guard FileManager.default.fileExists(atPath: url.path),
              let player = try? AVAudioPlayer(contentsOf: url)
        else { return nil }
        player.prepareToPlay()
        return player
    }

    private func readyPlayer() -> AVAudioPlayer? {
        if let player { return player }
        guard let url, let player = makePlayer(for: url) else {
            isAvailable = false
            return nil
        }
        player.currentTime = min(currentTime, max(0, player.duration - 0.05))
        self.player = player
        duration = player.duration
        isAvailable = true
        return player
    }

    private func clamped(_ time: TimeInterval) -> TimeInterval {
        min(max(0, time), max(0, duration - 0.05))
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.tick()
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
