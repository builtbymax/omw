/// Tiny search scorer for the overlay: every query word has to match the text somehow.
public enum Fuzzy {
    /// Higher is better, nil means no match. An empty query matches everything with 0.
    public static func score(_ query: String, in text: String) -> Int? {
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace)
        let haystack = text.lowercased()
        let words = haystack.split { !$0.isLetter && !$0.isNumber }
        var total = 0
        for token in tokens {
            if words.contains(where: { $0.hasPrefix(token) }) {
                total += 3
            } else if haystack.contains(token) {
                total += 2
            } else if isSubsequence(token, of: haystack) {
                total += 1
            } else {
                return nil
            }
        }
        return total
    }

    private static func isSubsequence(_ needle: Substring, of haystack: String) -> Bool {
        var remaining = needle[...]
        for char in haystack where char == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }
}
