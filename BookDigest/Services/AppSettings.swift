import Foundation

final class AppSettings: ObservableObject {
    @Published var apiKey: String {
        didSet {
            UserDefaults.standard.set(apiKey, forKey: apiKeyStorageKey)
        }
    }

    @Published var model: String {
        didSet {
            UserDefaults.standard.set(model, forKey: modelStorageKey)
        }
    }

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
    private let modelStorageKey = "openai.model"
    private let elevenLabsAPIKeyStorageKey = "elevenLabs.apiKey"
    private let speechVoiceStorageKey = "elevenLabs.speechVoice"

    init() {
        apiKey = UserDefaults.standard.string(forKey: apiKeyStorageKey) ?? ""
        model = UserDefaults.standard.string(forKey: modelStorageKey) ?? "gpt-5.4"
        elevenLabsAPIKey = UserDefaults.standard.string(forKey: elevenLabsAPIKeyStorageKey) ?? ""
        speechVoice = UserDefaults.standard.string(forKey: speechVoiceStorageKey) ?? "lUTamkMw7gOzZbFIwmq4"
    }
}
