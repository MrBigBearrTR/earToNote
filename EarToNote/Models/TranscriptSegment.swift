import Foundation
import SwiftData

@Model
final class TranscriptSegment {
    var index: Int
    var start: Double
    var end: Double
    var text: String

    var meeting: Meeting?
    var participant: MeetingParticipant?

    init(index: Int, start: Double, end: Double, text: String) {
        self.index = index
        self.start = start
        self.end = end
        self.text = text
    }

    var speakerName: String {
        participant?.displayName ?? "Bilinmeyen konuşmacı"
    }
}
