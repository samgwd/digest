import SwiftUI

// Compact "now listening" bar pinned above the tab bar whenever a digest is
// loading, playing, or paused. Tapping the book info opens the full player.
struct MiniPlayerBar: View {
    @EnvironmentObject private var speechController: SpeechController
    @EnvironmentObject private var bookStore: BookStore

    let openPlayer: (Book) -> Void

    var body: some View {
        if let book = currentBook {
            VStack(spacing: 0) {
                progressLine

                HStack(spacing: 12) {
                    Button {
                        openPlayer(book)
                    } label: {
                        HStack(spacing: 12) {
                            MiniPlayerCover(book: book)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(book.title)
                                    .font(EditorialTheme.titleFont(size: 15))
                                    .foregroundStyle(EditorialTheme.ink)
                                    .lineLimit(1)

                                Text(subtitle)
                                    .font(EditorialTheme.uiFont(size: 12, weight: .medium).monospacedDigit())
                                    .foregroundStyle(EditorialTheme.mutedInk)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    transportControls
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
            .background(EditorialTheme.paperHighlight)
        }
    }

    private var currentBook: Book? {
        guard let bookID = speechController.currentBookID else { return nil }
        return bookStore.book(withID: bookID)
    }

    // The track doubles as the bar's top hairline.
    private var progressLine: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(EditorialTheme.separator.opacity(0.55))

                Rectangle()
                    .fill(EditorialTheme.ink)
                    .frame(width: geometry.size.width * playbackFraction)
            }
        }
        .frame(height: 2)
    }

    private var transportControls: some View {
        HStack(spacing: 2) {
            Button {
                speechController.skip(by: -15)
            } label: {
                transportLabel(systemName: "gobackward.15")
            }
            .disabled(!canSeek)

            Button {
                togglePlayback()
            } label: {
                ZStack {
                    Circle()
                        .fill(EditorialTheme.ink)
                        .frame(width: 48, height: 48)

                    if speechController.isLoading {
                        ProgressView()
                            .tint(EditorialTheme.paperHighlight)
                    } else {
                        Image(systemName: speechController.isSpeaking ? "pause.fill" : "play.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(EditorialTheme.paperHighlight)
                    }
                }
            }
            .disabled(speechController.isLoading)

            Button {
                speechController.skip(by: 30)
            } label: {
                transportLabel(systemName: "goforward.30")
            }
            .disabled(!canSeek)
        }
        .buttonStyle(.plain)
    }

    private func transportLabel(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 21, weight: .semibold))
            .frame(width: 44, height: 48)
            .foregroundStyle(canSeek ? EditorialTheme.ink : EditorialTheme.mutedInk.opacity(0.5))
    }

    private var subtitle: String {
        switch speechController.loadingStage {
        case .requesting:
            return "Requesting audio…"
        case .generatingAudio:
            return "Generating audio…"
        case .downloading(let fraction):
            return "Downloading \(Int(fraction * 100))%"
        case nil:
            guard speechController.duration > 0 else {
                return "Preparing audio…"
            }
            return "\(playbackTimeString(speechController.currentTime)) / \(playbackTimeString(speechController.duration))"
        }
    }

    private var playbackFraction: Double {
        guard speechController.duration > 0 else {
            return 0
        }

        return min(max(speechController.currentTime / speechController.duration, 0), 1)
    }

    private var canSeek: Bool {
        speechController.duration > 0
    }

    private func togglePlayback() {
        if speechController.isSpeaking {
            speechController.pause()
        } else if speechController.isPaused {
            speechController.continueSpeaking()
        }
    }

    private func playbackTimeString(_ time: TimeInterval) -> String {
        let totalSeconds = Int(max(time, 0).rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// CoverArtView's fixed corner radius is sized for full-width covers, so the
// bar uses its own thumbnail with a radius that suits a 36pt cover.
private struct MiniPlayerCover: View {
    let book: Book

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(EditorialTheme.paperShadow)

                Image(systemName: "book.closed.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(EditorialTheme.mutedInk)
            }
        }
        .frame(width: 36, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
        }
        .task(id: book.id) {
            image = await BookCoverService.shared.image(for: book)
        }
    }
}
