import Foundation
import MeetingCore
import SwiftData

/// A person remembered across meetings. Until the user names them they are "Konuşmacı N", where N is
/// a global number, so the same voice keeps the same label in every meeting.
@Model
final class SpeakerProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var number: Int
    var isNamedByUser: Bool
    /// Weighted mean of the participant embeddings attributed to this person (the voiceprint).
    var embeddingData: Data?
    var embeddingWeight: Double
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \MeetingParticipant.speaker)
    var participants: [MeetingParticipant] = []

    init(number: Int) {
        self.id = UUID()
        self.name = SpeakerNaming.defaultName(number: number)
        self.number = number
        self.isNamedByUser = false
        self.embeddingData = nil
        self.embeddingWeight = 0
        self.createdAt = .now
    }

    var hasVoiceprint: Bool {
        embeddingData != nil && embeddingWeight > 0
    }

    var voiceprint: EmbeddingMath.WeightedCentroid {
        get {
            EmbeddingMath.WeightedCentroid(vector: embeddingData.map(EmbeddingMath.decode), weight: embeddingWeight)
        }
        set {
            embeddingData = newValue.vector.map(EmbeddingMath.encode)
            embeddingWeight = newValue.weight
        }
    }

    var meetingCount: Int {
        Set(participants.compactMap { $0.meeting?.id }).count
    }
}
