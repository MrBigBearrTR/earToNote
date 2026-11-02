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
    private var managerSpeakerCount: Int?

    /// The Core ML models are downloaded on first use and then cached on the device.
    nonisolated static var modelsWereDownloaded: Bool {
        UserDefaults.standard.bool(forKey: modelsReadyKey)
    }

    func prepare() async throws {
        _ = try await readyManager(speakerCount: manager == nil ? nil : managerSpeakerCount)
    }

    /// - Parameter speakerCount: Forces the number of speakers; `nil` lets the clustering decide.
    func diarize(
        fileURL: URL,
        speakerCount: Int? = nil,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> DiarizationOutput {
        let manager = try await readyManager(speakerCount: speakerCount)
        let result: DiarizationResult
        do {
            result = try await manager.process(fileURL) { processed, total in
                guard total > 0 else { return }
                progress(Double(processed) / Double(total))
            }
        } catch OfflineDiarizationError.noSpeechDetected {
            return DiarizationOutput(turns: [], embeddings: [:])
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

    private func readyManager(speakerCount: Int?) async throws -> OfflineDiarizerManager {
        if let manager, managerSpeakerCount == speakerCount {
            return manager
        }
        var config = OfflineDiarizerConfig.default
        // Each 10 s window in a batch costs ~13 MB at peak; keep iPhone memory use low.
        config.segmentation.batchSize = 8
        // Also the shortest turn that is reported. Short replies ("evet", "tamam") are often the only
        // trace of a quiet participant, and the default of 1 s drops them.
        config.embedding.minSegmentDurationSeconds = 0.3
        config.clustering.numSpeakers = speakerCount
        let manager = OfflineDiarizerManager(config: config)
        try await manager.prepareModels()
        self.manager = manager
        managerSpeakerCount = speakerCount
        UserDefaults.standard.set(true, forKey: Self.modelsReadyKey)
        return manager
    }
}
