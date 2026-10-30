import Foundation

/// A speaker found by diarization in the current recording.
public struct SpeakerCandidate: Equatable, Sendable {
    public var key: String
    public var embedding: [Float]
    public var speechDuration: Double

    public init(key: String, embedding: [Float], speechDuration: Double) {
        self.key = key
        self.embedding = embedding
        self.speechDuration = speechDuration
    }
}

/// A person saved on the device with a voiceprint from earlier meetings.
public struct KnownSpeaker: Equatable, Sendable {
    public var id: UUID
    public var embedding: [Float]

    public init(id: UUID, embedding: [Float]) {
        self.id = id
        self.embedding = embedding
    }
}

public struct SpeakerMatch: Equatable, Sendable {
    public var candidateKey: String
    /// `nil` when no saved person was similar enough; the caller should create a new profile.
    public var profileID: UUID?
    /// Highest similarity seen for this candidate, even when it stayed below the threshold.
    public var similarity: Float

    public init(candidateKey: String, profileID: UUID?, similarity: Float) {
        self.candidateKey = candidateKey
        self.profileID = profileID
        self.similarity = similarity
    }
}

/// Matches the speakers of a new recording to saved people by voiceprint similarity.
///
/// Matching is one-to-one: two speakers of the same recording are never given the same saved
/// person, because diarization already decided they are different voices.
public struct SpeakerMatcher: Sendable {
    public var threshold: Float

    public init(threshold: Float) {
        self.threshold = threshold
    }

    public func match(candidates: [SpeakerCandidate], known: [KnownSpeaker]) -> [String: SpeakerMatch] {
        struct Pair {
            let candidateIndex: Int
            let knownIndex: Int
            let similarity: Float
        }

        var pairs: [Pair] = []
        var bestSimilarity: [String: Float] = [:]
        for (candidateIndex, candidate) in candidates.enumerated() where !candidate.embedding.isEmpty {
            for (knownIndex, person) in known.enumerated() where !person.embedding.isEmpty {
                let similarity = EmbeddingMath.cosineSimilarity(candidate.embedding, person.embedding)
                pairs.append(Pair(candidateIndex: candidateIndex, knownIndex: knownIndex, similarity: similarity))
                bestSimilarity[candidate.key] = max(bestSimilarity[candidate.key] ?? -1, similarity)
            }
        }

        pairs.sort { lhs, rhs in
            if lhs.similarity != rhs.similarity { return lhs.similarity > rhs.similarity }
            // Prefer the candidate with more speech: its voiceprint is more reliable.
            return candidates[lhs.candidateIndex].speechDuration > candidates[rhs.candidateIndex].speechDuration
        }

        var result: [String: SpeakerMatch] = [:]
        var usedKnown = Set<Int>()
        for pair in pairs where pair.similarity >= threshold {
            let key = candidates[pair.candidateIndex].key
            guard result[key] == nil, !usedKnown.contains(pair.knownIndex) else { continue }
            usedKnown.insert(pair.knownIndex)
            result[key] = SpeakerMatch(candidateKey: key, profileID: known[pair.knownIndex].id, similarity: pair.similarity)
        }

        for candidate in candidates where result[candidate.key] == nil {
            result[candidate.key] = SpeakerMatch(
                candidateKey: candidate.key,
                profileID: nil,
                similarity: bestSimilarity[candidate.key] ?? 0
            )
        }
        return result
    }
}
