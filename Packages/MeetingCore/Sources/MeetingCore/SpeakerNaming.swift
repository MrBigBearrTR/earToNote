import Foundation

public enum SpeakerNaming {
    public static func defaultName(number: Int) -> String {
        "Konuşmacı \(number)"
    }

    /// Next free speaker number. Numbers are global across meetings so that the same person keeps
    /// the same "Konuşmacı N" label everywhere until the user gives them a real name.
    public static func nextNumber(existing: [Int]) -> Int {
        (existing.max() ?? 0) + 1
    }

    /// Trims the name typed by the user; returns `nil` when nothing meaningful is left.
    public static func cleanedName(_ raw: String) -> String? {
        let cleaned = TextJoiner.normalizeWhitespace(raw)
        return cleaned.isEmpty ? nil : cleaned
    }
}
