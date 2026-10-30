import SwiftData
import SwiftUI

/// Sidebar + detail on iPad; collapses to a navigation stack on iPhone.
struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(MeetingProcessor.self) private var processor
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]
    @State private var selection: UUID?

    var body: some View {
        NavigationSplitView {
            MeetingListView(selection: $selection)
        } detail: {
            if let meeting = meetings.first(where: { $0.id == selection }) {
                MeetingDetailView(meeting: meeting) {
                    selection = nil
                }
                .id(meeting.id)
            } else {
                ContentUnavailableView(
                    "Toplantı seçin",
                    systemImage: "waveform",
                    description: Text("Yeni bir kayıt başlatın veya listeden bir toplantı seçin.")
                )
            }
        }
        .task {
            processor.recoverInterruptedMeetings(in: modelContext)
        }
    }
}
