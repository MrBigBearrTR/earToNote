import SwiftData
import SwiftUI

@main
struct EarToNoteApp: App {
    @State private var processor = MeetingProcessor()
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: Meeting.self, MeetingParticipant.self, TranscriptSegment.self, SpeakerProfile.self
            )
        } catch {
            fatalError("Veritabanı açılamadı: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(processor)
        }
        .modelContainer(container)
    }
}
