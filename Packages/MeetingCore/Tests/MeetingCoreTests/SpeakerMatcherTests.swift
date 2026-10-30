import XCTest
@testable import MeetingCore

final class SpeakerMatcherTests: XCTestCase {
    private let ali = UUID()
    private let ayse = UUID()

    func testMatchesCandidatesToMostSimilarSavedPerson() {
        let known = [
            KnownSpeaker(id: ali, embedding: [1, 0, 0]),
            KnownSpeaker(id: ayse, embedding: [0, 1, 0]),
        ]
        let candidates = [
            SpeakerCandidate(key: "S1", embedding: [0.1, 0.95, 0], speechDuration: 30),
            SpeakerCandidate(key: "S2", embedding: [0.9, 0.1, 0.1], speechDuration: 40),
        ]

        let matches = SpeakerMatcher(threshold: 0.65).match(candidates: candidates, known: known)

        XCTAssertEqual(matches["S1"]?.profileID, ayse)
        XCTAssertEqual(matches["S2"]?.profileID, ali)
    }

    func testCandidateBelowThresholdGetsNoProfile() {
        let known = [KnownSpeaker(id: ali, embedding: [1, 0, 0])]
        let candidates = [SpeakerCandidate(key: "S1", embedding: [0, 0, 1], speechDuration: 10)]

        let match = SpeakerMatcher(threshold: 0.65).match(candidates: candidates, known: known)["S1"]

        XCTAssertNotNil(match)
        XCTAssertNil(match?.profileID)
        XCTAssertEqual(match?.similarity ?? 1, 0, accuracy: 1e-6)
    }

    func testOneSavedPersonIsNeverGivenToTwoSpeakersOfTheSameMeeting() {
        let known = [KnownSpeaker(id: ali, embedding: [1, 0])]
        let candidates = [
            SpeakerCandidate(key: "S1", embedding: [0.9, 0.2], speechDuration: 20),
            SpeakerCandidate(key: "S2", embedding: [0.99, 0.05], speechDuration: 20),
        ]

        let matches = SpeakerMatcher(threshold: 0.6).match(candidates: candidates, known: known)

        XCTAssertEqual(matches["S2"]?.profileID, ali)
        XCTAssertNil(matches["S1"]?.profileID)
    }

    func testEqualSimilarityPrefersCandidateWithMoreSpeech() {
        let known = [KnownSpeaker(id: ali, embedding: [1, 0])]
        let candidates = [
            SpeakerCandidate(key: "short", embedding: [1, 0], speechDuration: 2),
            SpeakerCandidate(key: "long", embedding: [1, 0], speechDuration: 50),
        ]

        let matches = SpeakerMatcher(threshold: 0.6).match(candidates: candidates, known: known)

        XCTAssertEqual(matches["long"]?.profileID, ali)
        XCTAssertNil(matches["short"]?.profileID)
    }

    func testCandidatesWithoutEmbeddingAreReturnedUnmatched() {
        let known = [KnownSpeaker(id: ali, embedding: [1, 0])]
        let candidates = [SpeakerCandidate(key: "S1", embedding: [], speechDuration: 5)]

        let matches = SpeakerMatcher(threshold: 0.6).match(candidates: candidates, known: known)

        XCTAssertEqual(matches.count, 1)
        XCTAssertNil(matches["S1"]?.profileID)
    }

    func testVoiceprintPolicyIgnoresShortSpeechAndCapsLongSpeech() {
        let policy = VoiceprintPolicy(minimumSpeech: 3, maximumWeight: 600)

        XCTAssertEqual(policy.weight(forSpeechDuration: 2.9), 0)
        XCTAssertEqual(policy.weight(forSpeechDuration: 3), 3)
        XCTAssertEqual(policy.weight(forSpeechDuration: 1_000), 600)
        XCTAssertEqual(policy.weight(forSpeechDuration: .nan), 0)
    }

    func testSpeakerNamingUsesGlobalNumbers() {
        XCTAssertEqual(SpeakerNaming.nextNumber(existing: []), 1)
        XCTAssertEqual(SpeakerNaming.nextNumber(existing: [1, 4, 2]), 5)
        XCTAssertEqual(SpeakerNaming.defaultName(number: 3), "Konuşmacı 3")
        XCTAssertEqual(SpeakerNaming.cleanedName("  Ali   Veli "), "Ali Veli")
        XCTAssertNil(SpeakerNaming.cleanedName("   "))
    }
}
