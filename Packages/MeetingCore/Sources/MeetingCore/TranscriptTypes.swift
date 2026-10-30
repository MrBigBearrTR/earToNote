import Foundation

/// A recognized piece of text (usually a single word) with its position on the recording timeline.
public struct TimedWord: Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = max(start, end)
    }
}

/// A "who spoke when" span produced by diarization. `speakerKey` is only unique within one recording.
public struct SpeakerTurn: Equatable, Sendable {
    public var speakerKey: String
    public var start: Double
    public var end: Double

    public init(speakerKey: String, start: Double, end: Double) {
        self.speakerKey = speakerKey
        self.start = start
        self.end = max(start, end)
    }

    public var duration: Double { end - start }
}

/// A paragraph of transcript attributed to one diarized speaker.
public struct AlignedSegment: Equatable, Sendable {
    public var speakerKey: String?
    public var start: Double
    public var end: Double
    public var text: String

    public init(speakerKey: String?, start: Double, end: Double, text: String) {
        self.speakerKey = speakerKey
        self.start = start
        self.end = end
        self.text = text
    }
}

public enum SpeakerStats {
    /// Total speaking time per diarized speaker key.
    public static func speechDurations(of turns: [SpeakerTurn]) -> [String: Double] {
        turns.reduce(into: [:]) { result, turn in
            result[turn.speakerKey, default: 0] += turn.duration
        }
    }
}
