import Foundation

enum TextSanitizer {
    static func sanitizedResearchText(_ s: String) -> String {
        var t = s
        let patterns = [
            #"contentReference\[.*?\]\{.*?\}"#,
            #"\[image [^\]]*\]"#,
            #"contentReference\[.*?\]"#,
            #"\{index=\d+\}"#
        ]
        for p in patterns {
            if let r = try? NSRegularExpression(pattern: p, options: [.dotMatchesLineSeparators]) {
                t = r.stringByReplacingMatches(in: t, options: [], range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "")
            }
        }
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func firstSentence(from s: String) -> String {
        let clean = sanitizedResearchText(s)
        if let idx = clean.firstIndex(of: ".") {
            return String(clean[..<idx])
        }
        return clean
    }
}

