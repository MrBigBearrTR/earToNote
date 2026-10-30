import Foundation
import MeetingCore
import SwiftData

/// Operations on saved people that keep voiceprints consistent with who is assigned to which voice.
@MainActor
enum SpeakerDirectory {
    static let voiceprintPolicy = VoiceprintPolicy(minimumSpeech: AppSettings.minimumSpeechForVoiceprint)

    static func allProfiles(in context: ModelContext) -> [SpeakerProfile] {
        (try? context.fetch(FetchDescriptor<SpeakerProfile>())) ?? []
    }

    static func nextNumber(in context: ModelContext) -> Int {
        SpeakerNaming.nextNumber(existing: allProfiles(in: context).map(\.number))
    }

    @discardableResult
    static func makeProfile(number: Int, in context: ModelContext) -> SpeakerProfile {
        let profile = SpeakerProfile(number: number)
        context.insert(profile)
        return profile
    }

    /// Links the participant to `profile` and, if they spoke long enough, teaches the profile their voice.
    static func attach(_ participant: MeetingParticipant, to profile: SpeakerProfile) {
        participant.speaker = profile
        let weight = voiceprintPolicy.weight(forSpeechDuration: participant.speechDuration)
        if weight > 0, let embedding = participant.embedding, !embedding.isEmpty {
            profile.voiceprint = EmbeddingMath.adding(embedding, weight: weight, to: profile.voiceprint)
            participant.contributedWeight = weight
        } else {
            participant.contributedWeight = 0
        }
    }

    /// Unlinks the participant and takes its voice back out of the profile's voiceprint.
    static func detach(_ participant: MeetingParticipant) {
        if let profile = participant.speaker, participant.contributedWeight > 0, let embedding = participant.embedding {
            profile.voiceprint = EmbeddingMath.removing(embedding, weight: participant.contributedWeight, from: profile.voiceprint)
        }
        participant.contributedWeight = 0
        participant.matchSimilarity = nil
        participant.speaker = nil
    }

    /// "This voice is actually <target>": moves the participant and corrects both voiceprints.
    static func reassign(_ participant: MeetingParticipant, to target: SpeakerProfile, in context: ModelContext) {
        let previous = participant.speaker
        guard previous?.id != target.id else { return }
        detach(participant)
        attach(participant, to: target)
        if let previous {
            deleteIfUnused(previous, ignoring: participant, in: context)
        }
        try? context.save()
    }

    /// The voice was matched to the wrong person and belongs to someone new.
    @discardableResult
    static func splitIntoNewProfile(_ participant: MeetingParticipant, name: String?, in context: ModelContext) -> SpeakerProfile {
        let profile = makeProfile(number: nextNumber(in: context), in: context)
        if let name {
            rename(profile, to: name)
        }
        reassign(participant, to: profile, in: context)
        return profile
    }

    static func rename(_ profile: SpeakerProfile, to name: String) {
        profile.name = name
        profile.isNamedByUser = true
    }

    /// Two profiles turned out to be the same person: everything of `source` moves to `target`.
    static func merge(_ source: SpeakerProfile, into target: SpeakerProfile, in context: ModelContext) {
        guard source.id != target.id else { return }
        for participant in Array(source.participants) {
            participant.speaker = target
        }
        target.voiceprint = EmbeddingMath.merging(source.voiceprint, into: target.voiceprint)
        context.delete(source)
        try? context.save()
    }

    static func delete(_ profile: SpeakerProfile, in context: ModelContext) {
        for participant in Array(profile.participants) {
            participant.contributedWeight = 0
            participant.matchSimilarity = nil
            participant.speaker = nil
        }
        context.delete(profile)
        try? context.save()
    }

    /// Removes the transcript of a meeting (before re-processing it) without leaving stale voice data behind.
    static func clearTranscript(of meeting: Meeting, in context: ModelContext) {
        for participant in Array(meeting.participants) {
            let previous = participant.speaker
            detach(participant)
            if let previous {
                deleteIfUnused(previous, ignoring: participant, in: context)
            }
            context.delete(participant)
        }
        for segment in Array(meeting.segments) {
            context.delete(segment)
        }
    }

    /// Auto-created profiles that no longer have any voice or meeting are noise from a wrong match.
    private static func deleteIfUnused(_ profile: SpeakerProfile, ignoring participant: MeetingParticipant, in context: ModelContext) {
        guard !profile.isNamedByUser, !profile.hasVoiceprint else { return }
        let others = profile.participants.filter { $0.id != participant.id }
        guard others.isEmpty else { return }
        context.delete(profile)
    }
}
