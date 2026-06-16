import SwiftUI

struct SearchView: View {
    @EnvironmentObject private var bookStore: BookStore
    @FocusState private var isSearchFocused: Bool
    @State private var searchText = ""

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
                    Text("Search by title, author, or theme")
                        .font(EditorialTheme.detailFont(size: 16))
                        .foregroundStyle(EditorialTheme.mutedInk)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if filteredBooks.isEmpty {
                    ContentUnavailableView(
                        "No Matching Books",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search term.")
                    )
                    .foregroundStyle(EditorialTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                } else {
                    HStack(alignment: .lastTextBaseline) {
                        EditorialEyebrow(text: "Results")
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
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .preferredColorScheme(.light)
        .background(background.ignoresSafeArea())
        .onAppear {
            isSearchFocused = true
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

            TextField("Search title, author, theme", text: $searchText)
                .font(EditorialTheme.uiFont(size: 17))
                .foregroundStyle(EditorialTheme.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($isSearchFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
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
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredBooks: [Book] {
        guard !searchQuery.isEmpty else { return [] }
        return bookStore.allBooks.filter { $0.matches(searchText: searchQuery) }
    }
}
