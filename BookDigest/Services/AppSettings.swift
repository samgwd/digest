import Foundation

final class AppSettings: ObservableObject {
    @Published var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: apiKeyStorageKey)
        }
    }

    // Set by the app, not user-configurable.
    let model = "gpt-5.4"

    @Published var elevenLabsAPIKey: String {
        didSet {
            UserDefaults.standard.set(elevenLabsAPIKey, forKey: elevenLabsAPIKeyStorageKey)
        }
    }

    @Published var speechVoice: String {
        didSet {
            UserDefaults.standard.set(speechVoice, forKey: speechVoiceStorageKey)
        }
    }

    let speechModel = "eleven_flash_v2_5"

    private let apiKeyStorageKey = "openai.apiKey"
    private let elevenLabsAPIKeyStorageKey = "elevenLabs.apiKey"
    private let speechVoiceStorageKey = "elevenLabs.speechVoice"

    init() {
        apiKey = UserDefaults.standard.string(forKey: apiKeyStorageKey) ?? ""
        elevenLabsAPIKey = UserDefaults.standard.string(forKey: elevenLabsAPIKeyStorageKey) ?? ""
        speechVoice = UserDefaults.standard.string(forKey: speechVoiceStorageKey) ?? "lUTamkMw7gOzZbFIwmq4"
    }
}
