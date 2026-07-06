import SwiftUI

private enum DigestState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

struct BookDetailView: View {
    let book: Book

    @AppStorage(ReadingSessionStore.currentBookIDKey) private var currentReadingBookID = ""
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var speechController: SpeechController
    @EnvironmentObject private var digestGenerator: DigestGenerator
    @EnvironmentObject private var bookStore: BookStore
    @State private var digestText = ""
    @State private var digestState: DigestState = .idle
    @State private var errorMessage: String?
    @State private var savedAt: Date?
    @State private var isShowingPlayer = false
    @State private var isDigestExpanded = false
    @State private var synopsis: String?
    @State private var isSynopsisLoading = false
    @State private var digestProgress: Double = 0
    @State private var digestProgressTimer: Timer?
    @State private var savedPlaybackTime: TimeInterval = 0
    @State private var savedPlaybackDuration: TimeInterval = 0

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 26) {
                    hero
                    actionBlock
                    if let synopsis, !synopsis.isEmpty {
                        leadParagraph
                    }
                    digestBlock
                }
                .padding(.horizontal, 22)
                .padding(.top, 60)
                .padding(.bottom, 40)
            }

            backButton
                .padding(.leading, 22)
                .padding(.top, 10)
        }
        .background(background.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .enableInteractivePopGesture()
        .toolbar(.hidden, for: .tabBar)
        .task(id: book.id) {
            loadSavedDigest()
            loadSavedPlaybackPosition()
            syncWithGenerator(status: digestGenerator.status(for: book.id))
            async let synopsisTask: () = loadSynopsis()
            async let contentsTask: () = loadContents()
            async let remoteDigestTask: () = loadRemoteDigestIfNeeded()
            _ = await (synopsisTask, contentsTask, remoteDigestTask)
        }
        .onReceive(digestGenerator.$statuses) { statuses in
            syncWithGenerator(status: statuses[book.id] ?? .idle)
        }
        .fullScreenCover(isPresented: $isShowingPlayer, onDismiss: {
            loadSavedPlaybackPosition()
        }) {
            BookPlaybackView(book: book, digestText: digestText)
                .environmentObject(settings)
                .environmentObject(speechController)
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                EditorialTheme.paperHighlight,
                EditorialTheme.paper,
                EditorialTheme.paperShadow.opacity(0.75)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var hero: some View {
        VStack(spacing: 18) {
            EditorialEyebrow(text: book.deck)

            VStack(spacing: 8) {
                Text(book.title)
                    .font(EditorialTheme.displayFont(size: 31))
                    .foregroundStyle(EditorialTheme.ink)
                    .multilineTextAlignment(.center)

                Text("by \(book.author)")
                    .font(EditorialTheme.detailFont(size: 18))
                    .foregroundStyle(EditorialTheme.mutedInk)
                    .multilineTextAlignment(.center)
            }

            EditorialDivider()

            CoverArtView(book: book)
                .frame(width: 198, height: CoverArtMetrics.height(forWidth: 198))
                .shadow(color: .black.opacity(0.10), radius: 18, y: 12)
        }
    }

    private var leadParagraph: some View {
        Text(leadAttributedText)
            .font(EditorialTheme.detailFont(size: 18))
            .foregroundStyle(EditorialTheme.mutedInk)
            .lineSpacing(5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var leadAttributedText: AttributedString {
        let full = (synopsis ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = full.first else { return AttributedString(full) }

        var firstChar = AttributedString(String(first))
        firstChar.font = EditorialTheme.displayFont(size: 40)
        firstChar.foregroundColor = UIColor(EditorialTheme.accent)

        var rest = AttributedString(String(full.dropFirst()))
        rest.font = EditorialTheme.detailFont(size: 18)

        return firstChar + rest
    }

    private var actionBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                handlePrimaryAction()
            } label: {
                HStack {
                    if digestState == .loading {
                        DigestProgressRing(progress: digestProgress)
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: primaryButtonImage)
                    }
                    Text(primaryButtonTitle.uppercased())
                }
            }
            .buttonStyle(EditorialPrimaryButtonStyle())
            .disabled(primaryButtonDisabled)

            if !isInLibrary {
                Button {
                    bookStore.addBook(book)
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add to Library")
                    }
                }
                .buttonStyle(EditorialSecondaryButtonStyle())
            }

            if hasListeningProgress {
                listeningProgressCard
            }

            if speechController.currentBookID == book.id {
                nowPlayingCard
            }

            if settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Add an OpenAI API key in Settings to generate digests that don't exist yet. Digests other readers have already generated are shared and free to play.")
                    .font(EditorialTheme.detailFont(size: 14))
                    .foregroundStyle(EditorialTheme.mutedInk)
            }

            if let savedAt {
                Text("Saved \(savedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(EditorialTheme.detailFont(size: 14))
                    .foregroundStyle(EditorialTheme.mutedInk)
            }

            if let speechErrorMessage = speechController.errorMessage {
                Text(speechErrorMessage)
                    .font(EditorialTheme.detailFont(size: 14))
                    .foregroundStyle(.red.opacity(0.86))
            }
        }
    }

    @ViewBuilder
    private var digestBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isDigestExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        EditorialEyebrow(text: "Digest")

                        Text(digestCollapsedSummary)
                            .font(EditorialTheme.detailFont(size: 16))
                            .foregroundStyle(digestSummaryColor)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 12)

                    if digestState == .loading {
                        ProgressView()
                            .tint(EditorialTheme.ink)
                    }

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(EditorialTheme.mutedInk)
                        .rotationEffect(.degrees(isDigestExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isDigestExpanded {
                digestContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.30))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(EditorialTheme.separator.opacity(0.66), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var digestContent: some View {
        switch digestState {
        case .idle where digestText.isEmpty:
            Text("Generate an audio-ready essay for \(book.title) and it will appear here.")
                .font(EditorialTheme.detailFont(size: 18))
                .foregroundStyle(EditorialTheme.mutedInk)

        case .loading:
            VStack(alignment: .leading, spacing: 12) {
                ProgressView()
                    .tint(EditorialTheme.ink)
                Text("Creating digest...")
                    .font(EditorialTheme.detailFont(size: 17))
                    .foregroundStyle(EditorialTheme.mutedInk)
            }

        case .failed:
            Text(errorMessage ?? "Generation failed. Try again in a moment.")
                .font(EditorialTheme.detailFont(size: 17))
                .foregroundStyle(.red.opacity(0.85))

        case .idle, .loaded:
            Text(digestText)
                .font(EditorialTheme.detailFont(size: 18))
                .foregroundStyle(EditorialTheme.ink)
                .lineSpacing(8)
                .textSelection(.enabled)
        }
    }

    private var nowPlayingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            EditorialEyebrow(text: nowPlayingStatusText)

            if speechController.duration > 0 {
                ProgressView(value: speechController.currentTime, total: max(speechController.duration, 1))
                    .tint(EditorialTheme.ink)
            }

            Button("Open Player") {
                isShowingPlayer = true
            }
            .buttonStyle(EditorialSecondaryButtonStyle())
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.34))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(EditorialTheme.separator.opacity(0.66), lineWidth: 1)
        }
    }

    private var primaryButtonTitle: String {
        if digestState == .loading {
            return "Digesting"
        }

        if digestText.isEmpty {
            return "Generate Digest"
        }

        if speechController.currentBookID == book.id {
            return "Open Player"
        }

        return "Listen"
    }

    private var primaryButtonImage: String {
        if digestState == .loading {
            return "sparkles"
        }

        return digestText.isEmpty ? "sparkles" : "play.fill"
    }

    private var primaryButtonDisabled: Bool {
        // An empty OpenAI key doesn't disable generation: the tap may find a
        // digest another reader already shared, which needs no key.
        digestState == .loading
    }

    private var digestCollapsedSummary: String {
        switch digestState {
        case .idle where digestText.isEmpty:
            return "Generate a digest, then open it here at the bottom of the page."
        case .loading:
            return "Creating digest..."
        case .failed:
            return errorMessage ?? "Generation failed. Try again in a moment."
        case .idle, .loaded:
            return "Tap to open the full digest."
        }
    }

    private var digestSummaryColor: Color {
        if digestState == .failed {
            return .red.opacity(0.85)
        }

        return EditorialTheme.mutedInk
    }

    private var hasListeningProgress: Bool {
        !digestText.isEmpty && savedPlaybackDuration > 0 && speechController.currentBookID != book.id
    }

    private var listeningProgressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                EditorialEyebrow(text: "Listening Progress")
                Spacer()
                Text("\(listeningProgressPercent)%")
                    .font(EditorialTheme.uiFont(size: 13, weight: .semibold))
                    .foregroundStyle(EditorialTheme.mutedInk)
            }

            ProgressView(value: savedPlaybackTime, total: max(savedPlaybackDuration, 1))
                .tint(EditorialTheme.ink)

            HStack {
                Text(playbackTimeString(savedPlaybackTime))
                Spacer()
                Text(playbackTimeString(savedPlaybackDuration))
            }
            .font(EditorialTheme.detailFont(size: 13).monospacedDigit())
            .foregroundStyle(EditorialTheme.mutedInk)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.34))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(EditorialTheme.separator.opacity(0.66), lineWidth: 1)
        }
    }

    private var listeningProgressPercent: Int {
        guard savedPlaybackDuration > 0 else { return 0 }
        return min(Int((savedPlaybackTime / savedPlaybackDuration) * 100), 100)
    }

    private func playbackTimeString(_ time: TimeInterval) -> String {
        let totalSeconds = Int(max(time, 0).rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var nowPlayingStatusText: String {
        if speechController.loadingStage != nil {
            return "Preparing Audio"
        }

        if speechController.isPaused {
            return "Paused"
        }

        if speechController.isSpeaking {
            return "Now Playing"
        }

        return "Ready"
    }

    private var isInLibrary: Bool {
        bookStore.allBooks.contains { $0.id == book.id }
    }

    private func handlePrimaryAction() {
        if digestText.isEmpty {
            speechController.stop()
            // Keep the digest reachable from the library when generating for a
            // book browsed from a category shelf.
            bookStore.addBook(book)
            digestGenerator.generate(for: book)
            return
        }

        openPlayer()
    }

    private func syncWithGenerator(status: DigestGenerator.Status) {
        switch status {
        case .idle:
            break
        case .generating:
            if digestState != .loading {
                errorMessage = nil
                digestState = .loading
                startDigestProgressTimer()
            }
        case .completed(let when):
            if let saved = DigestStorage.load(for: book.id) {
                let sanitized = DigestTextSanitizer.sanitize(saved.text)
                digestText = sanitized
                savedAt = saved.savedAt
                if sanitized != saved.text {
                    DigestStorage.save(sanitized, for: book.id, savedAt: saved.savedAt)
                }
            } else {
                savedAt = when
            }
            stopDigestProgressTimer()
            digestState = .loaded
            digestGenerator.acknowledgeCompletion(for: book.id)
        case .failed(let message):
            errorMessage = message
            stopDigestProgressTimer()
            digestState = .failed
        }
    }

    private static let estimatedDigestSeconds: Double = 90

    private func startDigestProgressTimer() {
        digestProgressTimer?.invalidate()
        digestProgress = 0
        let start = Date()
        let timer = Timer(timeInterval: 0.25, repeats: true) { _ in
            let elapsed = Date().timeIntervalSince(start)
            let estimate = Self.estimatedDigestSeconds
            withAnimation(.linear(duration: 0.25)) {
                digestProgress = 1 - 1 / (1 + elapsed / estimate)
            }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        digestProgressTimer = timer
    }

    private func stopDigestProgressTimer() {
        digestProgressTimer?.invalidate()
        digestProgressTimer = nil
        withAnimation(.easeOut(duration: 0.3)) {
            digestProgress = 1
        }
    }

    private func loadSavedDigest() {
        guard digestText.isEmpty, let savedDigest = DigestStorage.load(for: book.id) else {
            return
        }

        let sanitizedText = DigestTextSanitizer.sanitize(savedDigest.text)
        digestText = sanitizedText
        savedAt = savedDigest.savedAt
        digestState = .loaded

        if sanitizedText != savedDigest.text {
            DigestStorage.save(sanitizedText, for: book.id, savedAt: savedDigest.savedAt)
        }
    }

    private func loadRemoteDigestIfNeeded() async {
        guard digestText.isEmpty else { return }
        if await digestGenerator.fetchRemoteDigestIfAvailable(for: book) {
            loadSavedDigest()
        } else {
            // The shared row may be mid-generation (e.g. this device started
            // it before a relaunch); reattach instead of showing Generate.
            await digestGenerator.resumeIfRemoteGenerating(for: book)
        }
    }

    private func loadSavedPlaybackPosition() {
        if let saved = PlaybackPositionStore.savedPosition(for: book.id) {
            savedPlaybackTime = saved.time
            savedPlaybackDuration = saved.duration
        } else {
            savedPlaybackTime = 0
            savedPlaybackDuration = 0
        }
    }

    private func loadSynopsis() async {
        if let cached = SynopsisStorage.load(for: book.id) {
            synopsis = cached
            return
        }

        isSynopsisLoading = true
        defer { isSynopsisLoading = false }

        guard let fetched = await OpenLibraryClient.fetchSynopsis(
            title: book.title,
            author: book.author
        ) else { return }

        synopsis = fetched
        SynopsisStorage.save(fetched, for: book.id)
    }

    // Contents are no longer shown on this page, but playback still uses them
    // for section markers, so keep fetching in the background.
    private func loadContents() async {
        if ContentsStorage.load(for: book.id) != nil { return }

        guard let fetched = await OpenLibraryClient.fetchTableOfContents(
            title: book.title,
            author: book.author
        ) else { return }

        ContentsStorage.save(fetched, for: book.id)
    }

    private func openPlayer() {
        guard !digestText.isEmpty else {
            return
        }

        currentReadingBookID = book.id
        isShowingPlayer = true
    }
}

private struct DigestProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(EditorialTheme.paperHighlight.opacity(0.3), lineWidth: 2)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(EditorialTheme.paperHighlight, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
