import Foundation

/// Combines speech-to-text output (timed words) with diarization output (speaker turns) into
/// speaker-attributed paragraphs.
public struct TranscriptAligner: Sendable {
    /// A word that overlaps no turn inherits the previous word's speaker when it follows within this gap.
    public var continuationGap: Double
    /// A pause at least this long starts a new paragraph even if the speaker did not change.
    public var paragraphPause: Double
    /// Paragraphs longer than this are split at the next sentence boundary.
    public var maxParagraphDuration: Double

    public init(continuationGap: Double = 1.0, paragraphPause: Double = 4.0, maxParagraphDuration: Double = 90) {
        self.continuationGap = continuationGap
        self.paragraphPause = paragraphPause
        self.maxParagraphDuration = maxParagraphDuration
    }

    /// Returns the speaker key for every word (same order as `words`).
    public func assignSpeakers(words: [TimedWord], turns: [SpeakerTurn]) -> [String?] {
        let sortedTurns = turns.sorted { $0.start < $1.start }
        var assignments: [String?] = []
        assignments.reserveCapacity(words.count)

        var previousWord: TimedWord?
        var previousKey: String?
        for word in words {
            var key = bestOverlappingTurn(for: word, in: sortedTurns)?.speakerKey
            if key == nil, let previousKey, let previousWord, word.start - previousWord.end <= continuationGap {
                key = previousKey
            }
            if key == nil {
                key = nearestTurn(to: word, in: sortedTurns)?.speakerKey
            }
            assignments.append(key)
            previousWord = word
            previousKey = key
        }
        return assignments
    }

    public func align(words: [TimedWord], turns: [SpeakerTurn]) -> [AlignedSegment] {
        let orderedWords = words.enumerated()
            .sorted { lhs, rhs in
                lhs.element.start == rhs.element.start ? lhs.offset < rhs.offset : lhs.element.start < rhs.element.start
            }
            .map(\.element)
        let keys = assignSpeakers(words: orderedWords, turns: turns)

        var segments: [AlignedSegment] = []
        var currentTokens: [String] = []
        var currentKey: String?
        var currentStart = 0.0
        var currentEnd = 0.0

        func flush() {
            let text = TextJoiner.join(currentTokens)
            if !text.isEmpty {
                segments.append(AlignedSegment(speakerKey: currentKey, start: currentStart, end: currentEnd, text: text))
            }
            currentTokens = []
        }

        for (word, key) in zip(orderedWords, keys) {
            if currentTokens.isEmpty {
                currentKey = key
                currentStart = word.start
                currentEnd = word.end
                currentTokens = [word.text]
                continue
            }

            let speakerChanged = key != currentKey
            let longPause = word.start - currentEnd >= paragraphPause
            let tooLong = currentEnd - currentStart >= maxParagraphDuration && endsSentence(currentTokens.last)
            if speakerChanged || longPause || tooLong {
                flush()
                currentKey = key
                currentStart = word.start
                currentEnd = word.end
                currentTokens = [word.text]
            } else {
                currentTokens.append(word.text)
                currentEnd = max(currentEnd, word.end)
            }
        }
        flush()
        return segments
    }

    private func bestOverlappingTurn(for word: TimedWord, in turns: [SpeakerTurn]) -> SpeakerTurn? {
        guard !turns.isEmpty else { return nil }
        // Zero-length words still need to land inside a turn.
        let wordEnd = max(word.end, word.start + 0.001)
        var best: SpeakerTurn?
        var bestOverlap = 0.0
        for turn in turns {
            if turn.start >= wordEnd { break }
            let overlap = min(turn.end, wordEnd) - max(turn.start, word.start)
            if overlap > bestOverlap {
                bestOverlap = overlap
                best = turn
            }
        }
        return best
    }

    private func nearestTurn(to word: TimedWord, in turns: [SpeakerTurn]) -> SpeakerTurn? {
        let midpoint = (word.start + word.end) / 2
        return turns.min { lhs, rhs in
            distance(from: midpoint, to: lhs) < distance(from: midpoint, to: rhs)
        }
    }

    private func distance(from time: Double, to turn: SpeakerTurn) -> Double {
        if time < turn.start { return turn.start - time }
        if time > turn.end { return time - turn.end }
        return 0
    }

    private func endsSentence(_ token: String?) -> Bool {
        guard let last = token?.trimmingCharacters(in: .whitespacesAndNewlines).last else { return false }
        return last == "." || last == "!" || last == "?" || last == "…"
    }
}
