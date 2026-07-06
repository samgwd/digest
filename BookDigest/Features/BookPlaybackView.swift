import SwiftUI

struct BookPlaybackView: View {
    let book: Book
    let digestText: String

    @AppStorage(ReadingSessionStore.currentBookIDKey) private var currentReadingBookID = ""
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var speechController: SpeechController
    @State private var scrubPosition = 0.0
    @State private var isEditingScrubber = false
    @State private var savedTime: TimeInterval = 0
    @State private var savedDuration: TimeInterval = 0

    private var isShowingSavedPosition: Bool {
        speechController.currentBookID != book.id && savedDuration > 0
    }

    private var displayCurrentTime: TimeInterval {
        if isEditingScrubber { return scrubPosition }
        if isShowingSavedPosition { return savedTime }
        return speechController.currentTime
    }

    private var displayDuration: TimeInterval {
        if isShowingSavedPosition { return savedDuration }
        return speechController.duration
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 26) {
                topBar
                artwork
                titleBlock
                progressSection
                controls
                statusSection
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 34)
        }
        .scrollIndicators(.hidden)
        .background(background.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear {
            if let saved = PlaybackPositionStore.savedPosition(for: book.id) {
                savedTime = saved.time
                savedDuration = saved.duration
            }
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                EditorialTheme.paperHighlight,
                EditorialTheme.paper,
                EditorialTheme.paperShadow.opacity(0.78)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(EditorialIconButtonStyle())

            Spacer()

            VStack(spacing: 6) {
                Text("Now Reading Aloud")
                    .font(EditorialTheme.uiFont(size: 11, weight: .semibold))
                    .tracking(2.8)
                    .foregroundStyle(EditorialTheme.ink)

                Text(downloadHeader)
                    .font(EditorialTheme.detailFont(size: 13))
                    .foregroundStyle(EditorialTheme.mutedInk)
            }

            Spacer()

            Image(systemName: "list.bullet")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(Circle().fill(Color.white.opacity(0.52)))
                .overlay {
                    Circle().stroke(EditorialTheme.separator.opacity(0.48), lineWidth: 1)
                }
                .foregroundStyle(EditorialTheme.ink)
        }
    }

    private var artwork: some View {
        CoverArtView(book: book)
            .frame(width: 210, height: 305)
            .shadow(color: .black.opacity(0.10), radius: 20, y: 12)
            .padding(.top, 8)
    }

    private var titleBlock: some View {
        VStack(spacing: 10) {
            EditorialEyebrow(text: currentSectionTitle)

            Text(book.title)
                .font(EditorialTheme.displayFont(size: 31))
                .foregroundStyle(EditorialTheme.ink)
                .multilineTextAlignment(.center)

            Text(book.author)
                .font(EditorialTheme.detailFont(size: 18))
                .foregroundStyle(EditorialTheme.mutedInk)
                .multilineTextAlignment(.center)
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PlaybackTimeline(
                progress: playbackFraction,
                downloadFraction: downloadedFraction
            )
            .frame(height: 18)

            Slider(
                value: Binding(
                    get: { isEditingScrubber ? scrubPosition : displayCurrentTime },
                    set: { scrubPosition = $0 }
                ),
                in: 0...max(displayDuration, 1),
                onEditingChanged: { isEditing in
                    if isEditing {
                        scrubPosition = displayCurrentTime
                        isEditingScrubber = true
                    } else {
                        isEditingScrubber = false
                        speechController.seek(to: scrubPosition)
                    }
                }
            )
            .opacity(0.02)
            .frame(height: 0)
            .disabled(!canSeek)

            HStack {
                Text(playbackTimeString(displayCurrentTime))
                Spacer()
                Text(playbackTimeString(displayDuration))
            }
            .font(EditorialTheme.uiFont(size: 13, weight: .medium).monospacedDigit())
            .foregroundStyle(EditorialTheme.mutedInk)

            if hasDownloadProgress {
                HStack {
                    Text("Downloaded")
                    Spacer()
                    Text(downloadHeader)
                }
                .font(EditorialTheme.detailFont(size: 14))
                .foregroundStyle(EditorialTheme.mutedInk)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 28) {
            Button {
                speechController.skip(by: -15)
            } label: {
                playerControlLabel(systemName: "gobackward.15")
            }
            .buttonStyle(.plain)
            .disabled(!canSeek)

            Button {
                togglePlayback()
            } label: {
                Image(systemName: playPauseImage)
                    .font(.system(size: 34, weight: .bold))
                    .frame(width: 84, height: 84)
                    .background(Circle().fill(EditorialTheme.ink))
                    .foregroundStyle(EditorialTheme.paperHighlight)
            }
            .buttonStyle(.plain)
            .disabled(digestText.isEmpty || speechController.isLoading)

            Button {
                speechController.skip(by: 30)
            } label: {
                playerControlLabel(systemName: "goforward.30")
            }
            .buttonStyle(.plain)
            .disabled(!canSeek)
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let errorMessage = speechController.errorMessage {
            Text(errorMessage)
                .font(EditorialTheme.detailFont(size: 14))
                .multilineTextAlignment(.center)
                .foregroundStyle(.red.opacity(0.86))
            
        } else if speechController.isLoading {
            Text("Preparing audio...")
                .font(EditorialTheme.detailFont(size: 15))
                .foregroundStyle(EditorialTheme.mutedInk)
        }
    }

    private func playerControlLabel(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 24, weight: .semibold))
            .frame(width: 58, height: 58)
            .foregroundStyle(EditorialTheme.ink)
    }

    private var hasPlaybackState: Bool {
        speechController.currentBookID == book.id &&
            (speechController.isSpeaking || speechController.isPaused || speechController.isLoading)
    }

    private var isPreparingTrack: Bool {
        speechController.currentBookID == book.id && speechController.loadingStage != nil
    }

    private var canSeek: Bool {
        speechController.currentBookID == book.id && speechController.duration > 0
    }

    private var playPauseImage: String {
        if speechController.isSpeaking {
            return "pause.fill"
        }

        return "play.fill"
    }

    private var playbackFraction: Double {
        guard displayDuration > 0 else {
            return 0
        }

        return min(max(displayCurrentTime / displayDuration, 0), 1)
    }

    private var downloadedFraction: Double {
        let dur = displayDuration
        guard dur > 0 else {
            return 0
        }

        if isShowingSavedPosition { return 1 }
        return min(max(speechController.downloadedDuration / dur, 0), 1)
    }

    private var currentSectionTitle: String {
        let sections = book.contentsItems
        guard !sections.isEmpty else {
            return book.deck
        }

        guard displayDuration > 0 else {
            return sections[0]
        }

        let time = isShowingSavedPosition ? savedTime : speechController.currentTime
        let fraction = min(max(time / displayDuration, 0), 0.999)
        let index = min(Int(Double(sections.count) * fraction), sections.count - 1)
        return sections[index]
    }

    private var hasDownloadProgress: Bool {
        speechController.currentBookID == book.id && speechController.loadingStage != nil
    }

    private var downloadHeader: String {
        guard speechController.currentBookID == book.id else {
            return "\(playbackTimeString(displayDuration)) ready"
        }

        switch speechController.loadingStage {
        case .requesting:
            return "Requesting audio…"
        case .generatingAudio:
            return "Generating audio…"
        case .downloading(let fraction):
            return "Downloading \(Int(fraction * 100))%"
        case nil:
            return "\(playbackTimeString(speechController.duration)) ready"
        }
    }

    private func togglePlayback() {
        currentReadingBookID = book.id

        if speechController.currentBookID != book.id {
            speechController.speak(digestText, book: book, apiKey: settings.elevenLabsAPIKey)
            return
        }

        if speechController.isPaused {
            speechController.continueSpeaking()
        } else if speechController.isSpeaking {
            speechController.pause()
        } else {
            speechController.speak(digestText, book: book, apiKey: settings.elevenLabsAPIKey)
        }
    }

    private func playbackTimeString(_ time: TimeInterval) -> String {
        let totalSeconds = Int(max(time, 0).rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct PlaybackTimeline: View {
    let progress: Double
    let downloadFraction: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(EditorialTheme.separator.opacity(0.55))
                    .frame(height: 1)

                Rectangle()
                    .fill(EditorialTheme.ink.opacity(0.18))
                    .frame(width: width * downloadFraction, height: 2)

                Rectangle()
                    .fill(EditorialTheme.ink)
                    .frame(width: max(width * progress, 0), height: 2)

                Circle()
                    .fill(EditorialTheme.ink)
                    .frame(width: 8, height: 8)
                    .offset(x: max(min((width * progress) - 4, width - 8), 0))
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}
