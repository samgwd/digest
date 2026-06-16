import SwiftUI
import UIKit

enum CoverArtMetrics {
    static let cornerRadius: CGFloat = 18
    static let aspectRatio: CGFloat = 0.68

    static func height(forWidth width: CGFloat) -> CGFloat {
        width / aspectRatio
    }
}

struct CoverArtView: View {
    let book: Book

    @StateObject private var loader: BookCoverLoader

    init(book: Book) {
        self.book = book
        _loader = StateObject(wrappedValue: BookCoverLoader(book: book))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = loader.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    fallbackCover
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: CoverArtMetrics.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CoverArtMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            }
        }
        .clipped()
        .task {
            loader.loadIfNeeded()
        }
    }

    private var fallbackCover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: CoverArtMetrics.cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            EditorialTheme.paperHighlight,
                            EditorialTheme.paper
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            book.coverColors.first?.opacity(0.10) ?? EditorialTheme.accent.opacity(0.10),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 12) {
                Text(book.shortTitle)
                    .font(EditorialTheme.displayFont(size: 26))
                    .foregroundStyle(EditorialTheme.ink)
                    .lineLimit(4)
                    .minimumScaleFactor(0.7)

                EditorialDivider()

                Text(book.author)
                    .font(EditorialTheme.detailFont(size: 14))
                    .foregroundStyle(EditorialTheme.mutedInk)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(18)
        }
    }
}

@MainActor
final class BookCoverLoader: ObservableObject {
    @Published var image: UIImage?

    private let book: Book

    init(book: Book) {
        self.book = book
    }

    func loadIfNeeded() {
        guard image == nil else {
            return
        }

        Task { [book] in
            image = await BookCoverService.shared.image(for: book)
        }
    }
}

@MainActor
final class BookCoverService {
    static let shared = BookCoverService()

    private var memoryCache: [String: UIImage] = [:]
    private var inflight: [String: Task<UIImage?, Never>] = [:]

    private init() {}

    func image(for book: Book) async -> UIImage? {
        if let image = memoryCache[book.id] {
            return image
        }

        if let bundled = UIImage(named: book.coverImageName) {
            memoryCache[book.id] = bundled
            return bundled
        }

        if let cached = cachedImage(for: book) {
            memoryCache[book.id] = cached
            return cached
        }

        if let task = inflight[book.id] {
            return await task.value
        }

        let task = Task<UIImage?, Never> { [book] in
            await self.fetchAndPersistImage(for: book)
        }
        inflight[book.id] = task

        let image = await task.value
        inflight[book.id] = nil

        if let image {
            memoryCache[book.id] = image
        }

        return image
    }

    private func cachedImage(for book: Book) -> UIImage? {
        let url = cacheURL(for: book)
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }

        return image
    }

    private func fetchAndPersistImage(for book: Book) async -> UIImage? {
        guard let remoteURL = await resolveRemoteURL(for: book) else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: remoteURL)
            guard let image = UIImage(data: data) else {
                return nil
            }

            let cacheDirectory = coverCacheDirectory()
            try? FileManager.default.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            try? data.write(to: cacheURL(for: book), options: .atomic)
            return image
        } catch {
            return nil
        }
    }

    private func resolveRemoteURL(for book: Book) async -> URL? {
        if let googleURL = await googleBooksURL(for: book) {
            return googleURL
        }

        return await openLibraryURL(for: book)
    }

    private func googleBooksURL(for book: Book) async -> URL? {
        let authorFragment = book.author.components(separatedBy: " and ").first ?? book.author
        var components = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")
        components?.queryItems = [
            URLQueryItem(name: "q", value: "intitle:\"\(book.title)\" inauthor:\"\(authorFragment)\""),
            URLQueryItem(name: "printType", value: "books"),
            URLQueryItem(name: "projection", value: "lite"),
            URLQueryItem(name: "maxResults", value: "5")
        ]

        guard let url = components?.url else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(GoogleBooksResponse.self, from: data)
            let bestMatch = response.items?
                .compactMap(\.volumeInfo)
                .max(by: { matchScore(for: book, candidate: $0) < matchScore(for: book, candidate: $1) })

            guard let imageLinks = bestMatch?.imageLinks else {
                return nil
            }

            let rawURL = imageLinks.extraLarge ??
                imageLinks.large ??
                imageLinks.medium ??
                imageLinks.small ??
                imageLinks.thumbnail ??
                imageLinks.smallThumbnail

            guard let rawURL else {
                return nil
            }

            let sanitized = rawURL
                .replacingOccurrences(of: "http://", with: "https://")
                .replacingOccurrences(of: "&edge=curl", with: "")
                .replacingOccurrences(of: "zoom=1", with: "zoom=2")

            if sanitized.contains("zoom=") {
                return URL(string: sanitized)
            }

            let suffix = sanitized.contains("?") ? "&zoom=2" : "?zoom=2"
            return URL(string: sanitized + suffix)
        } catch {
            return nil
        }
    }

    private func openLibraryURL(for book: Book) async -> URL? {
        var components = URLComponents(string: "https://openlibrary.org/search.json")
        components?.queryItems = [
            URLQueryItem(name: "title", value: book.title),
            URLQueryItem(name: "author", value: book.author),
            URLQueryItem(name: "limit", value: "5")
        ]

        guard let url = components?.url else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(OpenLibrarySearchResponse.self, from: data)
            let bestMatch = response.docs.max(by: { matchScore(for: book, candidate: $0) < matchScore(for: book, candidate: $1) })

            guard let coverID = bestMatch?.coverID else {
                return nil
            }

            return URL(string: "https://covers.openlibrary.org/b/id/\(coverID)-L.jpg?default=false")
        } catch {
            return nil
        }
    }

    private func matchScore(for book: Book, candidate: GoogleBookVolumeInfo) -> Double {
        matchScore(
            title: book.title,
            author: book.author,
            candidateTitle: candidate.title ?? "",
            candidateAuthor: candidate.authors?.joined(separator: " ") ?? ""
        )
    }

    private func matchScore(for book: Book, candidate: OpenLibraryDoc) -> Double {
        matchScore(
            title: book.title,
            author: book.author,
            candidateTitle: candidate.title ?? "",
            candidateAuthor: (candidate.authorNames ?? []).joined(separator: " ")
        )
    }

    private func matchScore(title: String, author: String, candidateTitle: String, candidateAuthor: String) -> Double {
        let titleScore = tokenOverlap(normalize(title), normalize(candidateTitle))
        let authorScore = tokenOverlap(normalize(author), normalize(candidateAuthor))
        return (titleScore * 0.8) + (authorScore * 0.2)
    }

    private func normalize(_ text: String) -> [String] {
        text
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    private func tokenOverlap(_ lhs: [String], _ rhs: [String]) -> Double {
        let left = Set(lhs)
        let right = Set(rhs)
        guard !left.isEmpty else {
            return 0
        }

        return Double(left.intersection(right).count) / Double(left.count)
    }

    private func coverCacheDirectory() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BookDigestCoverCache", isDirectory: true)
    }

    private func cacheURL(for book: Book) -> URL {
        coverCacheDirectory().appendingPathComponent("\(book.id).jpg")
    }
}

private struct GoogleBooksResponse: Decodable {
    let items: [GoogleBookVolume]?
}

private struct GoogleBookVolume: Decodable {
    let volumeInfo: GoogleBookVolumeInfo
}

private struct GoogleBookVolumeInfo: Decodable {
    let title: String?
    let authors: [String]?
    let imageLinks: GoogleBookImageLinks?
}

private struct GoogleBookImageLinks: Decodable {
    let smallThumbnail: String?
    let thumbnail: String?
    let small: String?
    let medium: String?
    let large: String?
    let extraLarge: String?
}

private struct OpenLibrarySearchResponse: Decodable {
    let docs: [OpenLibraryDoc]
}

private struct OpenLibraryDoc: Decodable {
    let title: String?
    let authorNames: [String]?
    let coverID: Int?

    private enum CodingKeys: String, CodingKey {
        case title
        case authorNames = "author_name"
        case coverID = "cover_i"
    }
}

enum EditorialTheme {
    static let paper = Color(red: 0.95, green: 0.92, blue: 0.86)
    static let paperHighlight = Color(red: 0.98, green: 0.96, blue: 0.92)
    static let paperShadow = Color(red: 0.91, green: 0.88, blue: 0.81)
    static let ink = Color(red: 0.11, green: 0.09, blue: 0.08)
    static let mutedInk = Color(red: 0.45, green: 0.40, blue: 0.34)
    static let accent = Color(red: 0.76, green: 0.28, blue: 0.22)
    static let separator = Color(red: 0.73, green: 0.69, blue: 0.63)
    static let card = Color.white.opacity(0.52)
    static let forest = Color(red: 0.15, green: 0.28, blue: 0.20)

    static func displayFont(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .serif)
    }

    static func titleFont(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    static func detailFont(size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    static func uiFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

struct EditorialDivider: View {
    var body: some View {
        Rectangle()
            .fill(EditorialTheme.separator)
            .frame(height: 1)
    }
}

struct EditorialEyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(EditorialTheme.uiFont(size: 14, weight: .bold))
            .tracking(2.8)
            .foregroundStyle(EditorialTheme.forest)
    }
}

struct EditorialIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 42, height: 42)
            .background(
                Circle()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.82 : 0.66))
            )
            .overlay {
                Circle()
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            }
            .foregroundStyle(EditorialTheme.ink)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

struct EditorialPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(EditorialTheme.uiFont(size: 15, weight: .semibold))
            .tracking(1.8)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(EditorialTheme.ink)
            )
            .foregroundStyle(EditorialTheme.paperHighlight)
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

struct EditorialSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(EditorialTheme.uiFont(size: 14, weight: .medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.54 : 0.36))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(EditorialTheme.separator.opacity(0.7), lineWidth: 1)
            }
            .foregroundStyle(EditorialTheme.ink)
    }
}

struct InteractivePopGestureModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(InteractivePopGestureEnabler())
    }
}

private struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        InteractivePopController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private final class InteractivePopController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        navigationController?.interactivePopGestureRecognizer?.delegate = nil
    }
}

extension View {
    func enableInteractivePopGesture() -> some View {
        modifier(InteractivePopGestureModifier())
    }
}
