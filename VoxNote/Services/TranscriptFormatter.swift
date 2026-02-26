import Foundation

enum TranscriptFormatter {
    /// Inserts line breaks after sentence-ending punctuation for readability.
    /// Handles English (`. ! ?` followed by space) and CJK (`。 ！ ？`).
    static func applyLineBreaks(to text: String) -> String {
        guard !text.isEmpty else { return text }

        var result = text

        // English: sentence-ending punctuation followed by a space → punctuation + newline
        // Match `. `, `! `, `? ` (but not inside abbreviations like "U.S. ")
        result = result.replacingOccurrences(
            of: "([.!?])\\s+",
            with: "$1\n",
            options: .regularExpression
        )

        // CJK: sentence-ending punctuation → punctuation + newline (if not already followed by newline)
        result = result.replacingOccurrences(
            of: "([。！？])(?!\n)",
            with: "$1\n",
            options: .regularExpression
        )

        // Collapse multiple consecutive newlines into a single newline
        result = result.replacingOccurrences(
            of: "\n{2,}",
            with: "\n",
            options: .regularExpression
        )

        return result
    }

    /// Splits text into sentences at English (.!?) and CJK (。！？) punctuation boundaries.
    /// Returns an array of trimmed, non-empty sentence strings.
    static func splitIntoSentences(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        // Use a record separator as delimiter to split
        let delimited = text
            .replacingOccurrences(of: "([.!?])\\s+", with: "$1\u{1E}", options: .regularExpression)
            .replacingOccurrences(of: "([。！？])", with: "$1\u{1E}", options: .regularExpression)

        return delimited
            .components(separatedBy: "\u{1E}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
