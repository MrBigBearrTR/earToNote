import Foundation

/// Plans the audio the speech recognizer hears: every diarized turn on its own, followed by a short
/// silence, with the pauses between turns left out. Recognizers favor the dominant voice of a
/// recording; separating the turns (and leveling each one, see `TurnLeveler`) lets quieter people,
/// usually those sitting farther from the phone, be transcribed too. Every recognized word can then
/// be traced back to the turn it came from.
///
/// All positions are in samples at `sampleRate`, so the producer of the audio and `place(_:)` agree
/// exactly on where each turn sits.
public struct TurnLayout: Equatable, Sendable {
    public struct Region: Equatable, Sendable {
        public var speakerKey: String
        /// First sample of the region in the recording.
        public var sourceStart: Int
        public var sampleCount: Int
        /// First sample of the region in the recognizer's audio.
        public var outputStart: Int

        public var sourceEnd: Int { sourceStart + sampleCount }
        public var outputEnd: Int { outputStart + sampleCount }
    }

    public let sampleRate: Double
    public let gapSamples: Int
    public let regions: [Region]

    /// - Parameters:
    ///   - padding: Audio kept before and after each turn so that word edges are not cut off. It never
    ///     reaches past the midpoint to the neighboring turn.
    ///   - gap: Silence inserted after every region.
    ///   - mergeGap: Consecutive turns of the same speaker closer than this become one region.
    public init(
        turns: [SpeakerTurn],
        recordingDuration: Double,
        sampleRate: Double,
        padding: Double = 0.4,
        gap: Double = 1.0,
        mergeGap: Double = 0.5
    ) {
        self.sampleRate = sampleRate
        self.gapSamples = Int((gap * sampleRate).rounded())

        var merged: [SpeakerTurn] = []
        for turn in turns.sorted(by: { $0.start < $1.start }) where turn.end > turn.start {
            if let last = merged.last, last.speakerKey == turn.speakerKey, turn.start - last.end <= mergeGap {
                merged[merged.count - 1].end = max(last.end, turn.end)
            } else {
                merged.append(turn)
            }
        }

        let totalSamples = Int((max(0, recordingDuration) * sampleRate).rounded())
        var regions: [Region] = []
        var output = 0
        var previousEnd = 0
        for (index, turn) in merged.enumerated() {
            let lowerLimit = index > 0 ? (merged[index - 1].end + turn.start) / 2 : 0
            let upperLimit = index + 1 < merged.count ? (turn.end + merged[index + 1].start) / 2 : recordingDuration
            let start = max(previousEnd, Int((max(lowerLimit, turn.start - padding) * sampleRate).rounded()))
            let end = min(totalSamples, Int((min(upperLimit, turn.end + padding) * sampleRate).rounded()))
            guard end > start else { continue }
            regions.append(Region(speakerKey: turn.speakerKey, sourceStart: start, sampleCount: end - start, outputStart: output))
            output += end - start + gapSamples
            previousEnd = end
        }
        self.regions = regions
    }

    public var isEmpty: Bool { regions.isEmpty }

    public var outputSampleCount: Int {
        regions.last.map { $0.outputEnd + gapSamples } ?? 0
    }

    public var outputDuration: Double {
        Double(outputSampleCount) / sampleRate
    }

    /// Moves words recognized in the layout's audio back to the recording's timeline, together with the
    /// speaker of the region each word came from. Words that fall into a gap belong to the nearest region.
    public func place(_ words: [TimedWord]) -> (words: [TimedWord], speakerKeys: [String]) {
        guard !regions.isEmpty else { return ([], []) }
        var placed: [TimedWord] = []
        var keys: [String] = []
        placed.reserveCapacity(words.count)
        keys.reserveCapacity(words.count)
        for word in words {
            let region = regions[regionIndex(at: (word.start + word.end) / 2 * sampleRate)]
            func sourceTime(_ outputTime: Double) -> Double {
                let sample = min(max(outputTime * sampleRate, Double(region.outputStart)), Double(region.outputEnd))
                return (sample - Double(region.outputStart) + Double(region.sourceStart)) / sampleRate
            }
            placed.append(TimedWord(text: word.text, start: sourceTime(word.start), end: sourceTime(word.end)))
            keys.append(region.speakerKey)
        }
        return (placed, keys)
    }

    private func regionIndex(at outputSample: Double) -> Int {
        // Last region starting at or before the sample (binary search), then the closer of it and the next.
        var low = 0
        var high = regions.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if Double(regions[mid].outputStart) <= outputSample {
                low = mid
            } else {
                high = mid - 1
            }
        }
        let current = regions[low]
        guard outputSample > Double(current.outputEnd), low + 1 < regions.count else { return low }
        let next = regions[low + 1]
        return outputSample - Double(current.outputEnd) <= Double(next.outputStart) - outputSample ? low : low + 1
    }
}

/// Brings each turn to a common loudness so that quiet and loud speakers reach the recognizer alike.
public struct TurnLeveler: Sendable {
    /// Level the speech of a turn is brought to, in dBFS.
    public var targetLevel: Float
    public var maximumBoost: Float
    public var maximumCut: Float

    public init(targetLevel: Float = -16, maximumBoost: Float = 30, maximumCut: Float = 6) {
        self.targetLevel = targetLevel
        self.maximumBoost = maximumBoost
        self.maximumCut = maximumCut
    }

    /// Linear gain for a turn, from the RMS values of its short frames (e.g. 20 ms). Only the louder half
    /// of the frames is measured, so pauses inside the turn do not make it look quieter than the speech.
    public func gain(frameRMS: [Float]) -> Float {
        let sorted = frameRMS.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return 1 }
        let loud = sorted[(sorted.count / 2)...]
        let meanSquare = loud.reduce(Float(0)) { $0 + $1 * $1 } / Float(loud.count)
        guard meanSquare > 1e-12 else { return 1 }
        let level = 10 * log10(meanSquare)
        let gainDB = min(maximumBoost, max(-maximumCut, targetLevel - level))
        return pow(10, gainDB / 20)
    }
}
