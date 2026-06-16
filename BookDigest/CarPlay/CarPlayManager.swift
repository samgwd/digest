import CarPlay
import UIKit

@MainActor
final class CarPlayManager {
    private let interfaceController: CPInterfaceController

    init(interfaceController: CPInterfaceController) {
        self.interfaceController = interfaceController
    }

    func configure() {
        let browseTab = makeBrowseTab()
        let nowPlayingTab = CPNowPlayingTemplate.shared
        nowPlayingTab.tabTitle = "Now Playing"
        nowPlayingTab.tabImage = UIImage(systemName: "waveform") ?? UIImage()

        let tabBar = CPTabBarTemplate(templates: [browseTab, nowPlayingTab])
        interfaceController.setRootTemplate(tabBar, animated: true, completion: nil)
    }

    private func makeBrowseTab() -> CPListTemplate {
        let items = BookCategory.allCases.map { category -> CPListItem in
            let item = CPListItem(
                text: category.title,
                detailText: category.subtitle,
                image: UIImage(systemName: category.systemImage)
            )
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                self?.showBooks(for: category)
                completion()
            }
            return item
        }

        let section = CPListSection(items: items)
        let template = CPListTemplate(title: "Library", sections: [section])
        template.tabTitle = "Library"
        template.tabImage = UIImage(systemName: "books.vertical") ?? UIImage()
        return template
    }

    private func showBooks(for category: BookCategory) {
        let appState = SharedAppState.shared
        let allBooks = appState.bookStore.allBooks
        let booksInCategory = allBooks.filter { $0.category == category }
        let playableBooks = booksInCategory.filter { DigestStorage.hasDigest(for: $0.id) }

        let items: [CPListItem]

        if appState.settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let item = CPListItem(text: "API Key Required", detailText: "Set up your OpenAI key in the Digest app")
            item.isEnabled = false
            items = [item]
        } else if playableBooks.isEmpty {
            let item = CPListItem(text: "No Digests Available", detailText: "Generate digests in the Digest app first")
            item.isEnabled = false
            items = [item]
        } else {
            items = playableBooks.map { book -> CPListItem in
                let isPlaying = appState.speechController.currentBookID == book.id
                let detailText = isPlaying ? "Now Playing" : book.author

                let item = CPListItem(text: book.shortTitle, detailText: detailText)
                item.isPlaying = isPlaying
                item.handler = { [weak self] _, completion in
                    self?.playBook(book)
                    completion()
                }
                return item
            }
        }

        let section = CPListSection(items: items)
        let template = CPListTemplate(title: category.title, sections: [section])
        interfaceController.pushTemplate(template, animated: true, completion: nil)
    }

    private func playBook(_ book: Book) {
        guard let digest = DigestStorage.load(for: book.id) else { return }

        let appState = SharedAppState.shared
        let settings = appState.settings!
        let speech = appState.speechController!

        if speech.currentBookID == book.id {
            if speech.isPaused {
                speech.continueSpeaking()
            }
        } else {
            speech.speak(
                digest.text,
                bookID: book.id,
                title: book.title,
                apiKey: settings.apiKey,
                model: settings.speechModel,
                voice: settings.speechVoice
            )
        }

        let nowPlaying = CPNowPlayingTemplate.shared
        interfaceController.pushTemplate(nowPlaying, animated: true, completion: nil)
    }
}
