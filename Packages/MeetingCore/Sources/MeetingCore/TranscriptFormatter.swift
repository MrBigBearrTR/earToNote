import Foundation

public struct ExportSegment: Equatable, Sendable {
    public var start: Double
    public var speaker: String
    public var text: String

    public init(start: Double, speaker: String, text: String) {
        self.start = start
        self.speaker = speaker
        self.text = text
    }
}

public struct ExportMetadata: Equatable, Sendable {
    public var title: String
    public var dateText: String
    public var duration: Double

    public init(title: String, dateText: String, duration: Double) {
        self.title = title
        self.dateText = dateText
        self.duration = duration
    }
}

/// Produces the text the user copies or shares at the end of a meeting.
public enum TranscriptFormatter {
    /// `HH:MM:SS`, e.g. `00:01:23`.
    public static func timestamp(_ seconds: Double) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0).rounded(.down))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    /// Short human readable duration in Turkish, e.g. `1 sa 5 dk`, `12 dk 3 sn`, `45 sn`.
    public static func durationText(_ seconds: Double) -> String {
        let total = Int(max(0, seconds.isFinite ? seconds : 0).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return "\(hours) sa \(minutes) dk" }
        if minutes > 0 { return secs > 0 ? "\(minutes) dk \(secs) sn" : "\(minutes) dk" }
        return "\(secs) sn"
    }

    /// Unique speaker names in order of first appearance.
    public static func participants(in segments: [ExportSegment]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for segment in segments where seen.insert(segment.speaker).inserted {
            names.append(segment.speaker)
        }
        return names
    }

    public static func plainText(metadata: ExportMetadata, segments: [ExportSegment]) -> String {
        var lines = [
            metadata.title,
            "Tarih: \(metadata.dateText)",
            "Süre: \(durationText(metadata.duration))",
        ]
        let names = participants(in: segments)
        if !names.isEmpty {
            lines.append("Katılımcılar: \(names.joined(separator: ", "))")
        }
        lines.append("")
        for segment in segments {
            lines.append("[\(timestamp(segment.start))] \(segment.speaker): \(segment.text)")
        }
        return lines.joined(separator: "\n")
    }

    public static func markdown(metadata: ExportMetadata, segments: [ExportSegment]) -> String {
        var lines = [
            "# \(metadata.title)",
            "",
            "- **Tarih:** \(metadata.dateText)",
            "- **Süre:** \(durationText(metadata.duration))",
        ]
        let names = participants(in: segments)
        if !names.isEmpty {
            lines.append("- **Katılımcılar:** \(names.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("## Konuşmalar")
        for segment in segments {
            lines.append("")
            lines.append("**\(segment.speaker)** `\(timestamp(segment.start))`  ")
            lines.append(segment.text)
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
