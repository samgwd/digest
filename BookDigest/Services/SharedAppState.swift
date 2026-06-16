import Foundation

@MainActor
final class SharedAppState {
    static let shared = SharedAppState()

    var settings: AppSettings!
    var speechController: SpeechController!
    var bookStore: BookStore!

    private init() {}
}
