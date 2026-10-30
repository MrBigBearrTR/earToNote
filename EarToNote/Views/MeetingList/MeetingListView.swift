import SwiftData
import SwiftUI
import UIKit

struct MeetingListView: View {
    @Binding var selection: UUID?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(MeetingProcessor.self) private var processor
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]

    @State private var searchText = ""
    @State private var recordingMeeting: Meeting?
    @State private var showingSpeakers = false
    @State private var showingSettings = false
    @State private var showingPermissionAlert = false
    @State private var pendingDeletionID: UUID?

    var body: some View {
        List(selection: $selection) {
            ForEach(filteredMeetings) { meeting in
                MeetingRow(meeting: meeting, progress: processor.progress[meeting.id])
                    .tag(meeting.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDeletionID = meeting.id
                        } label: {
                            Label("Sil", systemImage: "trash")
                        }
                    }
            }
        }
        .overlay {
            if meetings.isEmpty {
                ContentUnavailableView {
                    Label("Henüz toplantı yok", systemImage: "mic.badge.plus")
                } description: {
                    Text("Toplantıya girdiğinizde aşağıdaki düğmeyle kaydı başlatın. Kayıt bitince konuşmalar konuşmacılara göre yazıya dökülür.")
                }
            } else if filteredMeetings.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .navigationTitle("Toplantılar")
        .searchable(text: $searchText, prompt: "Başlık, kişi veya metin ara")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Ayarlar", systemImage: "gearshape")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSpeakers = true
                } label: {
                    Label("Kişiler", systemImage: "person.2")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            recordButton
        }
        .fullScreenCover(item: $recordingMeeting) { meeting in
            RecordingView(meeting: meeting) { outcome in
                recordingMeeting = nil
                if case .saved = outcome {
                    selection = meeting.id
                }
                MeetingActions.finishRecording(meeting, outcome: outcome, in: modelContext, processor: processor)
            }
        }
        .sheet(isPresented: $showingSpeakers) {
            NavigationStack {
                SpeakersView()
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
            }
        }
        .alert("Mikrofon izni gerekli", isPresented: $showingPermissionAlert) {
            Button("Ayarları Aç") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Toplantıları kaydedebilmek için Ayarlar'dan EarToNote'a mikrofon izni verin.")
        }
        .confirmationDialog("Toplantı silinsin mi?", isPresented: isConfirmingDeletion, titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                deletePendingMeeting()
            }
            Button("Vazgeç", role: .cancel) {
                pendingDeletionID = nil
            }
        } message: {
            Text("Ses kaydı ve metin kalıcı olarak silinir. Kayıtlı kişiler korunur.")
        }
    }

    private var filteredMeetings: [Meeting] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return meetings }
        return meetings.filter { meeting in
            meeting.title.localizedStandardContains(query)
                || meeting.participants.contains { $0.displayName.localizedStandardContains(query) }
                || meeting.segments.contains { $0.text.localizedStandardContains(query) }
        }
    }

    private var recordButton: some View {
        Button {
            Task {
                await startRecording()
            }
        } label: {
            Label("Kayıt Başlat", systemImage: "record.circle")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(.red)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var isConfirmingDeletion: Binding<Bool> {
        Binding(
            get: { pendingDeletionID != nil },
            set: { if !$0 { pendingDeletionID = nil } }
        )
    }

    private func startRecording() async {
        guard await AudioRecorder.requestPermission() else {
            showingPermissionAlert = true
            return
        }
        recordingMeeting = MeetingActions.startNewMeeting(in: modelContext)
    }

    private func deletePendingMeeting() {
        guard let id = pendingDeletionID, let meeting = meetings.first(where: { $0.id == id }) else { return }
        pendingDeletionID = nil
        if selection == id {
            selection = nil
        }
        MeetingActions.delete(meeting, in: modelContext, processor: processor)
    }
}
