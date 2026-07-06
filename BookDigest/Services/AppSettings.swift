import Foundation

// API keys are sent per-request to the shared generation service (a Supabase
// edge function) and never stored server-side. Voice and language model are
// fixed server-side so every user shares one digest and one audio file per
// book.
final class AppSettings: ObservableObject {
    @Published var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: apiKeyStorageKey)
        }
    }

    @Published var elevenLabsAPIKey: String {
        didSet {
            UserDefaults.standard.set(elevenLabsAPIKey, forKey: elevenLabsAPIKeyStorageKey)
        }
    }

    private let apiKeyStorageKey = "openai.apiKey"
    private let elevenLabsAPIKeyStorageKey = "elevenLabs.apiKey"

    init() {
        apiKey = UserDefaults.standard.string(forKey: apiKeyStorageKey) ?? ""
        elevenLabsAPIKey = UserDefaults.standard.string(forKey: elevenLabsAPIKeyStorageKey) ?? ""
    }
}
