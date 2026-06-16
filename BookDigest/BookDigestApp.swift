import SwiftUI

@main
struct BookDigestApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var speechController: SpeechController
    @StateObject private var bookStore: BookStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let settings = AppSettings()
        let speechController = SpeechController()
        let bookStore = BookStore()
        _settings = StateObject(wrappedValue: settings)
        _speechController = StateObject(wrappedValue: speechController)
        _bookStore = StateObject(wrappedValue: bookStore)

        let shared = SharedAppState.shared
        shared.settings = settings
        shared.speechController = speechController
        shared.bookStore = bookStore
    }

    var body: some Scene {
        WindowGroup {
            AppView()
                .environmentObject(settings)
                .environmentObject(speechController)
                .environmentObject(bookStore)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                speechController.savePlaybackPosition()
            }
        }
    }
}
