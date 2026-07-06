import Foundation

/// Supabase connection details.
///
/// Values are injected at build time from `Config/Secrets.xcconfig` (gitignored)
/// via Info.plist substitution. Copy `Config/Secrets.example.xcconfig` to
/// `Config/Secrets.xcconfig` and fill in your project's values.
enum SupabaseConfig {
    static let url: URL = {
        guard let host = infoValue("SUPABASE_HOST"),
              let url = URL(string: "https://\(host)") else {
            fatalError("Missing SUPABASE_HOST. Create Config/Secrets.xcconfig from Config/Secrets.example.xcconfig.")
        }
        return url
    }()

    static let publishableKey: String = {
        guard let key = infoValue("SUPABASE_PUBLISHABLE_KEY") else {
            fatalError("Missing SUPABASE_PUBLISHABLE_KEY. Create Config/Secrets.xcconfig from Config/Secrets.example.xcconfig.")
        }
        return key
    }()

    private static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
