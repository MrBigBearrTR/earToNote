import XCTest
@testable import MeetingCore

final class TranscriptFormatterTests: XCTestCase {
    private let metadata = ExportMetadata(title: "Haftalık Toplantı", dateText: "31 Ekim 2026 10:00", duration: 3_725)
    private let segments = [
        ExportSegment(start: 3, speaker: "Ali", text: "Günaydın, başlayalım."),
        ExportSegment(start: 83.6, speaker: "Konuşmacı 2", text: "Bütçe hazır."),
        ExportSegment(start: 3_661, speaker: "Ali", text: "Teşekkürler."),
    ]

    func testTimestamp() {
        XCTAssertEqual(TranscriptFormatter.timestamp(0), "00:00:00")
        XCTAssertEqual(TranscriptFormatter.timestamp(83.9), "00:01:23")
        XCTAssertEqual(TranscriptFormatter.timestamp(3_661), "01:01:01")
        XCTAssertEqual(TranscriptFormatter.timestamp(-5), "00:00:00")
        XCTAssertEqual(TranscriptFormatter.timestamp(.infinity), "00:00:00")
    }

    func testDurationText() {
        XCTAssertEqual(TranscriptFormatter.durationText(45), "45 sn")
        XCTAssertEqual(TranscriptFormatter.durationText(120), "2 dk")
        XCTAssertEqual(TranscriptFormatter.durationText(723), "12 dk 3 sn")
        XCTAssertEqual(TranscriptFormatter.durationText(3_725), "1 sa 2 dk")
    }

    func testParticipantsInOrderOfFirstAppearance() {
        XCTAssertEqual(TranscriptFormatter.participants(in: segments), ["Ali", "Konuşmacı 2"])
    }

    func testPlainText() {
        let expected = """
        Haftalık Toplantı
        Tarih: 31 Ekim 2026 10:00
        Süre: 1 sa 2 dk
        Katılımcılar: Ali, Konuşmacı 2

        [00:00:03] Ali: Günaydın, başlayalım.
        [00:01:23] Konuşmacı 2: Bütçe hazır.
        [01:01:01] Ali: Teşekkürler.
        """

        XCTAssertEqual(TranscriptFormatter.plainText(metadata: metadata, segments: segments), expected)
    }

    func testMarkdown() {
        let markdown = TranscriptFormatter.markdown(metadata: metadata, segments: segments)

        XCTAssertTrue(markdown.hasPrefix("# Haftalık Toplantı\n"))
        XCTAssertTrue(markdown.contains("- **Katılımcılar:** Ali, Konuşmacı 2"))
        XCTAssertTrue(markdown.contains("**Konuşmacı 2** `00:01:23`  \nBütçe hazır."))
        XCTAssertTrue(markdown.hasSuffix("Teşekkürler.\n"))
    }

    func testEmptyTranscriptHasNoParticipantsLine() {
        let text = TranscriptFormatter.plainText(metadata: metadata, segments: [])

        XCTAssertFalse(text.contains("Katılımcılar"))
    }
}
