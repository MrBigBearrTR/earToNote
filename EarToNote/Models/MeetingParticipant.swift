import Foundation
import MeetingCore
import SwiftData

/// One voice found by diarization in one meeting, linked to the saved person it belongs to.
///
/// Transcript segments point at the participant and the participant points at a `SpeakerProfile`,
/// so renaming a profile renames that person in every meeting at once.
@Model
final class MeetingParticipant {
    @Attribute(.unique) var id: UUID
    /// Label assigned by the diarizer (e.g. "S1"); only unique inside this meeting.
    var diarizationKey: String
    var speechDuration: Double
    var firstAppearance: Double
    /// L2-normalized voice embedding of this speaker in this meeting.
    var embeddingData: Data?
    /// How much this participant currently adds to its profile's voiceprint (0 = nothing).
    var contributedWeight: Double
    /// Similarity to the profile when it was matched automatically; `nil` when a new profile was created.
    var matchSimilarity: Double?

    var meeting: Meeting?
    var speaker: SpeakerProfile?

    @Relationship(deleteRule: .nullify, inverse: \TranscriptSegment.participant)
    var segments: [TranscriptSegment] = []

    init(diarizationKey: String, speechDuration: Double, firstAppearance: Double, embedding: [Float]?) {
        self.id = UUID()
        self.diarizationKey = diarizationKey
        self.speechDuration = speechDuration
        self.firstAppearance = firstAppearance
        if let embedding, !embedding.isEmpty {
            self.embeddingData = EmbeddingMath.encode(EmbeddingMath.normalized(embedding))
        } else {
            self.embeddingData = nil
        }
        self.contributedWeight = 0
        self.matchSimilarity = nil
    }

    var embedding: [Float]? {
        embeddingData.map(EmbeddingMath.decode)
    }

    var displayName: String {
        speaker?.name ?? "Bilinmeyen konuşmacı"
    }
}
