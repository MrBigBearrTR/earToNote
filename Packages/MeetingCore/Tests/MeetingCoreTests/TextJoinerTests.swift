import XCTest
@testable import MeetingCore

final class TextJoinerTests: XCTestCase {
    func testInsertsSpacesBetweenBareWords() {
        XCTAssertEqual(TextJoiner.join(["Bugün", "hava", "güzel"]), "Bugün hava güzel")
    }

    func testKeepsTokensThatAlreadyContainSpaces() {
        XCTAssertEqual(TextJoiner.join(["Bugün ", "hava ", "güzel"]), "Bugün hava güzel")
        XCTAssertEqual(TextJoiner.join(["Bugün", " hava", " güzel"]), "Bugün hava güzel")
    }

    func testPunctuationAttachesToPreviousWord() {
        XCTAssertEqual(TextJoiner.join(["Evet", ",", "tamam", "."]), "Evet, tamam.")
        XCTAssertEqual(TextJoiner.join(["Ali", "'nin", "raporu", "?"]), "Ali'nin raporu?")
    }

    func testOpeningBracketAttachesToNextWord() {
        XCTAssertEqual(TextJoiner.join(["bütçe", "(", "taslak", ")"]), "bütçe (taslak)")
    }

    func testCollapsesRepeatedWhitespace() {
        XCTAssertEqual(TextJoiner.join(["  bir  ", "  iki "]), "bir iki")
        XCTAssertEqual(TextJoiner.join([String]()), "")
    }
}
