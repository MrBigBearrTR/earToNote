import XCTest
@testable import MeetingCore

final class TranscriptAlignerTests: XCTestCase {
    private let aligner = TranscriptAligner()

    func testGroupsWordsBySpeakerTurns() {
        let words = [
            TimedWord(text: "Merhaba", start: 0.0, end: 0.4),
            TimedWord(text: "arkadaşlar.", start: 0.5, end: 1.0),
            TimedWord(text: "Selam", start: 2.0, end: 2.3),
            TimedWord(text: "Ali.", start: 2.4, end: 2.7),
            TimedWord(text: "Başlayalım", start: 3.5, end: 4.0),
            TimedWord(text: "mı?", start: 4.0, end: 4.2),
        ]
        let turns = [
            SpeakerTurn(speakerKey: "S1", start: 0.0, end: 1.2),
            SpeakerTurn(speakerKey: "S2", start: 1.9, end: 2.8),
            SpeakerTurn(speakerKey: "S1", start: 3.4, end: 4.5),
        ]

        let segments = aligner.align(words: words, turns: turns)

        XCTAssertEqual(segments, [
            AlignedSegment(speakerKey: "S1", start: 0.0, end: 1.0, text: "Merhaba arkadaşlar."),
            AlignedSegment(speakerKey: "S2", start: 2.0, end: 2.7, text: "Selam Ali."),
            AlignedSegment(speakerKey: "S1", start: 3.5, end: 4.2, text: "Başlayalım mı?"),
        ])
    }

    func testWordIsAssignedToTurnWithLargestOverlap() {
        let words = [TimedWord(text: "evet", start: 1.0, end: 2.0)]
        let turns = [
            SpeakerTurn(speakerKey: "S1", start: 0.0, end: 1.2),
            SpeakerTurn(speakerKey: "S2", start: 1.2, end: 3.0),
        ]

        XCTAssertEqual(aligner.assignSpeakers(words: words, turns: turns), ["S2"])
    }

    func testWordOutsideTurnsContinuesPreviousSpeaker() {
        let words = [
            TimedWord(text: "bir", start: 0.0, end: 0.5),
            TimedWord(text: "iki", start: 1.0, end: 1.3),
        ]
        let turns = [
            SpeakerTurn(speakerKey: "S1", start: 0.0, end: 0.6),
            SpeakerTurn(speakerKey: "S2", start: 1.35, end: 3.0),
        ]

        XCTAssertEqual(aligner.assignSpeakers(words: words, turns: turns), ["S1", "S1"])
    }

    func testIsolatedWordFallsBackToNearestTurn() {
        let words = [TimedWord(text: "tamam", start: 10.0, end: 10.4)]
        let turns = [
            SpeakerTurn(speakerKey: "S1", start: 0.0, end: 2.0),
            SpeakerTurn(speakerKey: "S2", start: 11.0, end: 12.0),
        ]

        XCTAssertEqual(aligner.assignSpeakers(words: words, turns: turns), ["S2"])
    }

    func testWithoutTurnsEverythingIsOneUnknownSpeaker() {
        let words = [
            TimedWord(text: "tek", start: 0.0, end: 0.3),
            TimedWord(text: "kişi", start: 0.4, end: 0.8),
        ]

        let segments = aligner.align(words: words, turns: [])

        XCTAssertEqual(segments, [AlignedSegment(speakerKey: nil, start: 0.0, end: 0.8, text: "tek kişi")])
    }

    func testLongPauseStartsNewParagraphForSameSpeaker() {
        let words = [
            TimedWord(text: "Önce", start: 0.0, end: 0.4),
            TimedWord(text: "bu.", start: 0.5, end: 0.8),
            TimedWord(text: "Sonra", start: 10.0, end: 10.4),
            TimedWord(text: "şu.", start: 10.5, end: 10.8),
        ]
        let turns = [SpeakerTurn(speakerKey: "S1", start: 0.0, end: 11.0)]

        let segments = aligner.align(words: words, turns: turns)

        XCTAssertEqual(segments.map(\.text), ["Önce bu.", "Sonra şu."])
        XCTAssertEqual(segments.map(\.speakerKey), ["S1", "S1"])
    }

    func testVeryLongParagraphSplitsAtSentenceEnd() {
        var aligner = TranscriptAligner()
        aligner.maxParagraphDuration = 5
        let words = [
            TimedWord(text: "Uzun", start: 0, end: 1),
            TimedWord(text: "bir", start: 2, end: 3),
            TimedWord(text: "cümle", start: 4, end: 5),
            TimedWord(text: "devam", start: 6, end: 7),
            TimedWord(text: "ediyor.", start: 8, end: 9),
            TimedWord(text: "Yeni", start: 10, end: 11),
            TimedWord(text: "cümle.", start: 12, end: 13),
        ]
        let turns = [SpeakerTurn(speakerKey: "S1", start: 0, end: 14)]

        let segments = aligner.align(words: words, turns: turns)

        XCTAssertEqual(segments.map(\.text), ["Uzun bir cümle devam ediyor.", "Yeni cümle."])
    }

    func testUnsortedWordsAreOrderedByTime() {
        let words = [
            TimedWord(text: "dünya", start: 0.5, end: 0.9),
            TimedWord(text: "Merhaba", start: 0.0, end: 0.4),
        ]

        let segments = aligner.align(words: words, turns: [SpeakerTurn(speakerKey: "S1", start: 0, end: 1)])

        XCTAssertEqual(segments.map(\.text), ["Merhaba dünya"])
    }

    func testSpeechDurationsSumTurnsPerSpeaker() {
        let turns = [
            SpeakerTurn(speakerKey: "S1", start: 0, end: 2),
            SpeakerTurn(speakerKey: "S2", start: 2, end: 3),
            SpeakerTurn(speakerKey: "S1", start: 5, end: 6.5),
        ]

        let durations = SpeakerStats.speechDurations(of: turns)

        XCTAssertEqual(durations["S1"] ?? 0, 3.5, accuracy: 1e-9)
        XCTAssertEqual(durations["S2"] ?? 0, 1.0, accuracy: 1e-9)
    }
}
