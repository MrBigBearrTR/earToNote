import Foundation
import SwiftData

enum MeetingStatus: String, Codable, CaseIterable {
    case recording
    case processing
    case ready
    case failed
}

@Model
final class Meeting {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var duration: Double
    var audioFileName: String
    var statusRaw: String
    var errorMessage: String?
    var localeIdentifier: String

    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.meeting)
    var segments: [TranscriptSegment] = []

    @Relationship(deleteRule: .cascade, inverse: \MeetingParticipant.meeting)
    var participants: [MeetingParticipant] = []

    init(id: UUID = UUID(), title: String, createdAt: Date = .now, localeIdentifier: String) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = 0
        self.audioFileName = RecordingStore.fileName(for: id)
        self.statusRaw = MeetingStatus.recording.rawValue
        self.errorMessage = nil
        self.localeIdentifier = localeIdentifier
    }

    var status: MeetingStatus {
        get { MeetingStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    var audioURL: URL {
        RecordingStore.url(forFileName: audioFileName)
    }

    var orderedSegments: [TranscriptSegment] {
        segments.sorted { $0.index < $1.index }
    }

    var orderedParticipants: [MeetingParticipant] {
        participants.sorted { $0.firstAppearance < $1.firstAppearance }
    }

    static func defaultTitle(for date: Date) -> String {
        "Toplantı " + date.formatted(.dateTime.day().month(.abbreviated).year().hour().minute())
    }
}
