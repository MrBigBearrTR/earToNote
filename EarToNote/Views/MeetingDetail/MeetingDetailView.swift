import MeetingCore
import SwiftData
import SwiftUI
import UIKit

struct MeetingDetailView: View {
    let meeting: Meeting
    let onDelete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(MeetingProcessor.self) private var processor
    @State private var player = AudioPlayer()
    @State private var editingParticipant: MeetingParticipant?
    @State private var isEditingTitle = false
    @State private var draftTitle = ""
    @State private var confirmingDelete = false
    @State private var toastMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                content
            }
            .padding()
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            if player.isAvailable {
                PlayerBar(player: player)
            }
        }
        .overlay(alignment: .top) {
            if let toastMessage {
                ToastView(message: toastMessage)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(.spring(duration: 0.3), value: toastMessage)
        .navigationTitle(meeting.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if meeting.status == .ready {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        copy(TranscriptExport.plainText(for: meeting), message: "Metin kopyalandı")
                    } label: {
                        Label("Metni Kopyala", systemImage: "doc.on.doc")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                MeetingActionsMenu(
                    meeting: meeting,
                    isProcessing: processor.isProcessing(meeting.id),
                    onCopy: copy(_:message:),
                    onRename: beginTitleEdit,
                    onReprocess: { speakerCount in
                        meeting.expectedSpeakerCount = speakerCount
                        processor.process(meeting, in: modelContext)
                    },
                    onDelete: { confirmingDelete = true }
                )
            }
        }
        .sheet(item: $editingParticipant) { participant in
            NavigationStack {
                RenameSpeakerSheet(participant: participant)
            }
        }
        .alert("Toplantı adı", isPresented: $isEditingTitle) {
            TextField("Başlık", text: $draftTitle)
            Button("Kaydet") {
                let cleaned = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    meeting.title = cleaned
                    try? modelContext.save()
                }
            }
            Button("Vazgeç", role: .cancel) {}
        }
        .confirmationDialog("Toplantı silinsin mi?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                deleteMeeting()
            }
        } message: {
            Text("Ses kaydı ve metin kalıcı olarak silinir. Kayıtlı kişiler korunur.")
        }
        .task {
            player.load(url: meeting.audioURL)
        }
        .onDisappear {
            // iOS can report a disappearance for a detail view that stays on screen (iPhone split view),
            // so only pause here; the player is released together with the view.
            player.pause()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: beginTitleEdit) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(meeting.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.leading)
                    Image(systemName: "pencil")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Toplantı adını değiştir")

            Text("\(meeting.createdAt.formatted(date: .long, time: .shortened)) · \(TranscriptFormatter.durationText(meeting.duration))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            let participants = meeting.orderedParticipants
            if meeting.status == .ready, !participants.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(participants) { participant in
                            Button {
                                editingParticipant = participant
                            } label: {
                                HStack(spacing: 6) {
                                    SpeakerDot(number: participant.speaker?.number)
                                    Text(participant.displayName)
                                    Image(systemName: "pencil")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color(.secondarySystemBackground)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text("İsim vermek veya düzeltmek için bir konuşmacıya dokunun. Verdiğiniz isim sonraki toplantılarda da kullanılır.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch meeting.status {
        case .recording:
            Label("Kayıt sürüyor…", systemImage: "record.circle")
                .foregroundStyle(.red)
        case .processing:
            ProcessingStatusView(progress: processor.progress[meeting.id]) {
                processor.cancel(meeting.id)
            }
        case .failed:
            FailedStatusView(
                message: meeting.errorMessage ?? "Bilinmeyen bir hata oluştu.",
                canRetry: RecordingStore.fileExists(named: meeting.audioFileName),
                onRetry: { processor.process(meeting, in: modelContext) },
                onShowPrevious: meeting.segments.isEmpty ? nil : {
                    meeting.status = .ready
                    meeting.errorMessage = nil
                    try? modelContext.save()
                }
            )
        case .ready:
            TranscriptListView(meeting: meeting, player: player) { participant in
                editingParticipant = participant
            }
        }
    }

    private func beginTitleEdit() {
        draftTitle = meeting.title
        isEditingTitle = true
    }

    private func copy(_ text: String, message: String) {
        UIPasteboard.general.string = text
        toastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    private func deleteMeeting() {
        player.stop()
        let meeting = meeting
        let context = modelContext
        let processor = processor
        onDelete()
        // Let the detail view leave the screen before its model object goes away.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            MeetingActions.delete(meeting, in: context, processor: processor)
        }
    }
}

private struct MeetingActionsMenu: View {
    let meeting: Meeting
    let isProcessing: Bool
    let onCopy: (String, String) -> Void
    let onRename: () -> Void
    /// The number of people in the meeting, or `nil` to let it be detected.
    let onReprocess: (Int?) -> Void
    let onDelete: () -> Void

    var body: some View {
        Menu {
            if meeting.status == .ready {
                let plainText = TranscriptExport.plainText(for: meeting)
                let markdown = TranscriptExport.markdown(for: meeting)
                let baseName = TranscriptExport.fileBaseName(for: meeting)

                Section("Metin") {
                    Button {
                        onCopy(plainText, "Metin kopyalandı")
                    } label: {
                        Label("Metni Kopyala", systemImage: "doc.on.doc")
                    }
                    Button {
                        onCopy(markdown, "Markdown kopyalandı")
                    } label: {
                        Label("Markdown Olarak Kopyala", systemImage: "number")
                    }
                    ShareLink(
                        item: TranscriptFile(fileName: "\(baseName).txt", contents: plainText),
                        preview: SharePreview(meeting.title)
                    ) {
                        Label("Metin Dosyası Paylaş (.txt)", systemImage: "square.and.arrow.up")
                    }
                    ShareLink(
                        item: TranscriptFile(fileName: "\(baseName).md", contents: markdown),
                        preview: SharePreview(meeting.title)
                    ) {
                        Label("Markdown Paylaş (.md)", systemImage: "square.and.arrow.up.on.square")
                    }
                }
            }

            if RecordingStore.fileExists(named: meeting.audioFileName) {
                Section("Ses") {
                    ShareLink(
                        item: RecordingFile(
                            sourceURL: meeting.audioURL,
                            fileName: "\(TranscriptExport.fileBaseName(for: meeting)).m4a"
                        ),
                        preview: SharePreview(meeting.title)
                    ) {
                        Label("Ses Kaydını Paylaş", systemImage: "waveform")
                    }
                }
            }

            Section {
                Button(action: onRename) {
                    Label("Yeniden Adlandır", systemImage: "pencil")
                }
                reprocessMenu
                    .disabled(isProcessing || meeting.status == .recording)
                Button(role: .destructive, action: onDelete) {
                    Label("Toplantıyı Sil", systemImage: "trash")
                }
            }
        } label: {
            Label("Diğer", systemImage: "ellipsis.circle")
        }
    }

    private var reprocessMenu: some View {
        Menu {
            Button {
                onReprocess(nil)
            } label: {
                Label("Kişi Sayısını Otomatik Bul", systemImage: meeting.expectedSpeakerCount == nil ? "checkmark" : "wand.and.stars")
            }
            Section("Toplantıda kaç kişi vardı?") {
                ForEach(1...8, id: \.self) { count in
                    Button {
                        onReprocess(count)
                    } label: {
                        if meeting.expectedSpeakerCount == count {
                            Label("\(count) kişi", systemImage: "checkmark")
                        } else {
                            Text("\(count) kişi")
                        }
                    }
                }
            }
        } label: {
            Label("Yeniden İşle", systemImage: "arrow.clockwise")
        }
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 4, y: 2)
    }
}
