import Foundation

/// Joins recognizer tokens into readable text. Tokens may or may not carry their own surrounding
/// whitespace, so a space is only inserted when neither side already provides one and the next
/// token is not punctuation that attaches to the previous word.
public enum TextJoiner {
    private static let attachesToPrevious: Set<Character> = [
        ".", ",", "!", "?", ";", ":", "…", ")", "]", "}", "%", "»", "”", "'", "’",
    ]
    private static let attachesToNext: Set<Character> = ["(", "[", "{", "«", "“"]

    public static func join<S: Sequence>(_ tokens: S) -> String where S.Element == String {
        var result = ""
        for token in tokens where !token.isEmpty {
            guard let last = result.last, let first = token.first else {
                result += token
                continue
            }
            let needsSpace = !last.isWhitespace
                && !first.isWhitespace
                && !attachesToPrevious.contains(first)
                && !attachesToNext.contains(last)
            if needsSpace {
                result += " "
            }
            result += token
        }
        return normalizeWhitespace(result)
    }

    public static func normalizeWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
