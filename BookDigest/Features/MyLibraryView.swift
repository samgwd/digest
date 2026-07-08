import SwiftUI

struct MyLibraryView: View {
    @AppStorage(ReadingSessionStore.currentBookIDKey) private var currentReadingBookID = ""
    @EnvironmentObject private var bookStore: BookStore
    @EnvironmentObject private var digestGenerator: DigestGenerator
    @State private var finishedBookIDs: [String] = []
    @State private var inProgressBooks: [LibraryEntry] = []

    private let columns = [
        GridItem(.flexible(), spacing: 22, alignment: .top),
        GridItem(.flexible(), spacing: 22, alignment: .top)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 30) {
                header

                if downloadingBooks.isEmpty && visibleInProgressBooks.isEmpty && finishedBooks.isEmpty {
                    emptyState
                } else {
                    if !downloadingBooks.isEmpty {
                        downloadingSection
                    }

                    if !visibleInProgressBooks.isEmpty {
                        inProgressSection
                    }

                    if !finishedBooks.isEmpty {
                        finishedSection
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 40)
        }
        .background(background.ignoresSafeArea())
        .onAppear(perform: reload)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            EditorialEyebrow(text: "My Library")

            Text("Books you've read or are part way through.")
                .font(EditorialTheme.detailFont(size: 16))
                .foregroundStyle(EditorialTheme.mutedInk)

            EditorialDivider()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your library is empty.")
                .font(EditorialTheme.titleFont(size: 20))
                .foregroundStyle(EditorialTheme.ink)

            Text("Start listening to a digest and it will appear here.")
                .font(EditorialTheme.detailFont(size: 16))
                .foregroundStyle(EditorialTheme.mutedInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.5))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(EditorialTheme.separator.opacity(0.5), lineWidth: 1)
        }
    }

    private var downloadingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Downloading", count: downloadingBooks.count)

            VStack(spacing: 12) {
                ForEach(downloadingBooks) { book in
                    NavigationLink {
                        BookDetailView(book: book)
                    } label: {
                        DownloadingRow(book: book)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(book.title) by \(book.author), downloading")
                }
            }
        }
    }

    private var inProgressSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "In Progress", count: visibleInProgressBooks.count)

            VStack(spacing: 12) {
                ForEach(visibleInProgressBooks, id: \.book.id) { entry in
                    NavigationLink {
                        BookDetailView(book: entry.book)
                    } label: {
                        InProgressRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            markFinished(entry.book)
                        } label: {
                            Label("Mark as Finished", systemImage: "checkmark.circle")
                        }
                    }
                    .accessibilityAction(named: "Mark as Finished") {
                        markFinished(entry.book)
                    }
                }
            }
        }
    }

    private var finishedSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            sectionHeader(title: "Read", count: finishedBooks.count)

            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(finishedBooks) { book in
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

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(alignment: .lastTextBaseline) {
            EditorialEyebrow(text: title)
            Spacer()
            Text("\(count)")
                .font(EditorialTheme.detailFont(size: 14))
                .foregroundStyle(EditorialTheme.mutedInk)
        }
    }

    // Live view of in-flight generations: the digest itself, or the narration
    // that keeps generating after the text completes. Driven by the
    // generator's published statuses, so rows appear and disappear without a
    // reload.
    private var downloadingIDs: Set<String> {
        var ids: Set<String> = []
        for (id, status) in digestGenerator.statuses {
            if case .generating = status { ids.insert(id) }
        }
        for (id, status) in digestGenerator.audioStatuses where status == .generating {
            ids.insert(id)
        }
        return ids
    }

    private var downloadingBooks: [Book] {
        downloadingIDs
            .compactMap { id in bookStore.allBooks.first { $0.id == id } }
            .sorted { $0.title < $1.title }
    }

    private var visibleInProgressBooks: [LibraryEntry] {
        inProgressBooks.filter { !downloadingIDs.contains($0.book.id) }
    }

    private var finishedBooks: [Book] {
        finishedBookIDs
            .filter { !downloadingIDs.contains($0) }
            .compactMap { id in
                bookStore.allBooks.first { $0.id == id }
            }
    }

    private func reload() {
        finishedBookIDs = FinishedBooksStore.allFinishedIDs()

        let inProgressIDs = PlaybackPositionStore.allBookIDsWithProgress()
            .filter { !finishedBookIDs.contains($0) }

        var entries: [LibraryEntry] = inProgressIDs.compactMap { id in
            guard let book = bookStore.allBooks.first(where: { $0.id == id }),
                  let position = PlaybackPositionStore.savedPosition(for: id) else {
                return nil
            }
            return LibraryEntry(book: book, time: position.time, duration: position.duration)
        }

        if !currentReadingBookID.isEmpty,
           !entries.contains(where: { $0.book.id == currentReadingBookID }),
           !finishedBookIDs.contains(currentReadingBookID),
           let book = bookStore.allBooks.first(where: { $0.id == currentReadingBookID }) {
            entries.insert(LibraryEntry(book: book, time: 0, duration: 0), at: 0)
        }

        inProgressBooks = entries
    }

    private func markFinished(_ book: Book) {
        FinishedBooksStore.markFinished(book.id)
        PlaybackPositionStore.clear(for: book.id)
        if currentReadingBookID == book.id {
            currentReadingBookID = ""
        }
        withAnimation {
            reload()
        }
    }
}

struct LibraryEntry {
    let book: Book
    let time: TimeInterval
    let duration: TimeInterval

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(time / duration, 0), 1)
    }

    var progressPercent: Int {
        Int((progress * 100).rounded())
    }
}

private struct DownloadingRow: View {
    let book: Book

    var body: some View {
        HStack(spacing: 14) {
            CoverArtView(book: book)
                .frame(width: 64, height: CoverArtMetrics.height(forWidth: 64))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(EditorialTheme.titleFont(size: 18))
                    .foregroundStyle(EditorialTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(book.author)
                    .font(EditorialTheme.detailFont(size: 13))
                    .foregroundStyle(EditorialTheme.mutedInk)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(EditorialTheme.accent)

                    Text("Downloading…")
                        .font(EditorialTheme.uiFont(size: 11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(EditorialTheme.accent)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(EditorialTheme.mutedInk.opacity(0.7))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(EditorialTheme.separator.opacity(0.5), lineWidth: 1)
        }
    }
}

private struct InProgressRow: View {
    let entry: LibraryEntry

    var body: some View {
        HStack(spacing: 14) {
            CoverArtView(book: entry.book)
                .frame(width: 64, height: CoverArtMetrics.height(forWidth: 64))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.book.title)
                    .font(EditorialTheme.titleFont(size: 18))
                    .foregroundStyle(EditorialTheme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(entry.book.author)
                    .font(EditorialTheme.detailFont(size: 13))
                    .foregroundStyle(EditorialTheme.mutedInk)
                    .lineLimit(1)

                if entry.duration > 0 {
                    ProgressView(value: entry.progress)
                        .tint(EditorialTheme.accent)

                    Text("\(entry.progressPercent)% listened")
                        .font(EditorialTheme.uiFont(size: 11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(EditorialTheme.accent)
                } else {
                    Text("Currently Reading")
                        .font(EditorialTheme.uiFont(size: 11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(EditorialTheme.accent)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(EditorialTheme.mutedInk.opacity(0.7))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.55))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(EditorialTheme.separator.opacity(0.5), lineWidth: 1)
        }
    }
}

enum FinishedBooksStore {
    private static let key = "library.finishedBookIDs"

    static func allFinishedIDs() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func markFinished(_ bookID: String) {
        var ids = allFinishedIDs()
        guard !ids.contains(bookID) else { return }
        ids.append(bookID)
        UserDefaults.standard.set(ids, forKey: key)
    }
}

extension PlaybackPositionStore {
    static func allBookIDsWithProgress() -> [String] {
        let prefix = "playback.position."
        return UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) }
            .filter { savedPosition(for: $0) != nil }
            .sorted()
    }
}
