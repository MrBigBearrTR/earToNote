import Foundation
import SwiftData

@MainActor
enum MeetingActions {
    static func startNewMeeting(in context: ModelContext) -> Meeting {
        let now = Date.now
        let meeting = Meeting(
            title: Meeting.defaultTitle(for: now),
            createdAt: now,
            localeIdentifier: AppSettings.localeIdentifier
        )
        context.insert(meeting)
        try? context.save()
        return meeting
    }

    static func finishRecording(_ meeting: Meeting, outcome: RecordingOutcome, in context: ModelContext, processor: MeetingProcessor) {
        switch outcome {
        case .saved(let duration):
            meeting.duration = duration
            try? context.save()
            processor.process(meeting, in: context)
        case .cancelled:
            RecordingStore.deleteFile(named: meeting.audioFileName)
            context.delete(meeting)
            try? context.save()
        }
    }

    /// Deletes the meeting, its transcript and its audio file. Saved people and their voiceprints are
    /// kept so they are still recognized in future meetings.
    static func delete(_ meeting: Meeting, in context: ModelContext, processor: MeetingProcessor) {
        processor.cancel(meeting.id)
        RecordingStore.deleteFile(named: meeting.audioFileName)
        context.delete(meeting)
        try? context.save()
    }
}
