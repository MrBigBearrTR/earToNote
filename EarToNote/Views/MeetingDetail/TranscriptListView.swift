import MeetingCore
import SwiftUI

/// The speaker-attributed transcript. Kept separate from the detail screen so that playback
/// progress only re-renders the transcript, not the toolbar and its export menu.
struct TranscriptListView: View {
    let meeting: Meeting
    let player: AudioPlayer
    let onSelectSpeaker: (MeetingParticipant?) -> Void

    var body: some View {
        let segments = meeting.orderedSegments
        if segments.isEmpty {
            ContentUnavailableView(
                "Konuşma algılanmadı",
                systemImage: "waveform.slash",
                description: Text("Kayıtta yazıya dökülebilecek bir konuşma bulunamadı.")
            )
        } else {
            let activeIndex = activeSegmentIndex(in: segments)
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    TranscriptSegmentRow(
                        segment: segment,
                        isActive: index == activeIndex,
                        onSelectSpeaker: {
                            onSelectSpeaker(segment.participant)
                        },
                        onPlay: {
                            player.play(from: segment.start)
                        }
                    )
                }
            }
        }
    }

    private func activeSegmentIndex(in segments: [TranscriptSegment]) -> Int? {
        guard player.isPlaying || player.currentTime > 0 else { return nil }
        let time = player.currentTime
        return segments.lastIndex { $0.start <= time && time < max($0.end, $0.start + 0.5) }
    }
}

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment
    let isActive: Bool
    let onSelectSpeaker: () -> Void
    let onPlay: () -> Void

    var body: some View {
        let color = SpeakerPalette.color(for: segment.participant?.speaker?.number)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: onSelectSpeaker) {
                    HStack(spacing: 6) {
                        SpeakerDot(number: segment.participant?.speaker?.number)
                        Text(segment.speakerName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(color)
                    }
                }
                .accessibilityHint("Konuşmacının adını düzenle")

                Spacer()

                Button(action: onPlay) {
                    Label(TranscriptFormatter.timestamp(segment.start), systemImage: "play.fill")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("\(TranscriptFormatter.timestamp(segment.start)) anından oynat")
            }
            .buttonStyle(.plain)

            Text(segment.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActive ? color.opacity(0.18) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isActive ? color.opacity(0.6) : .clear, lineWidth: 1.5)
        )
    }
}
