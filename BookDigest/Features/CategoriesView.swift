import SwiftUI

struct CategoriesView: View {
    @EnvironmentObject private var bookStore: BookStore
    @State private var readyBooks: [Book] = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 14) {
                EditorialEyebrow(text: "Categories")

                if !readyBooks.isEmpty {
                    NavigationLink {
                        ReadyDigestsShelfView(books: readyBooks)
                    } label: {
                        ReadyDigestsRow(bookCount: readyBooks.count)
                    }
                    .buttonStyle(.plain)

                    Rectangle()
                        .fill(EditorialTheme.separator.opacity(0.6))
                        .frame(height: 1)
                        .padding(.vertical, 6)
                }

                ForEach(BookCategory.allCases) { category in
                    NavigationLink {
                        CategoryShelfView(category: category)
                    } label: {
                        CategoryRow(category: category)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .background(background.ignoresSafeArea())
        .task { await loadReadyBooks() }
        .refreshable { await loadReadyBooks() }
    }

    // The digest table is shared, so a ready row can belong to a book from
    // any shelf or the user's own library. Rows for books this install
    // doesn't know about are dropped — without a category they can't render.
    private func loadReadyBooks() async {
        guard let rows = try? await SharedAppState.shared.supabaseService.fetchReadyDigests() else {
            return
        }
        let curated = BookCategory.allCases.flatMap(CuratedBooks.books(in:))
        var seen = Set<String>()
        readyBooks = rows.compactMap { row in
            bookStore.book(withID: row.bookID)
                ?? curated.first { $0.id == row.bookID }
                ?? (bookStore.allBooks + curated).first {
                    $0.title.compare(row.title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }
        }
        .filter { seen.insert($0.id).inserted }
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

}

// Inverted treatment on purpose: this entry isn't a real category, and the
// filled card plus the divider below it mark it as a different kind of shelf.
private struct ReadyDigestsRow: View {
    let bookCount: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(EditorialTheme.forest)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(EditorialTheme.paperHighlight)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Ready to Listen")
                    .font(EditorialTheme.titleFont(size: 19))
                    .foregroundStyle(EditorialTheme.paperHighlight)

                Text(bookCount == 1
                    ? "1 book with a digest already available"
                    : "\(bookCount) books with digests already available")
                    .font(EditorialTheme.detailFont(size: 14))
                    .foregroundStyle(EditorialTheme.paperHighlight.opacity(0.82))
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(EditorialTheme.paperHighlight.opacity(0.7))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(EditorialTheme.forest)
        )
    }
}

struct ReadyDigestsShelfView: View {
    let books: [Book]

    private let columns = [
        GridItem(.flexible(), spacing: 22, alignment: .top),
        GridItem(.flexible(), spacing: 22, alignment: .top)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    EditorialEyebrow(text: "Ready to Listen")

                    Text("Digests that have already been generated")
                        .font(EditorialTheme.detailFont(size: 18))
                        .foregroundStyle(EditorialTheme.mutedInk)
                }

                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(books) { book in
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
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .background(background.ignoresSafeArea())
        .navigationTitle("Ready to Listen")
        .navigationBarTitleDisplayMode(.inline)
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
}
