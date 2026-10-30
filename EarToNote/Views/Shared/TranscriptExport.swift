import CoreTransferable
import Foundation
import MeetingCore
import UniformTypeIdentifiers

@MainActor
enum TranscriptExport {
    static func plainText(for meeting: Meeting) -> String {
        TranscriptFormatter.plainText(metadata: metadata(for: meeting), segments: segments(for: meeting))
    }

    static func markdown(for meeting: Meeting) -> String {
        TranscriptFormatter.markdown(metadata: metadata(for: meeting), segments: segments(for: meeting))
    }

    static func fileBaseName(for meeting: Meeting) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = meeting.title
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Toplanti" : cleaned
    }

    private static func metadata(for meeting: Meeting) -> ExportMetadata {
        ExportMetadata(
            title: meeting.title,
            dateText: meeting.createdAt.formatted(date: .long, time: .shortened),
            duration: meeting.duration
        )
    }

    private static func segments(for meeting: Meeting) -> [ExportSegment] {
        meeting.orderedSegments.map { segment in
            ExportSegment(start: segment.start, speaker: segment.speakerName, text: segment.text)
        }
    }
}

/// A text file handed to the share sheet (AirDrop, Files, Mail, Notes, ...).
struct TranscriptFile: Transferable {
    let fileName: String
    let contents: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { file in
            let directory = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: file.fileName, directoryHint: .notDirectory)
            try file.contents.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
