import SwiftUI

struct LibraryView: View {
    @AppStorage(ReadingSessionStore.currentBookIDKey) private var currentReadingBookID = ""
    @EnvironmentObject private var speechController: SpeechController
    @EnvironmentObject private var bookStore: BookStore
    @State private var showingAddBook = false

    private let columns = [
        GridItem(.flexible(), spacing: 22, alignment: .top),
        GridItem(.flexible(), spacing: 22, alignment: .top)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 30) {
                masthead

                if let currentReadingBook {
                    currentReadingSection(for: currentReadingBook)
                }

                topPicksSection
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

    private var masthead: some View {
        VStack(spacing: 18) {
            HStack {
                Spacer()
                    .frame(width: 42)

                Spacer()

                Image("logo-spell-out")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 150)

                Spacer()

                Button {
                    showingAddBook = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .bold))
                }
                .buttonStyle(EditorialIconButtonStyle())
                .accessibilityLabel("Add Book")
            }

            EditorialDivider()
        }
        .sheet(isPresented: $showingAddBook) {
            AddBookView()
        }
    }

    private func currentReadingSection(for book: Book) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorialEyebrow(text: "Currently Reading")

            NavigationLink {
                BookDetailView(book: book)
            } label: {
                HStack(spacing: 14) {
                    CoverArtView(book: book)
                        .frame(width: 72, height: CoverArtMetrics.height(forWidth: 72))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(book.title)
                            .font(EditorialTheme.titleFont(size: 20))
                            .foregroundStyle(EditorialTheme.ink)
                            .multilineTextAlignment(.leading)

                        Text(currentReadingStatusText(for: book))
                            .font(EditorialTheme.uiFont(size: 12, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(EditorialTheme.accent)

                        Text("\(book.deck) · \(book.readingMinutes) min")
                            .font(EditorialTheme.uiFont(size: 12))
                            .foregroundStyle(EditorialTheme.mutedInk)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: speechController.currentBookID == book.id ? "waveform" : "arrow.up.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(EditorialTheme.paperHighlight)
                        .frame(width: 46, height: 46)
                        .background(
                            Circle()
                                .fill(EditorialTheme.forest)
                        )
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(EditorialTheme.separator.opacity(0.5), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var topPicksSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .lastTextBaseline) {
                EditorialEyebrow(text: "Top Picks")
                Spacer()
                Text("6 selections")
                    .font(EditorialTheme.detailFont(size: 14))
                    .foregroundStyle(EditorialTheme.mutedInk)
            }

            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(topPickBooks) { book in
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

    private var currentReadingBook: Book? {
        if let activeBook = activePlaybackBook {
            return activeBook
        }

        guard !currentReadingBookID.isEmpty else {
            return nil
        }

        return bookStore.allBooks.first { $0.id == currentReadingBookID }
    }

    private var activePlaybackBook: Book? {
        guard let currentBookID = speechController.currentBookID else {
            return nil
        }

        return bookStore.allBooks.first { $0.id == currentBookID }
    }

    private var topPickBooks: [Book] {
        let topPickIDs = [
            "atomic-habits",
            "deep-work",
            "essentialism",
            "getting-things-done",
            "inspired",
            "never-split-the-difference"
        ]

        return topPickIDs.compactMap { id in
            bookStore.allBooks.first { $0.id == id }
        }
    }

    private func currentReadingStatusText(for book: Book) -> String {
        if speechController.currentBookID == book.id {
            if speechController.isPreparingFullTrack {
                return "Preparing Audio"
            }

            if speechController.isSpeaking {
                return "Now Playing"
            }

            if speechController.isPaused {
                return "Paused"
            }
        }

        return "Continue Digest"
    }

}

struct BookTile: View {
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                CoverArtView(book: book)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .aspectRatio(0.68, contentMode: .fit)
            .shadow(color: Color.black.opacity(0.15), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(EditorialTheme.titleFont(size: 18))
                    .foregroundStyle(EditorialTheme.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(book.author)
                    .font(EditorialTheme.detailFont(size: 14))
                    .foregroundStyle(EditorialTheme.mutedInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(book.category.title.uppercased())
                    .font(EditorialTheme.uiFont(size: 10, weight: .semibold))
                    .tracking(1.7)
                    .foregroundStyle(EditorialTheme.forest)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CategoryRow: View {
    let category: BookCategory
    let count: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: category.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(EditorialTheme.paperHighlight)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(EditorialTheme.forest)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(category.title)
                    .font(EditorialTheme.titleFont(size: 19))
                    .foregroundStyle(EditorialTheme.ink)

                Text(category.subtitle)
                    .font(EditorialTheme.detailFont(size: 14))
                    .foregroundStyle(EditorialTheme.mutedInk)
                    .lineLimit(2)
            }

            Spacer()

            Text("\(count)")
                .font(EditorialTheme.uiFont(size: 13, weight: .semibold))
                .foregroundStyle(EditorialTheme.mutedInk)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(EditorialTheme.mutedInk.opacity(0.7))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.5))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(EditorialTheme.separator.opacity(0.44), lineWidth: 1)
        }
    }
}
