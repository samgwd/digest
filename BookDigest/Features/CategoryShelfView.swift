import SwiftUI

struct CategoryShelfView: View {
    let category: BookCategory
    @EnvironmentObject private var bookStore: BookStore

    private let columns = [
        GridItem(.flexible(), spacing: 22, alignment: .top),
        GridItem(.flexible(), spacing: 22, alignment: .top)
    ]

    private var books: [Book] {
        bookStore.allBooks.filter { $0.category == category }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    EditorialEyebrow(text: category.title)

                    Text(category.subtitle)
                        .font(EditorialTheme.detailFont(size: 18))
                        .foregroundStyle(EditorialTheme.mutedInk)

                    Text("\(books.count) books")
                        .font(EditorialTheme.uiFont(size: 13, weight: .semibold))
                        .foregroundStyle(EditorialTheme.accent)
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
