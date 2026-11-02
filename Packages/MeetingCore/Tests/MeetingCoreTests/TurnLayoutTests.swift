import XCTest
@testable import MeetingCore

final class TurnLayoutTests: XCTestCase {
    func testTurnsArePaddedSeparatedAndPauseIsDropped() {
        let turns = [
            SpeakerTurn(speakerKey: "S1", start: 1.0, end: 3.0),
            SpeakerTurn(speakerKey: "S2", start: 10.0, end: 12.0),
        ]

        let layout = TurnLayout(turns: turns, recordingDuration: 20, sampleRate: 10, padding: 0.5, gap: 1.0)

        XCTAssertEqual(layout.regions, [
            TurnLayout.Region(speakerKey: "S1", sourceStart: 5, sampleCount: 30, outputStart: 0),
            TurnLayout.Region(speakerKey: "S2", sourceStart: 95, sampleCount: 30, outputStart: 40),
        ])
        XCTAssertEqual(layout.outputSampleCount, 80)
        XCTAssertEqual(layout.outputDuration, 8, accuracy: 1e-9)
    }

    func testPaddingStopsHalfwayToTheNeighbor() {
        let turns = [
            SpeakerTurn(speakerKey: "S1", start: 0.0, end: 2.0),
            SpeakerTurn(speakerKey: "S2", start: 2.2, end: 4.0),
        ]

        let layout = TurnLayout(turns: turns, recordingDuration: 4, sampleRate: 10, padding: 0.5, gap: 0)

        XCTAssertEqual(layout.regions.map(\.sourceStart), [0, 21])
        XCTAssertEqual(layout.regions.map(\.sourceEnd), [21, 40])
    }

    func testCloseTurnsOfTheSameSpeakerBecomeOneRegion() {
        let turns = [
            SpeakerTurn(speakerKey: "S1", start: 0.0, end: 1.0),
            SpeakerTurn(speakerKey: "S1", start: 1.3, end: 2.0),
            SpeakerTurn(speakerKey: "S1", start: 5.0, end: 6.0),
        ]

        let layout = TurnLayout(turns: turns, recordingDuration: 6, sampleRate: 10, padding: 0, gap: 0, mergeGap: 0.5)

        XCTAssertEqual(layout.regions.map(\.sourceStart), [0, 50])
        XCTAssertEqual(layout.regions.map(\.sampleCount), [20, 10])
    }

    func testWordsAreMovedBackToTheRecordingWithTheirSpeaker() {
        let turns = [
            SpeakerTurn(speakerKey: "S1", start: 1.0, end: 3.0),
            SpeakerTurn(speakerKey: "S2", start: 10.0, end: 12.0),
        ]
        let layout = TurnLayout(turns: turns, recordingDuration: 20, sampleRate: 10, padding: 0.5, gap: 1.0)
        // Output timeline: S1 = 0...3 s (recording 0.5...3.5), gap, S2 = 4...7 s (recording 9.5...12.5).
        let words = [
            TimedWord(text: "merhaba", start: 0.6, end: 1.0),
            TimedWord(text: "evet", start: 4.6, end: 5.0),
            // Recognizers sometimes stretch a word into the following silence.
            TimedWord(text: "tamam", start: 6.8, end: 7.6),
        ]

        let placed = layout.place(words)

        XCTAssertEqual(placed.speakerKeys, ["S1", "S2", "S2"])
        XCTAssertEqual(placed.words[0].start, 1.1, accuracy: 1e-9)
        XCTAssertEqual(placed.words[0].end, 1.5, accuracy: 1e-9)
        XCTAssertEqual(placed.words[1].start, 10.1, accuracy: 1e-9)
        XCTAssertEqual(placed.words[2].start, 12.3, accuracy: 1e-9)
        XCTAssertEqual(placed.words[2].end, 12.5, accuracy: 1e-9)
    }

    func testWordInAGapGoesToTheCloserRegion() {
        let turns = [
            SpeakerTurn(speakerKey: "S1", start: 0.0, end: 1.0),
            SpeakerTurn(speakerKey: "S2", start: 5.0, end: 6.0),
        ]
        let layout = TurnLayout(turns: turns, recordingDuration: 6, sampleRate: 10, padding: 0, gap: 2.0)
        // S1 = 0...1 s, gap 1...3 s, S2 = 3...4 s.

        let placed = layout.place([
            TimedWord(text: "a", start: 1.2, end: 1.4),
            TimedWord(text: "b", start: 2.6, end: 2.8),
        ])

        XCTAssertEqual(placed.speakerKeys, ["S1", "S2"])
        XCTAssertEqual(placed.words[0].start, 1.0, accuracy: 1e-9)
        XCTAssertEqual(placed.words[1].start, 5.0, accuracy: 1e-9)
    }

    func testWithoutTurnsTheLayoutIsEmpty() {
        let layout = TurnLayout(turns: [], recordingDuration: 10, sampleRate: 16_000)

        XCTAssertTrue(layout.isEmpty)
        XCTAssertEqual(layout.outputSampleCount, 0)
        XCTAssertTrue(layout.place([TimedWord(text: "x", start: 0, end: 1)]).words.isEmpty)
    }

    func testLevelerLiftsQuietSpeechToTheTarget() {
        let leveler = TurnLeveler(targetLevel: -20, maximumBoost: 30, maximumCut: 6)
        // Speech at -40 dBFS (0.01 RMS) with pauses that must not count.
        let frames: [Float] = [0.01, 0.01, 0.01, 0.0001, 0.0001]

        XCTAssertEqual(20 * log10(leveler.gain(frameRMS: frames)), 20, accuracy: 0.01)
    }

    func testLevelerLimitsBoostAndCut() {
        let leveler = TurnLeveler(targetLevel: -20, maximumBoost: 12, maximumCut: 6)

        XCTAssertEqual(20 * log10(leveler.gain(frameRMS: [0.0001, 0.0001])), 12, accuracy: 0.01)
        XCTAssertEqual(20 * log10(leveler.gain(frameRMS: [1, 1])), -6, accuracy: 0.01)
        XCTAssertEqual(leveler.gain(frameRMS: []), 1)
        XCTAssertEqual(leveler.gain(frameRMS: [0, 0]), 1)
    }
}
