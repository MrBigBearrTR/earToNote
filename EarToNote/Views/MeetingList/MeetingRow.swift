import MeetingCore
import SwiftUI

struct MeetingRow: View {
    let meeting: Meeting
    let progress: ProcessingProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meeting.title)
                .font(.headline)
                .lineLimit(2)

            Text("\(meeting.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(TranscriptFormatter.durationText(meeting.duration))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            statusLine
                .font(.caption)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch meeting.status {
        case .recording:
            Label("Kaydediliyor", systemImage: "record.circle")
                .foregroundStyle(.red)
        case .processing:
            if let progress {
                ProgressView(value: progress.fraction) {
                    Text(progress.stage.title)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("İşleniyor", systemImage: "hourglass")
                    .foregroundStyle(.secondary)
            }
        case .ready:
            let names = meeting.orderedParticipants.map(\.displayName)
            Label(names.isEmpty ? "Konuşma algılanmadı" : names.joined(separator: ", "), systemImage: "person.2")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .failed:
            Label("İşlenemedi", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
    }
}
