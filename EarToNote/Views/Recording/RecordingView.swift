import MeetingCore
import SwiftUI

enum RecordingOutcome {
    case saved(duration: TimeInterval)
    case cancelled
}

struct RecordingView: View {
    let meeting: Meeting
    let onFinish: (RecordingOutcome) -> Void

    @State private var recorder = AudioRecorder()
    @State private var didStart = false
    @State private var startError: String?
    @State private var confirmingCancel = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                statusBadge

                Text(TranscriptFormatter.timestamp(recorder.elapsed))
                    .font(.system(size: 64, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                LevelMeterView(levels: recorder.levels)
                    .frame(height: 90)
                    .padding(.horizontal)

                if recorder.wasInterrupted {
                    Label("Kayıt bir arama veya başka bir uygulama nedeniyle duraklatıldı. Devam etmek için ▶︎ düğmesine dokunun.", systemImage: "phone.arrow.down.left")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                controls

                Text("Ekran kilitlense de kayıt devam eder.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
            .navigationTitle(meeting.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") {
                        confirmingCancel = true
                    }
                }
            }
            .confirmationDialog("Kayıt silinsin mi?", isPresented: $confirmingCancel, titleVisibility: .visible) {
                Button("Kaydı Sil", role: .destructive) {
                    recorder.cancel()
                    onFinish(.cancelled)
                }
                Button("Kayda Devam Et", role: .cancel) {}
            } message: {
                Text("Bu toplantının ses kaydı kalıcı olarak silinecek.")
            }
            .alert("Kayıt başlatılamadı", isPresented: isShowingStartError) {
                Button("Tamam") {
                    onFinish(.cancelled)
                }
            } message: {
                Text(startError ?? "")
            }
        }
        .interactiveDismissDisabled()
        .task {
            await startIfNeeded()
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(recorder.isPaused ? Color.orange : Color.red)
                .frame(width: 10, height: 10)
                .opacity(recorder.isRecording ? 1 : 0.3)
            Text(recorder.isPaused ? "Duraklatıldı" : "Kaydediliyor")
                .font(.headline)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: Capsule())
    }

    private var controls: some View {
        HStack(spacing: 48) {
            Button {
                if recorder.isPaused {
                    recorder.resume()
                } else {
                    recorder.pause()
                }
            } label: {
                Image(systemName: recorder.isPaused ? "play.fill" : "pause.fill")
                    .font(.title)
                    .frame(width: 72, height: 72)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .accessibilityLabel(recorder.isPaused ? "Kayda devam et" : "Kaydı duraklat")
            .disabled(!recorder.isRecording)

            Button {
                let duration = recorder.stop()
                onFinish(.saved(duration: duration))
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 88, height: 88)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white)
                        .frame(width: 30, height: 30)
                }
            }
            .accessibilityLabel("Kaydı bitir")
            .disabled(!recorder.isRecording)
        }
        .buttonStyle(.plain)
    }

    private var isShowingStartError: Binding<Bool> {
        Binding(
            get: { startError != nil },
            set: { if !$0 { startError = nil } }
        )
    }

    private func startIfNeeded() async {
        guard !didStart else { return }
        didStart = true
        guard await AudioRecorder.requestPermission() else {
            startError = RecorderError.permissionDenied.localizedDescription
            return
        }
        do {
            try recorder.start(recordingTo: meeting.audioURL)
        } catch {
            startError = error.localizedDescription
        }
    }
}

struct LevelMeterView: View {
    let levels: [Float]

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 3) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule()
                        .fill(Color.accentColor.opacity(0.35 + 0.65 * Double(level)))
                        .frame(height: max(4, geometry.size.height * CGFloat(level)))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .animation(.linear(duration: 0.1), value: levels)
        .accessibilityHidden(true)
    }
}
