import SwiftUI

@MainActor
final class BookStore: ObservableObject {
    @Published private(set) var userBooks: [Book] = []

    var allBooks: [Book] {
        Book.catalog + userBooks
    }

    init() {
        userBooks = Self.loadPersistedBooks()
    }

    func addBook(_ book: Book) {
        guard !allBooks.contains(where: { $0.id == book.id }) else { return }
        userBooks.append(book)
        persist()
    }

    func removeUserBook(id: String) {
        userBooks.removeAll { $0.id == id }
        persist()
    }

    func book(withID id: String) -> Book? {
        allBooks.first { $0.id == id }
    }

    // MARK: - Persistence

    private func persist() {
        let persisted = userBooks.map(PersistedBook.init)
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: Self.storeURL, options: .atomic)
    }

    static func loadPersistedBooksList() -> [Book] {
        loadPersistedBooks()
    }

    private static func loadPersistedBooks() -> [Book] {
        guard let data = try? Data(contentsOf: storeURL),
              let persisted = try? JSONDecoder().decode([PersistedBook].self, from: data) else {
            return []
        }
        return persisted.compactMap { $0.toBook() }
    }

    private static var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BookDigest", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("user-books.json")
    }
}

private struct PersistedBook: Codable {
    let id: String
    let title: String
    let shortTitle: String
    let author: String
    let angle: String
    let category: String
    let keywords: [String]
    let coverColors: [[Double]]

    init(_ book: Book) {
        id = book.id
        title = book.title
        shortTitle = book.shortTitle
        author = book.author
        angle = book.angle
        category = book.category.rawValue
        keywords = book.keywords
        coverColors = book.coverColors.map { color in
            let uiColor = UIColor(color)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
            uiColor.getRed(&r, green: &g, blue: &b, alpha: nil)
            return [Double(r), Double(g), Double(b)]
        }
    }

    func toBook() -> Book? {
        guard let cat = BookCategory(rawValue: category) else { return nil }
        let colors = coverColors.compactMap { components -> Color? in
            guard components.count >= 3 else { return nil }
            return Color(red: components[0], green: components[1], blue: components[2])
        }
        return Book(
            id: id, title: title, shortTitle: shortTitle,
            author: author, angle: angle, category: cat,
            keywords: keywords, coverColors: colors
        )
    }
}
