import Foundation

/// Decides how much a speaker's embedding from one meeting should count towards their saved voiceprint.
public struct VoiceprintPolicy: Sendable {
    /// Speakers who talked less than this are still labeled, but their voice is too short to trust.
    public var minimumSpeech: Double
    /// Caps a single meeting's influence so one long meeting does not freeze the voiceprint.
    public var maximumWeight: Double

    public init(minimumSpeech: Double = 3, maximumWeight: Double = 600) {
        self.minimumSpeech = minimumSpeech
        self.maximumWeight = maximumWeight
    }

    /// Returns 0 when the embedding must not update the voiceprint.
    public func weight(forSpeechDuration duration: Double) -> Double {
        guard duration.isFinite, duration >= minimumSpeech else { return 0 }
        return min(duration, maximumWeight)
    }
}
