import SwiftUI

@main
struct BookDigestApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var speechController: SpeechController
    @StateObject private var bookStore: BookStore
    @StateObject private var digestGenerator: DigestGenerator
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let settings = AppSettings()
        let speechController = SpeechController()
        let bookStore = BookStore()
        let digestGenerator = DigestGenerator(settings: settings)
        _settings = StateObject(wrappedValue: settings)
        _speechController = StateObject(wrappedValue: speechController)
        _bookStore = StateObject(wrappedValue: bookStore)
        _digestGenerator = StateObject(wrappedValue: digestGenerator)

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
                .environmentObject(digestGenerator)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                speechController.savePlaybackPosition()
            }
        }
    }
}
