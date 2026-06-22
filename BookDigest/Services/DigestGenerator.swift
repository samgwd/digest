import SwiftUI
import UIKit

@MainActor
final class DigestGenerator: ObservableObject {
    enum Status: Equatable {
        case idle
        case generating(startedAt: Date)
        case completed(savedAt: Date)
        case failed(message: String)
    }

    @Published private(set) var statuses: [String: Status] = [:]

    private var tasks: [String: Task<Void, Never>] = [:]
    private var backgroundTaskIDs: [String: UIBackgroundTaskIdentifier] = [:]
    private unowned let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func status(for bookID: String) -> Status {
        statuses[bookID] ?? .idle
    }

    func isGenerating(_ bookID: String) -> Bool {
        if case .generating = status(for: bookID) { return true }
        return false
    }

    func generate(for book: Book) {
        guard !isGenerating(book.id) else { return }
        let startedAt = Date()
        statuses[book.id] = .generating(startedAt: startedAt)
        beginBackgroundTask(for: book.id)

        let apiKey = settings.apiKey
        let model = settings.model
        let bookID = book.id

        tasks[book.id] = Task { [weak self] in
            let client = OpenAIClient(apiKey: apiKey, model: model)
            do {
                let raw = try await client.generateDigest(for: book)
                try Task.checkCancellation()
                let sanitized = DigestTextSanitizer.sanitize(raw)
                let savedAt = Date()
                DigestStorage.save(sanitized, for: bookID, savedAt: savedAt)
                await MainActor.run {
                    guard let self else { return }
                    self.statuses[bookID] = .completed(savedAt: savedAt)
                    self.finish(for: bookID)
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.statuses[bookID] = .idle
                    self?.finish(for: bookID)
                }
            } catch {
                await MainActor.run {
                    self?.statuses[bookID] = .failed(message: error.localizedDescription)
                    self?.finish(for: bookID)
                }
            }
        }
    }

    func acknowledgeCompletion(for bookID: String) {
        if case .completed = statuses[bookID] {
            statuses[bookID] = .idle
        }
    }

    private func finish(for bookID: String) {
        tasks[bookID] = nil
        endBackgroundTask(for: bookID)
    }

    private func beginBackgroundTask(for bookID: String) {
        let id = UIApplication.shared.beginBackgroundTask(withName: "DigestGen-\(bookID)") { [weak self] in
            Task { @MainActor in
                self?.tasks[bookID]?.cancel()
                self?.endBackgroundTask(for: bookID)
            }
        }
        backgroundTaskIDs[bookID] = id
    }

    private func endBackgroundTask(for bookID: String) {
        if let id = backgroundTaskIDs[bookID], id != .invalid {
            UIApplication.shared.endBackgroundTask(id)
        }
        backgroundTaskIDs[bookID] = nil
    }
}
