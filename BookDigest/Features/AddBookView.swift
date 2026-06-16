import SwiftUI

struct AddBookView: View {
    @EnvironmentObject private var bookStore: BookStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var searchModel = BookSearchModel()
    @State private var selectedResult: BookSearchResult?
    @State private var selectedCategory: BookCategory = .habits
    @State private var showingCategoryPicker = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 22) {
                    searchField

                    if searchModel.isSearching {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if let error = searchModel.errorMessage {
                        Text(error)
                            .font(EditorialTheme.detailFont(size: 16))
                            .foregroundStyle(EditorialTheme.mutedInk)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if searchModel.results.isEmpty && searchModel.hasSearched {
                        Text("No books found")
                            .font(EditorialTheme.detailFont(size: 16))
                            .foregroundStyle(EditorialTheme.mutedInk)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else if !searchModel.results.isEmpty {
                        EditorialEyebrow(text: "Results")

                        ForEach(searchModel.results) { result in
                            resultRow(result)
                        }
                    } else {
                        Text("Search for a book by title or author")
                            .font(EditorialTheme.detailFont(size: 16))
                            .foregroundStyle(EditorialTheme.mutedInk)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
            .background(background.ignoresSafeArea())
            .navigationTitle("Add Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(EditorialTheme.forest)
                }
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

            TextField("Search by title or author", text: $searchModel.query)
                .font(EditorialTheme.uiFont(size: 17))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
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

    private func resultRow(_ result: BookSearchResult) -> some View {
        let alreadyAdded = bookStore.allBooks.contains { $0.id == result.bookID }

        return Button {
            if !alreadyAdded {
                selectedCategory = .habits
                selectedResult = result
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

    private func addBook(from result: BookSearchResult, category: BookCategory) {
        let book = Book(
            id: result.bookID,
            title: result.title,
            shortTitle: result.shortTitle,
            author: result.authors,
            angle: result.description ?? "A book by \(result.authors).",
            category: category,
            keywords: result.subjects,
            coverColors: [
                Color(red: 0.14, green: 0.16, blue: 0.20),
                Color(red: 0.55, green: 0.60, blue: 0.65)
            ]
        )
        bookStore.addBook(book)
        selectedResult = nil
        dismiss()
    }
}

// MARK: - Category Picker Sheet

private struct CategoryPickerSheet: View {
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
        title.lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
            .split(separator: " ")
            .prefix(6)
            .joined(separator: "-")
    }
}

@MainActor
final class BookSearchModel: ObservableObject {
    @Published var query = ""
    @Published var results: [BookSearchResult] = []
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var hasSearched = false

    private var searchTask: Task<Void, Never>?

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
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            hasSearched = false
            return
        }

        searchTask?.cancel()
        searchTask = Task {
            isSearching = true
            errorMessage = nil
            defer {
                isSearching = false
                hasSearched = true
            }

            var components = URLComponents(string: "https://openlibrary.org/search.json")
            components?.queryItems = [
                URLQueryItem(name: "q", value: trimmed),
                URLQueryItem(name: "limit", value: "15"),
                URLQueryItem(name: "fields", value: "key,title,author_name,first_sentence,cover_i,subject")
            ]

            guard let url = components?.url else { return }

            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if Task.isCancelled { return }

                let response = try JSONDecoder().decode(OLSearchResponse.self, from: data)
                results = response.docs.compactMap { doc -> BookSearchResult? in
                    guard let title = doc.title else { return nil }
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
