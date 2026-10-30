import AVFoundation
import Foundation
import Observation

enum RecorderError: LocalizedError {
    case permissionDenied
    case couldNotStart

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Mikrofon izni verilmedi. Ayarlar > EarToNote bölümünden mikrofon iznini açabilirsiniz."
        case .couldNotStart:
            "Ses kaydı başlatılamadı. Başka bir uygulama mikrofonu kullanıyor olabilir."
        }
    }
}

/// Records the meeting to an AAC (.m4a) file. Recording keeps running with the screen locked because
/// the app declares the `audio` background mode.
@MainActor
@Observable
final class AudioRecorder {
    static let meterSampleCount = 48

    private(set) var isRecording = false
    private(set) var isPaused = false
    /// The system paused the recording (phone call, Siri, another app took the microphone).
    private(set) var wasInterrupted = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var levels: [Float] = Array(repeating: 0, count: AudioRecorder.meterSampleCount)

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meterTask: Task<Void, Never>?
    @ObservationIgnored private var interruptionTask: Task<Void, Never>?

    static func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        @unknown default:
            return false
        }
    }

    func start(recordingTo url: URL) throws {
        guard !isRecording else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record() else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw RecorderError.couldNotStart
        }

        self.recorder = recorder
        isRecording = true
        isPaused = false
        wasInterrupted = false
        elapsed = 0
        startMetering()
        observeInterruptions()
    }

    func pause() {
        guard isRecording, !isPaused else { return }
        recorder?.pause()
        isPaused = true
    }

    func resume() {
        guard isRecording, isPaused, let recorder else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        if recorder.record() {
            isPaused = false
            wasInterrupted = false
        }
    }

    /// Finishes the file and returns the recorded duration in seconds.
    @discardableResult
    func stop() -> TimeInterval {
        if let recorder, recorder.isRecording {
            elapsed = max(elapsed, recorder.currentTime)
        }
        recorder?.stop()
        tearDown()
        return elapsed
    }

    /// Stops and deletes the file.
    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        tearDown()
    }

    private func tearDown() {
        meterTask?.cancel()
        interruptionTask?.cancel()
        meterTask = nil
        interruptionTask = nil
        recorder = nil
        isRecording = false
        isPaused = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startMetering() {
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.sampleMeter()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func sampleMeter() {
        guard let recorder, isRecording else { return }
        if recorder.isRecording {
            elapsed = recorder.currentTime
        }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        // Map roughly -50 dB (silence) ... 0 dB (loud) to 0 ... 1.
        let level = isPaused ? 0 : max(0, min(1, (power + 50) / 50))
        levels.removeFirst()
        levels.append(level)
    }

    private func observeInterruptions() {
        interruptionTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification)
            for await notification in notifications {
                self?.handleInterruption(userInfo: notification.userInfo)
            }
        }
    }

    private func handleInterruption(userInfo: [AnyHashable: Any]?) {
        guard let userInfo,
              let rawType = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType)
        else { return }

        switch type {
        case .began:
            guard isRecording else { return }
            isPaused = true
            wasInterrupted = true
        case .ended:
            let rawOptions = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if wasInterrupted, AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume) {
                resume()
            }
        @unknown default:
            break
        }
    }
}
