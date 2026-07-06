import Foundation

// Strips markdown so digest text is safe for direct TTS playback. Server
// digests arrive pre-sanitized (supabase/functions/_shared/sanitize.ts is a
// port of this); this remains for digests generated before the backend
// existed. Keep the two implementations in sync.
enum DigestTextSanitizer {
    static func sanitize(_ text: String) -> String {
        var sanitized = text.replacingOccurrences(of: "\r\n", with: "\n")
        sanitized = replaceMarkdownLinks(in: sanitized)

        let lines = sanitized.components(separatedBy: .newlines).map { line in
            var cleaned = line.trimmingCharacters(in: .whitespaces)

            cleaned = cleaned.replacingOccurrences(
                of: #"^#{1,6}\s*"#,
                with: "",
                options: .regularExpression
            )
            cleaned = cleaned.replacingOccurrences(
                of: #"^[-*+]\s+"#,
                with: "",
                options: .regularExpression
            )
            cleaned = cleaned.replacingOccurrences(
                of: #"^\d+[.)]\s+"#,
                with: "",
                options: .regularExpression
            )
            cleaned = cleaned.replacingOccurrences(
                of: #"^>\s*"#,
                with: "",
                options: .regularExpression
            )

            cleaned = cleaned.replacingOccurrences(of: #"[*_`~]+"#, with: "", options: .regularExpression)

            return cleaned.trimmingCharacters(in: .whitespaces)
        }

        sanitized = lines.joined(separator: "\n")
        sanitized = sanitized.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)

        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replaceMarkdownLinks(in text: String) -> String {
        let pattern = #"!?\[([^\]]+)\]\([^)]+\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "$1")
    }
}
