import SwiftUI

struct CategoriesView: View {
    @EnvironmentObject private var bookStore: BookStore

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 14) {
                EditorialEyebrow(text: "Categories")

                ForEach(BookCategory.allCases) { category in
                    NavigationLink {
                        CategoryShelfView(category: category)
                    } label: {
                        CategoryRow(category: category, count: books(in: category).count)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .background(background.ignoresSafeArea())
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

    private func books(in category: BookCategory) -> [Book] {
        bookStore.allBooks.filter { $0.category == category }
    }
}
