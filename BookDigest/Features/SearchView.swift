import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var bookStore: BookStore
    @FocusState private var isSearchFocused: Bool
    @StateObject private var searchModel = BookSearchModel()
    @State private var selectedResult: BookSearchResult?
    @State private var selectedCategory: BookCategory = .habits

    private let columns = [
        GridItem(.flexible(), spacing: 22, alignment: .top),
        GridItem(.flexible(), spacing: 22, alignment: .top)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 22) {
                EditorialEyebrow(text: "Search")

                HStack(spacing: 12) {
                    searchField

                    if isSearchFocused {
                        Button("Cancel") {
                            isSearchFocused = false
                        }
                        .font(EditorialTheme.uiFont(size: 16, weight: .medium))
                        .foregroundStyle(EditorialTheme.accent)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: isSearchFocused)

                if searchQuery.isEmpty {
                    Text("Search your library and discover new books")
                        .font(EditorialTheme.detailFont(size: 16))
                        .foregroundStyle(EditorialTheme.mutedInk)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    librarySection
                    discoverSection
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .preferredColorScheme(.light)
        .background(background.ignoresSafeArea())
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: searchModel.query) {
            searchModel.debouncedSearch()
        }
        .sheet(item: $selectedResult) { result in
            CategoryPickerSheet(
                result: result,
                selectedCategory: $selectedCategory,
                onAdd: { addBook(from: result, category: selectedCategory) }
            )
            .presentationDetents([.medium])
        }
    }

    @ViewBuilder
    private var librarySection: some View {
        if !filteredBooks.isEmpty {
            HStack(alignment: .lastTextBaseline) {
                EditorialEyebrow(text: "In Your Library")
                Spacer()
                Text("\(filteredBooks.count) matches")
                    .font(EditorialTheme.detailFont(size: 14))
                    .foregroundStyle(EditorialTheme.mutedInk)
            }

            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(filteredBooks) { book in
                    NavigationLink {
                        BookDetailView(book: book)
                    } label: {
                        BookTile(book: book)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(book.title) by \(book.author)")
                }
            }
        }
    }

    @ViewBuilder
    private var discoverSection: some View {
        if searchModel.isSearching {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, filteredBooks.isEmpty ? 40 : 12)
        } else if let error = searchModel.errorMessage {
            Text(error)
                .font(EditorialTheme.detailFont(size: 16))
                .foregroundStyle(EditorialTheme.mutedInk)
                .frame(maxWidth: .infinity)
                .padding(.top, filteredBooks.isEmpty ? 40 : 12)
        } else if !searchModel.results.isEmpty {
            EditorialEyebrow(text: "Discover")

            ForEach(searchModel.results) { result in
                BookSearchResultRow(result: result) {
                    selectedCategory = .habits
                    selectedResult = result
                }
            }
        } else if searchModel.hasSearched && filteredBooks.isEmpty {
            ContentUnavailableView(
                "No Matching Books",
                systemImage: "magnifyingglass",
                description: Text("Try a different search term.")
            )
            .foregroundStyle(EditorialTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                EditorialTheme.paperHighlight,
                EditorialTheme.paper,
                EditorialTheme.paperShadow.opacity(0.72)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(EditorialTheme.mutedInk)

            TextField("Search title, author, theme", text: $searchModel.query)
                .font(EditorialTheme.uiFont(size: 17))
                .foregroundStyle(EditorialTheme.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
                .onSubmit { searchModel.search() }

            if !searchModel.query.isEmpty {
                Button {
                    searchModel.query = ""
                    searchModel.results = []
                    searchModel.hasSearched = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(EditorialTheme.mutedInk.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.62))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(EditorialTheme.separator.opacity(0.42), lineWidth: 1)
        }
    }

    private var searchQuery: String {
        searchModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredBooks: [Book] {
        guard !searchQuery.isEmpty else { return [] }
        return bookStore.allBooks.filter { $0.matches(searchText: searchQuery) }
    }

    private func addBook(from result: BookSearchResult, category: BookCategory) {
        bookStore.addBook(result.makeBook(category: category))
        selectedResult = nil
    }
}

// MARK: - Search Result Row

struct BookSearchResultRow: View {
    let result: BookSearchResult
    let onSelect: () -> Void

    @EnvironmentObject private var bookStore: BookStore

    var body: some View {
        let alreadyAdded = bookStore.allBooks.contains { $0.id == result.bookID }

        Button {
            if !alreadyAdded {
                onSelect()
            }
        } label: {
            HStack(spacing: 14) {
                AsyncImage(url: result.thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(EditorialTheme.paper)
                    }
                }
                .frame(width: 56, height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(result.title)
                        .font(EditorialTheme.titleFont(size: 17))
                        .foregroundStyle(EditorialTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(result.authors)
                        .font(EditorialTheme.detailFont(size: 14))
                        .foregroundStyle(EditorialTheme.mutedInk)
                        .lineLimit(1)

                    if let description = result.description {
                        Text(description)
                            .font(EditorialTheme.detailFont(size: 13))
                            .foregroundStyle(EditorialTheme.mutedInk.opacity(0.8))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 0)

                if alreadyAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(EditorialTheme.forest)
                } else {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(EditorialTheme.forest)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.5))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(EditorialTheme.separator.opacity(0.4), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .opacity(alreadyAdded ? 0.6 : 1)
    }
}

// MARK: - Category Picker Sheet

struct CategoryPickerSheet: View {
    let result: BookSearchResult
    @Binding var selectedCategory: BookCategory
    let onAdd: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }
                    .font(EditorialTheme.uiFont(size: 17))
                    .foregroundStyle(EditorialTheme.forest)
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        AsyncImage(url: result.thumbnailURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(EditorialTheme.paper)
                            }
                        }
                        .frame(width: 48, height: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.title)
                                .font(EditorialTheme.titleFont(size: 18))
                                .foregroundStyle(EditorialTheme.ink)
                                .lineLimit(2)

                            Text(result.authors)
                                .font(EditorialTheme.detailFont(size: 14))
                                .foregroundStyle(EditorialTheme.mutedInk)
                        }
                    }

                    EditorialDivider()

                    EditorialEyebrow(text: "Category")

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 10
                    ) {
                        ForEach(BookCategory.allCases) { category in
                            Button {
                                selectedCategory = category
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: category.systemImage)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(category.title)
                                        .font(EditorialTheme.uiFont(size: 14, weight: .medium))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(selectedCategory == category
                                              ? EditorialTheme.forest
                                              : Color.white.opacity(0.5))
                                )
                                .foregroundStyle(selectedCategory == category
                                                 ? EditorialTheme.paperHighlight
                                                 : EditorialTheme.ink)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 22)
            }

            Button(action: onAdd) {
                Text("ADD TO LIBRARY")
            }
            .buttonStyle(EditorialPrimaryButtonStyle())
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
        .background(
            LinearGradient(
                colors: [EditorialTheme.paperHighlight, EditorialTheme.paper],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

// MARK: - Book Search

struct BookSearchResult: Identifiable {
    let id: String
    let title: String
    let shortTitle: String
    let authors: String
    let description: String?
    let thumbnailURL: URL?
    let subjects: [String]

    var bookID: String {
        Book.slug(fromTitle: title)
    }

    func makeBook(category: BookCategory) -> Book {
        let largeCoverURL = thumbnailURL.flatMap {
            URL(string: $0.absoluteString.replacingOccurrences(of: "-M.jpg", with: "-L.jpg"))
        }

        return Book(
            id: bookID,
            title: title,
            shortTitle: shortTitle,
            author: authors,
            angle: description ?? "A book by \(authors).",
            category: category,
            keywords: subjects,
            coverColors: [
                Color(red: 0.14, green: 0.16, blue: 0.20),
                Color(red: 0.55, green: 0.60, blue: 0.65)
            ],
            coverURL: largeCoverURL
        )
    }
}

@MainActor
final class BookSearchModel: ObservableObject {
    @Published var query = ""
    @Published var results: [BookSearchResult] = []
    @Published var isSearching = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var hasSearched = false

    // Sort order passed to Open Library (e.g. "readinglog" for popularity).
    // nil uses relevance, which suits free-text search.
    var sort: String?
    // Skip results with no cover image — mostly sparse catalog entries.
    var requireCovers = false

    private var searchTask: Task<Void, Never>?
    private var currentPage = 1
    private var fetchedCount = 0
    private var totalFound = 0

    private static let pageSize = 20

    var canLoadMore: Bool {
        hasSearched && errorMessage == nil && fetchedCount > 0 && fetchedCount < totalFound
    }

    func debouncedSearch() {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            hasSearched = false
            return
        }

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { search() }
        }
    }

    func search() {
        performSearch(reset: true)
    }

    func loadMore() {
        guard canLoadMore, !isSearching, !isLoadingMore else { return }
        performSearch(reset: false)
    }

    private func performSearch(reset: Bool) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            hasSearched = false
            return
        }

        searchTask?.cancel()
        let page = reset ? 1 : currentPage + 1

        searchTask = Task {
            if reset {
                isSearching = true
            } else {
                isLoadingMore = true
            }
            errorMessage = nil
            defer {
                isSearching = false
                isLoadingMore = false
                hasSearched = true
            }

            var components = URLComponents(string: "https://openlibrary.org/search.json")
            var queryItems = [
                URLQueryItem(name: "q", value: trimmed),
                URLQueryItem(name: "limit", value: "\(Self.pageSize)"),
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "fields", value: "key,title,author_name,first_sentence,cover_i,subject")
            ]
            if let sort {
                queryItems.append(URLQueryItem(name: "sort", value: sort))
            }
            components?.queryItems = queryItems

            guard let url = components?.url else { return }

            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if Task.isCancelled { return }

                let response = try JSONDecoder().decode(OLSearchResponse.self, from: data)
                let mapped = response.docs.compactMap { doc -> BookSearchResult? in
                    guard let title = doc.title else { return nil }
                    if requireCovers && doc.coverID == nil { return nil }
                    let authors = doc.authorNames?.joined(separator: ", ") ?? "Unknown Author"
                    let thumbURL = doc.coverID.flatMap {
                        URL(string: "https://covers.openlibrary.org/b/id/\($0)-M.jpg")
                    }
                    let short = title.count > 30 ? String(title.prefix(27)) + "..." : title
                    let description = doc.firstSentence?.first

                    return BookSearchResult(
                        id: doc.key ?? UUID().uuidString,
                        title: title,
                        shortTitle: short,
                        authors: authors,
                        description: description,
                        thumbnailURL: thumbURL,
                        subjects: Array((doc.subjects ?? []).prefix(5))
                    )
                }

                currentPage = page
                totalFound = response.numFound ?? 0
                fetchedCount = (reset ? 0 : fetchedCount) + response.docs.count

                if reset {
                    results = mapped
                } else {
                    let existingIDs = Set(results.map(\.id))
                    results.append(contentsOf: mapped.filter { !existingIDs.contains($0.id) })
                }
            } catch is CancellationError {
                // ignored
            } catch {
                if !Task.isCancelled {
                    errorMessage = "Search failed. Check your connection."
                }
            }
        }
    }
}

private struct OLSearchResponse: Decodable {
    let docs: [OLSearchDoc]
    let numFound: Int?
}

private struct OLSearchDoc: Decodable {
    let key: String?
    let title: String?
    let authorNames: [String]?
    let firstSentence: [String]?
    let coverID: Int?
    let subjects: [String]?

    private enum CodingKeys: String, CodingKey {
        case key, title
        case authorNames = "author_name"
        case firstSentence = "first_sentence"
        case coverID = "cover_i"
        case subjects = "subject"
    }
}
