import SwiftUI

struct CategoryShelfView: View {
    let category: BookCategory
    @EnvironmentObject private var bookStore: BookStore

    private let columns = [
        GridItem(.flexible(), spacing: 22, alignment: .top),
        GridItem(.flexible(), spacing: 22, alignment: .top)
    ]

    // Prefer the library's copy when the reader already has the book, so
    // digest state and category stay consistent. Catalog ids predate the
    // shared slug format, hence the title fallback.
    private var books: [Book] {
        CuratedBooks.books(in: category).map { curated in
            bookStore.book(withID: curated.id)
                ?? bookStore.allBooks.first {
                    $0.title.compare(curated.title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }
                ?? curated
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    EditorialEyebrow(text: category.title)

                    Text(category.subtitle)
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
        .navigationTitle(category.title)
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
