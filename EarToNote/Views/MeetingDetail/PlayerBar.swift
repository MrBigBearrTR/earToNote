import MeetingCore
import SwiftUI

struct PlayerBar: View {
    let player: AudioPlayer

    @State private var scrubTime: TimeInterval?

    var body: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { scrubTime ?? player.currentTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(player.duration, 0.1),
                onEditingChanged: { editing in
                    if !editing, let scrubTime {
                        player.seek(to: scrubTime)
                        self.scrubTime = nil
                    }
                }
            )
            .accessibilityLabel("Oynatma konumu")

            HStack {
                Text(TranscriptFormatter.timestamp(scrubTime ?? player.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .leading)

                Spacer()

                Button {
                    player.skip(by: -15)
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title3)
                }
                .accessibilityLabel("15 saniye geri")

                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 40))
                }
                .padding(.horizontal, 20)
                .accessibilityLabel(player.isPlaying ? "Duraklat" : "Oynat")

                Button {
                    player.skip(by: 15)
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title3)
                }
                .accessibilityLabel("15 saniye ileri")

                Spacer()

                Text(TranscriptFormatter.timestamp(player.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
