import Foundation

struct SavedDigest {
    let text: String
    let savedAt: Date
}

enum DigestStorage {
    static func save(_ text: String, for bookID: String, savedAt: Date) {
        let defaults = UserDefaults.standard
        defaults.set(text, forKey: textKey(for: bookID))
        defaults.set(savedAt, forKey: dateKey(for: bookID))
    }

    static func load(for bookID: String) -> SavedDigest? {
        let defaults = UserDefaults.standard

        guard let text = defaults.string(forKey: textKey(for: bookID)),
              let savedAt = defaults.object(forKey: dateKey(for: bookID)) as? Date else {
            return nil
        }

        return SavedDigest(text: text, savedAt: savedAt)
    }

    static func hasDigest(for bookID: String) -> Bool {
        load(for: bookID) != nil
    }

    private static func textKey(for bookID: String) -> String {
        "digest.text.\(bookID)"
    }

    private static func dateKey(for bookID: String) -> String {
        "digest.date.\(bookID)"
    }
}
