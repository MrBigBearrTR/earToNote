import FluidAudio
import Foundation
import MeetingCore

struct DiarizationOutput: Sendable {
    var turns: [SpeakerTurn]
    /// One voice embedding per diarized speaker, keyed like `SpeakerTurn.speakerKey`.
    var embeddings: [String: [Float]]
}

/// "Who spoke when", computed on device with FluidAudio's offline pyannote pipeline
/// (segmentation + WeSpeaker embeddings + VBx clustering on Core ML).
actor DiarizationService {
    static let shared = DiarizationService()

    private static let modelsReadyKey = "diarizationModelsReady"

    private var manager: OfflineDiarizerManager?

    /// The Core ML models are downloaded on first use and then cached on the device.
    nonisolated static var modelsWereDownloaded: Bool {
        UserDefaults.standard.bool(forKey: modelsReadyKey)
    }

    func prepare() async throws {
        _ = try await readyManager()
    }

    func diarize(fileURL: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> DiarizationOutput {
        let manager = try await readyManager()
        let result = try await manager.process(fileURL) { processed, total in
            guard total > 0 else { return }
            progress(Double(processed) / Double(total))
        }
        let turns = result.segments.map { segment in
            SpeakerTurn(
                speakerKey: segment.speakerId,
                start: Double(segment.startTimeSeconds),
                end: Double(segment.endTimeSeconds)
            )
        }
        return DiarizationOutput(turns: turns, embeddings: result.speakerDatabase ?? [:])
    }

    private func readyManager() async throws -> OfflineDiarizerManager {
        if let manager {
            return manager
        }
        var config = OfflineDiarizerConfig.default
        // Each 10 s window in a batch costs ~13 MB at peak; keep iPhone memory use low.
        config.segmentation.batchSize = 8
        let manager = OfflineDiarizerManager(config: config)
        try await manager.prepareModels()
        self.manager = manager
        UserDefaults.standard.set(true, forKey: Self.modelsReadyKey)
        return manager
    }
}
