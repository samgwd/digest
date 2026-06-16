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

    @Published var speechModel: String {
        didSet {
            UserDefaults.standard.set(speechModel, forKey: speechModelStorageKey)
        }
    }

    @Published var speechVoice: String {
        didSet {
            UserDefaults.standard.set(speechVoice, forKey: speechVoiceStorageKey)
        }
    }

    private let apiKeyStorageKey = "openai.apiKey"
    private let modelStorageKey = "openai.model"
    private let speechModelStorageKey = "openai.speechModel"
    private let speechVoiceStorageKey = "openai.speechVoice"

    init() {
        apiKey = UserDefaults.standard.string(forKey: apiKeyStorageKey) ?? ""
        model = UserDefaults.standard.string(forKey: modelStorageKey) ?? "gpt-5.4"
        speechModel = UserDefaults.standard.string(forKey: speechModelStorageKey) ?? "gpt-4o-mini-tts"
        speechVoice = UserDefaults.standard.string(forKey: speechVoiceStorageKey) ?? "marin"
    }
}
