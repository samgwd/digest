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
    private let backend: SupabaseService

    init(settings: AppSettings, backend: SupabaseService) {
        self.settings = settings
        self.backend = backend
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
        let bookID = book.id
        let backend = backend

        tasks[book.id] = Task { [weak self] in
            do {
                // Someone may have generated this digest already — sharing it
                // is the whole point, so check before asking for generation.
                if let existing = try await backend.fetchDigest(bookID: bookID),
                   existing.status == .ready,
                   let text = existing.digestText, !text.isEmpty {
                    try Task.checkCancellation()
                    let savedAt = existing.updatedAtDate
                    DigestStorage.save(text, for: bookID, savedAt: savedAt)
                    self?.statuses[bookID] = .completed(savedAt: savedAt)
                    self?.finish(for: bookID)
                    return
                }

                try await backend.requestDigestGeneration(book: book, openAIKey: apiKey)
                let row = try await backend.waitForDigest(book: book, openAIKey: apiKey)
                try Task.checkCancellation()

                guard let text = row.digestText, !text.isEmpty else {
                    throw SupabaseService.ServiceError.generationFailed("The digest came back empty.")
                }

                let savedAt = row.updatedAtDate
                DigestStorage.save(text, for: bookID, savedAt: savedAt)
                self?.statuses[bookID] = .completed(savedAt: savedAt)
                self?.finish(for: bookID)
            } catch is CancellationError {
                self?.statuses[bookID] = .idle
                self?.finish(for: bookID)
            } catch {
                self?.statuses[bookID] = .failed(message: error.localizedDescription)
                self?.finish(for: bookID)
            }
        }
    }

    // Passive discovery: pulls a shared digest into local storage without
    // requiring the user to press Generate (or have any API key).
    func fetchRemoteDigestIfAvailable(for book: Book) async -> Bool {
        guard !isGenerating(book.id), !DigestStorage.hasDigest(for: book.id) else {
            return false
        }

        guard let row = try? await backend.fetchDigest(bookID: book.id),
              row.status == .ready,
              let text = row.digestText, !text.isEmpty else {
            return false
        }

        DigestStorage.save(text, for: book.id, savedAt: row.updatedAtDate)
        return true
    }

    // Reattach to a generation that's already running server-side — one this
    // device started before a relaunch, or another reader's. Re-requesting is
    // safe: a live claim returns 'in_progress', and only a dead claim starts a
    // fresh generation.
    func resumeIfRemoteGenerating(for book: Book) async {
        guard !isGenerating(book.id), !DigestStorage.hasDigest(for: book.id) else { return }
        // Restarting after a dead claim needs a key, so don't auto-resume without one.
        guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let row = try? await backend.fetchDigest(bookID: book.id),
              row.status == .generating else { return }
        generate(for: book)
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
