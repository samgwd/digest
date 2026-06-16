@preconcurrency import AVFoundation
import CryptoKit
import Foundation
import MediaPlayer

@MainActor
final class SpeechController: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false
    @Published private(set) var isPaused = false
    @Published private(set) var isLoading = false
    @Published private(set) var isPreparingFullTrack = false
    @Published private(set) var currentBookID: String?
    @Published private(set) var currentTitle: String?
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var downloadedDuration: TimeInterval = 0
    @Published private(set) var downloadedChunkCount = 0
    @Published private(set) var totalChunkCount = 0
    @Published private(set) var errorMessage: String?

    private var audioPlayer: AVAudioPlayer?
    private var preparationTask: Task<Void, Never>?
    private var progressTimer: Timer?
    private var hasActiveAudioSession = false
    private var interruptionObserver: (any NSObjectProtocol)?
    private var currentAudioKey: String?
    private var combinedAudioURL: URL?
    private var preparedChunkURLs: [URL] = []
    private var preparedChunkDurations: [TimeInterval] = []
    private var currentChunkIndex = 0
    private var playbackOffset: TimeInterval = 0
    private var isUsingCombinedPlayer = false
    private var waitingForChunkIndex: Int?
    private var nowPlayingArtwork: MPMediaItemArtwork?

    var downloadProgress: Double {
        guard totalChunkCount > 0 else {
            return 0
        }

        return Double(downloadedChunkCount) / Double(totalChunkCount)
    }

    func speak(_ text: String, bookID: String, title: String, apiKey: String, model: String, voice: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            return
        }

        guard !trimmedAPIKey.isEmpty else {
            errorMessage = "Add an ElevenLabs API key in Settings."
            return
        }

        let speechModel = model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "eleven_flash_v2_5" : model
        let speechVoice = voice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "lUTamkMw7gOzZbFIwmq4" : voice
        let audioKey = SpeechAudioCache.cacheKey(text: trimmedText, model: speechModel, voice: speechVoice)

        currentBookID = bookID
        currentTitle = title
        errorMessage = nil
        loadArtwork(for: bookID)

        if currentAudioKey == audioKey, audioPlayer != nil {
            if duration > 0, currentTime >= duration {
                seek(to: 0)
            }

            do {
                try startPlayback()
            } catch {
                errorMessage = error.localizedDescription
                resetPlaybackState(keepError: true)
            }
            return
        }

        stop()
        currentBookID = bookID
        currentTitle = title
        errorMessage = nil
        isLoading = true

        preparationTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await preparePlayback(
                    for: trimmedText,
                    bookID: bookID,
                    title: title,
                    apiKey: trimmedAPIKey,
                    model: speechModel,
                    voice: speechVoice,
                    audioKey: audioKey
                )
            } catch is CancellationError {
                resetPlaybackState()
            } catch {
                errorMessage = error.localizedDescription
                resetPlaybackState(keepError: true)
            }

            preparationTask = nil
        }
    }

    func pause() {
        guard audioPlayer?.isPlaying == true else {
            return
        }

        audioPlayer?.pause()
        syncPlaybackProgress()
        stopProgressTimer()
        isPaused = true
        isSpeaking = false
        updateNowPlayingInfo()
        savePlaybackPosition()
    }

    func continueSpeaking() {
        guard audioPlayer != nil, isPaused else {
            return
        }

        do {
            try startPlayback()
        } catch {
            errorMessage = error.localizedDescription
            resetPlaybackState(keepError: true)
        }
    }

    func seek(to time: TimeInterval) {
        let boundedTime = min(max(time, 0), max(duration, 0))

        guard boundedTime.isFinite else {
            return
        }

        do {
            if let combinedAudioURL {
                if !isUsingCombinedPlayer {
                    let shouldResume = isSpeaking
                    let shouldRemainPaused = isPaused
                    try replacePlayer(with: combinedAudioURL, at: boundedTime)
                    isUsingCombinedPlayer = true
                    duration = audioPlayer?.duration ?? duration
                    downloadedDuration = duration
                    currentTime = boundedTime

                    if shouldResume {
                        try startPlayback()
                    } else if shouldRemainPaused {
                        enterPausedState()
                    } else {
                        syncPlaybackProgress()
                    }
                } else {
                    audioPlayer?.currentTime = boundedTime
                    currentTime = boundedTime
                }
            } else if !preparedChunkURLs.isEmpty {
                try seekWithinPreparedChunks(to: boundedTime)
            } else {
                return
            }

            updateNowPlayingInfo()
        } catch {
            errorMessage = error.localizedDescription
            resetPlaybackState(keepError: true)
        }
    }

    func skip(by delta: TimeInterval) {
        seek(to: currentPlaybackTime() + delta)
    }

    func stop() {
        savePlaybackPosition()
        preparationTask?.cancel()
        preparationTask = nil
        audioPlayer?.stop()
        resetPlaybackState()
    }

    func savePlaybackPosition() {
        guard let bookID = currentBookID, duration > 0 else { return }
        let time = currentPlaybackTime()
        if time >= duration - 1 {
            PlaybackPositionStore.clear(for: bookID)
        } else {
            PlaybackPositionStore.save(time: time, duration: duration, for: bookID)
        }
    }

    private func preparePlayback(
        for text: String,
        bookID: String,
        title: String,
        apiKey: String,
        model: String,
        voice: String,
        audioKey: String
    ) async throws {
        if let cachedCombinedURL = CombinedSpeechCache.url(text: text, model: model, voice: voice) {
            currentAudioKey = audioKey
            currentBookID = bookID
            currentTitle = title
            combinedAudioURL = cachedCombinedURL
            totalChunkCount = 1
            downloadedChunkCount = 1
            preparedChunkURLs = []
            preparedChunkDurations = []
            currentChunkIndex = 0
            playbackOffset = 0
            waitingForChunkIndex = nil
            isUsingCombinedPlayer = true
            isPreparingFullTrack = false

            let savedPosition = PlaybackPositionStore.savedPosition(for: bookID)
            let startTime = savedPosition?.time ?? 0

            try replacePlayer(with: cachedCombinedURL, at: startTime)
            duration = audioPlayer?.duration ?? 0
            downloadedDuration = duration
            currentTime = min(startTime, duration)
            try startPlayback()
            return
        }

        let chunks = Self.playbackChunks(text)
        guard let firstChunk = chunks.first else {
            return
        }

        totalChunkCount = chunks.count

        let firstChunkURL = try await audioChunkURL(for: firstChunk, apiKey: apiKey, model: model, voice: voice)
        try Task.checkCancellation()

        let firstChunkDuration = try await Self.duration(for: firstChunkURL)
        try Task.checkCancellation()

        let savedPosition = PlaybackPositionStore.savedPosition(for: bookID)
        let isSingleChunk = chunks.count == 1
        let startTime = (isSingleChunk ? savedPosition?.time : nil) ?? 0

        currentAudioKey = audioKey
        currentBookID = bookID
        currentTitle = title
        combinedAudioURL = isSingleChunk ? firstChunkURL : nil
        preparedChunkURLs = [firstChunkURL]
        preparedChunkDurations = [firstChunkDuration]
        downloadedChunkCount = 1
        currentChunkIndex = 0
        playbackOffset = 0
        waitingForChunkIndex = nil
        isUsingCombinedPlayer = isSingleChunk
        isPreparingFullTrack = !isSingleChunk
        duration = firstChunkDuration
        downloadedDuration = firstChunkDuration
        currentTime = min(startTime, firstChunkDuration)

        try replacePlayer(with: firstChunkURL, at: startTime)
        try startPlayback()

        guard chunks.count > 1 else {
            return
        }

        for chunk in chunks.dropFirst() {
            let nextChunkURL = try await audioChunkURL(for: chunk, apiKey: apiKey, model: model, voice: voice)
            try Task.checkCancellation()

            guard currentAudioKey == audioKey else {
                return
            }

            let nextChunkDuration = try await Self.duration(for: nextChunkURL)
            preparedChunkURLs.append(nextChunkURL)
            preparedChunkDurations.append(nextChunkDuration)
            downloadedChunkCount = preparedChunkURLs.count
            duration = totalPreparedDuration
            downloadedDuration = totalPreparedDuration

            if let waitingForChunkIndex, waitingForChunkIndex < preparedChunkURLs.count {
                self.waitingForChunkIndex = nil
                try startPreparedChunk(at: waitingForChunkIndex)
            }
        }

        try Task.checkCancellation()
        guard currentAudioKey == audioKey else {
            return
        }

        let combinedURL = try await CombinedSpeechCache.combinedURL(
            from: preparedChunkURLs,
            text: text,
            model: model,
            voice: voice
        )

        try Task.checkCancellation()
        guard currentAudioKey == audioKey else {
            return
        }

        try activateCombinedPlayback(with: combinedURL)
    }

    private func startPlayback() throws {
        guard let audioPlayer else {
            return
        }

        try configureAudioSession()
        configureRemoteCommands()
        _ = audioPlayer.play()
        isLoading = false
        isSpeaking = true
        isPaused = false
        startProgressTimer()
        syncPlaybackProgress()
        updateNowPlayingInfo()
    }

    private func startPreparedChunk(at index: Int) throws {
        guard index < preparedChunkURLs.count else {
            return
        }

        currentChunkIndex = index
        try replacePlayer(with: preparedChunkURLs[index], at: 0)
        try startPlayback()
    }

    private func seekWithinPreparedChunks(to time: TimeInterval) throws {
        let target = preparedChunkTarget(for: time)
        let shouldResume = isSpeaking || waitingForChunkIndex != nil
        let shouldRemainPaused = isPaused

        waitingForChunkIndex = nil
        currentChunkIndex = target.index
        playbackOffset = target.offset

        try replacePlayer(with: preparedChunkURLs[target.index], at: target.localTime)
        isLoading = false
        currentTime = time

        if shouldResume {
            try startPlayback()
        } else if shouldRemainPaused {
            enterPausedState()
        } else {
            syncPlaybackProgress()
        }
    }

    private func activateCombinedPlayback(with combinedURL: URL) throws {
        let shouldResume = isSpeaking
        let shouldRemainPaused = isPaused
        let targetTime = currentPlaybackTime()

        combinedAudioURL = combinedURL
        isPreparingFullTrack = false
        isUsingCombinedPlayer = true
        downloadedChunkCount = max(downloadedChunkCount, totalChunkCount)

        try replacePlayer(with: combinedURL, at: targetTime)
        duration = audioPlayer?.duration ?? totalPreparedDuration
        downloadedDuration = duration
        currentTime = min(targetTime, duration)

        if shouldResume {
            try startPlayback()
        } else if shouldRemainPaused {
            enterPausedState()
        } else {
            syncPlaybackProgress()
        }
    }

    private func replacePlayer(with url: URL, at time: TimeInterval) throws {
        let player = try AVAudioPlayer(contentsOf: url)
        player.delegate = self
        player.prepareToPlay()
        player.currentTime = min(max(time, 0), player.duration)

        audioPlayer?.stop()
        audioPlayer = player
    }

    private func enterPausedState() {
        stopProgressTimer()
        isLoading = false
        isSpeaking = false
        isPaused = true
        syncPlaybackProgress()
        updateNowPlayingInfo()
    }

    private var positionSaveCounter = 0

    private func startProgressTimer() {
        stopProgressTimer()
        positionSaveCounter = 0

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.syncPlaybackProgress()
                self.positionSaveCounter += 1
                if self.positionSaveCounter >= 25 {
                    self.positionSaveCounter = 0
                    self.savePlaybackPosition()
                }
            }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func syncPlaybackProgress() {
        guard let audioPlayer else {
            currentTime = playbackOffset
            if isUsingCombinedPlayer {
                duration = max(duration, 0)
            }
            return
        }

        if isUsingCombinedPlayer {
            currentTime = audioPlayer.currentTime
            duration = audioPlayer.duration
        } else {
            currentTime = playbackOffset + audioPlayer.currentTime
        }
    }

    private func currentPlaybackTime() -> TimeInterval {
        guard let audioPlayer else {
            return playbackOffset
        }

        if isUsingCombinedPlayer {
            return audioPlayer.currentTime
        }

        return playbackOffset + audioPlayer.currentTime
    }

    private func preparedChunkTarget(for time: TimeInterval) -> (index: Int, offset: TimeInterval, localTime: TimeInterval) {
        let boundedTime = min(max(time, 0), totalPreparedDuration)
        var runningOffset: TimeInterval = 0

        for (index, chunkDuration) in preparedChunkDurations.enumerated() {
            let chunkEnd = runningOffset + chunkDuration
            if boundedTime < chunkEnd || index == preparedChunkDurations.indices.last {
                return (index, runningOffset, boundedTime - runningOffset)
            }
            runningOffset = chunkEnd
        }

        return (0, 0, 0)
    }

    private var totalPreparedDuration: TimeInterval {
        preparedChunkDurations.reduce(0, +)
    }

    private func resetPlaybackState(keepError: Bool = false) {
        preparationTask?.cancel()
        preparationTask = nil
        isLoading = false
        isSpeaking = false
        isPaused = false
        isPreparingFullTrack = false
        currentBookID = nil
        currentTitle = nil
        currentTime = 0
        duration = 0
        downloadedDuration = 0
        downloadedChunkCount = 0
        totalChunkCount = 0
        currentAudioKey = nil
        combinedAudioURL = nil
        preparedChunkURLs = []
        preparedChunkDurations = []
        currentChunkIndex = 0
        playbackOffset = 0
        isUsingCombinedPlayer = false
        waitingForChunkIndex = nil
        nowPlayingArtwork = nil
        stopProgressTimer()
        audioPlayer = nil
        tearDownRemoteCommands()
        clearNowPlayingInfo()
        deactivateAudioSession()

        if !keepError {
            errorMessage = nil
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()

        // Use the playback category so spoken audio continues when the app backgrounds or the screen locks.
        try session.setCategory(.playback, mode: .spokenAudio)

        if !hasActiveAudioSession {
            try session.setActive(true)
            hasActiveAudioSession = true
        }

        registerInterruptionObserver()
    }

    private func registerInterruptionObserver() {
        guard interruptionObserver == nil else { return }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleInterruption(notification)
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            if isSpeaking {
                audioPlayer?.pause()
                syncPlaybackProgress()
                stopProgressTimer()
                isPaused = true
                isSpeaking = false
                updateNowPlayingInfo()
                savePlaybackPosition()
            }

        case .ended:
            guard isPaused else { return }
            let shouldResume = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map { AVAudioSession.InterruptionOptions(rawValue: $0).contains(.shouldResume) } ?? false
            if shouldResume {
                do {
                    try startPlayback()
                } catch {
                    errorMessage = error.localizedDescription
                    resetPlaybackState(keepError: true)
                }
            }

        @unknown default:
            break
        }
    }

    private var remoteCommandsConfigured = false

    private func configureRemoteCommands() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true

        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.continueSpeaking() }
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.isSpeaking {
                    self.pause()
                } else if self.isPaused {
                    self.continueSpeaking()
                }
            }
            return .success
        }

        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: 15) }
            return .success
        }

        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.skip(by: -15) }
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func tearDownRemoteCommands() {
        guard remoteCommandsConfigured else { return }
        remoteCommandsConfigured = false

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
    }

    private func loadArtwork(for bookID: String) {
        guard let book = Book.catalog.first(where: { $0.id == bookID })
                ?? BookStore.loadPersistedBooksList().first(where: { $0.id == bookID }) else { return }

        Task { [weak self] in
            guard let image = await BookCoverService.shared.image(for: book) else { return }
            guard let self, self.currentBookID == bookID else { return }
            self.nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.updateNowPlayingInfo()
        }
    }

    private func updateNowPlayingInfo() {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = currentTitle ?? "Book Digest"
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isSpeaking ? 1.0 : 0.0
        if let nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = nowPlayingArtwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func deactivateAudioSession() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }

        guard hasActiveAudioSession else {
            return
        }

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            // Keep teardown best-effort so stop/failure paths do not surface a secondary error.
        }

        hasActiveAudioSession = false
    }

    private func audioChunkURL(for text: String, apiKey: String, model: String, voice: String) async throws -> URL {
        if let cachedURL = SpeechAudioCache.url(text: text, model: model, voice: voice) {
            if let data = try? Data(contentsOf: cachedURL, options: .mappedIfSafe),
               Self.looksLikeAudio(data) {
                return cachedURL
            }
            try? FileManager.default.removeItem(at: cachedURL)
        }

        let generatedAudio = try await Self.createSpeech(text: text, apiKey: apiKey, model: model, voice: voice)
        return try SpeechAudioCache.save(generatedAudio, text: text, model: model, voice: voice)
    }

    private static func duration(for url: URL) async throws -> TimeInterval {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        return CMTimeGetSeconds(duration)
    }

    private static func createSpeech(text: String, apiKey: String, model: String, voice: String) async throws -> Data {
        let encodedVoice = voice.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? voice
        guard let url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(encodedVoice)?output_format=mp3_44100_128") else {
            throw SpeechControllerError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.addValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("audio/mpeg", forHTTPHeaderField: "Accept")

        let payload = SpeechRequest(text: text, modelId: model)
        request.httpBody = try JSONEncoder.elevenLabs.encode(payload)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.elevenLabs.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw SpeechControllerError.timedOut
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpeechControllerError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = ElevenLabsErrorParser.message(from: data)
                ?? "ElevenLabs speech returned status \(httpResponse.statusCode)."
            throw SpeechControllerError.requestFailed(message)
        }

        guard !data.isEmpty else {
            throw SpeechControllerError.emptyAudio
        }

        guard Self.looksLikeAudio(data) else {
            let body = String(data: data.prefix(500), encoding: .utf8) ?? "unknown"
            throw SpeechControllerError.requestFailed("ElevenLabs returned non-audio data: \(body)")
        }

        return data
    }

    private static func looksLikeAudio(_ data: Data) -> Bool {
        guard data.count >= 3 else { return false }
        let b0 = data[0], b1 = data[1], b2 = data[2]
        // MP3 sync word (0xFF followed by 0xE0+ mask)
        if b0 == 0xFF, b1 & 0xE0 == 0xE0 { return true }
        // ID3 tag header
        if b0 == 0x49, b1 == 0x44, b2 == 0x33 { return true }
        return false
    }

    private static func playbackChunks(
        _ text: String,
        initialMaxCharacters: Int = 900,
        remainingMaxCharacters: Int = 3_000
    ) -> [String] {
        let initialChunks = chunk(text, maxCharacters: initialMaxCharacters)
        guard let firstChunk = initialChunks.first else {
            return []
        }

        let remainder = initialChunks.dropFirst().joined(separator: "\n\n")
        guard !remainder.isEmpty else {
            return [firstChunk]
        }

        return [firstChunk] + chunk(remainder, maxCharacters: remainingMaxCharacters)
    }

    private static func chunk(_ text: String, maxCharacters: Int = 3_000) -> [String] {
        let paragraphs = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var current = ""

        for paragraph in paragraphs {
            if paragraph.count > maxCharacters {
                if !current.isEmpty {
                    chunks.append(current)
                    current = ""
                }

                chunks.append(contentsOf: splitLongParagraph(paragraph, maxCharacters: maxCharacters))
                continue
            }

            if current.isEmpty {
                current = paragraph
            } else if current.count + paragraph.count + 2 <= maxCharacters {
                current += "\n\n\(paragraph)"
            } else {
                chunks.append(current)
                current = paragraph
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }

    private static func splitLongParagraph(_ paragraph: String, maxCharacters: Int) -> [String] {
        let sentences = paragraph
            .components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var chunks: [String] = []
        var current = ""

        for sentence in sentences {
            let sentenceText = sentence.hasSuffix(".") ? sentence : "\(sentence)."
            if current.isEmpty {
                current = sentenceText
            } else if current.count + sentenceText.count + 1 <= maxCharacters {
                current += " \(sentenceText)"
            } else {
                chunks.append(current)
                current = sentenceText
            }
        }

        if !current.isEmpty {
            chunks.append(current)
        }

        return chunks
    }
}

extension SpeechController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard flag else {
                errorMessage = "Audio playback did not finish successfully."
                resetPlaybackState(keepError: true)
                return
            }

            if isUsingCombinedPlayer {
                if let bookID = currentBookID {
                    PlaybackPositionStore.clear(for: bookID)
                }
                resetPlaybackState()
                return
            }

            playbackOffset += preparedChunkDurations[currentChunkIndex]
            currentTime = playbackOffset

            let nextChunkIndex = currentChunkIndex + 1
            if nextChunkIndex < preparedChunkURLs.count {
                do {
                    try startPreparedChunk(at: nextChunkIndex)
                } catch {
                    errorMessage = error.localizedDescription
                    resetPlaybackState(keepError: true)
                }
            } else if isPreparingFullTrack {
                waitingForChunkIndex = nextChunkIndex
                audioPlayer = nil
                stopProgressTimer()
                isLoading = true
                isSpeaking = false
                isPaused = false
                deactivateAudioSession()
            } else {
                resetPlaybackState()
            }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            errorMessage = error?.localizedDescription ?? "Audio playback failed."
            resetPlaybackState(keepError: true)
        }
    }
}

private struct SpeechRequest: Encodable {
    let text: String
    let modelId: String

    enum CodingKeys: String, CodingKey {
        case text
        case modelId = "model_id"
    }
}

private enum ElevenLabsErrorParser {
    static func message(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }

        if let dict = json as? [String: Any] {
            if let detail = dict["detail"] as? String {
                return detail
            }
            if let detail = dict["detail"] as? [String: Any] {
                if let message = detail["message"] as? String {
                    return message
                }
                if let status = detail["status"] as? String {
                    return status
                }
            }
            if let message = dict["message"] as? String {
                return message
            }
        }

        return nil
    }
}

private enum SpeechControllerError: LocalizedError {
    case invalidURL
    case invalidResponse
    case requestFailed(String)
    case emptyAudio
    case timedOut
    case invalidCacheLocation
    case missingAudioTrack
    case failedToAssembleAudio

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The ElevenLabs speech endpoint is not valid."
        case .invalidResponse:
            return "The response from ElevenLabs was not valid."
        case .requestFailed(let message):
            return message
        case .emptyAudio:
            return "ElevenLabs returned empty audio."
        case .timedOut:
            return "ElevenLabs took too long to prepare audio."
        case .invalidCacheLocation:
            return "The app could not prepare local audio storage."
        case .missingAudioTrack:
            return "One of the generated speech clips could not be read."
        case .failedToAssembleAudio:
            return "The generated speech clips could not be combined."
        }
    }
}

private extension URLSession {
    static var elevenLabs: URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 180
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }
}

private extension JSONEncoder {
    static var elevenLabs: JSONEncoder {
        JSONEncoder()
    }
}

private enum SpeechAudioCache {
    private static let directoryName = "SpeechCache"

    static func url(text: String, model: String, voice: String) -> URL? {
        guard let fileURL = fileURL(text: text, model: model, voice: voice),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        return fileURL
    }

    static func save(_ audioData: Data, text: String, model: String, voice: String) throws -> URL {
        guard let fileURL = fileURL(text: text, model: model, voice: voice) else {
            throw SpeechControllerError.invalidCacheLocation
        }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try audioData.write(to: fileURL, options: .atomic)
        return fileURL
    }

    static func cacheKey(text: String, model: String, voice: String) -> String {
        let cacheInput = "\(model)\n\(voice)\n\(text)"
        let digest = SHA256.hash(data: Data(cacheInput.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func fileURL(text: String, model: String, voice: String) -> URL? {
        guard let directoryURL = directoryURL() else {
            return nil
        }

        return directoryURL.appendingPathComponent(cacheKey(text: text, model: model, voice: voice))
            .appendingPathExtension("mp3")
    }

    private static func directoryURL() -> URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "BookDigest", isDirectory: true)
        .appendingPathComponent(directoryName, isDirectory: true)
    }
}

private enum CombinedSpeechCache {
    private static let directoryName = "CombinedSpeechCache"

    static func url(text: String, model: String, voice: String) -> URL? {
        guard let outputURL = fileURL(text: text, model: model, voice: voice),
              FileManager.default.fileExists(atPath: outputURL.path) else {
            return nil
        }

        return outputURL
    }

    static func combinedURL(from chunkURLs: [URL], text: String, model: String, voice: String) async throws -> URL {
        guard let outputURL = fileURL(text: text, model: model, voice: voice) else {
            throw SpeechControllerError.invalidCacheLocation
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            return outputURL
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let composition = AVMutableComposition()
        guard let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw SpeechControllerError.failedToAssembleAudio
        }

        var insertionTime = CMTime.zero

        for chunkURL in chunkURLs {
            let asset = AVURLAsset(url: chunkURL)
            let tracks = try await asset.load(.tracks)
            guard let sourceTrack = tracks.first(where: { $0.mediaType == .audio }) else {
                throw SpeechControllerError.missingAudioTrack
            }

            let assetDuration = try await asset.load(.duration)
            try audioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: assetDuration),
                of: sourceTrack,
                at: insertionTime
            )
            insertionTime = CMTimeAdd(insertionTime, assetDuration)
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw SpeechControllerError.failedToAssembleAudio
        }
        let exportSessionBox = ExportSessionBox(exportSession)

        exportSessionBox.session.outputURL = outputURL
        exportSessionBox.session.outputFileType = .m4a

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exportSessionBox.session.exportAsynchronously {
                switch exportSessionBox.session.status {
                case .completed:
                    continuation.resume(returning: ())
                case .failed:
                    continuation.resume(
                        throwing: exportSessionBox.session.error ?? SpeechControllerError.failedToAssembleAudio
                    )
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                default:
                    continuation.resume(throwing: SpeechControllerError.failedToAssembleAudio)
                }
            }
        }

        return outputURL
    }

    private static func fileURL(text: String, model: String, voice: String) -> URL? {
        guard let directoryURL = directoryURL() else {
            return nil
        }

        return directoryURL.appendingPathComponent(SpeechAudioCache.cacheKey(text: text, model: model, voice: voice))
            .appendingPathExtension("m4a")
    }

    private static func directoryURL() -> URL? {
        try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "BookDigest", isDirectory: true)
        .appendingPathComponent(directoryName, isDirectory: true)
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

enum PlaybackPositionStore {
    private static let prefix = "playback.position."
    private static let durationPrefix = "playback.duration."

    static func save(time: TimeInterval, duration: TimeInterval, for bookID: String) {
        UserDefaults.standard.set(time, forKey: prefix + bookID)
        UserDefaults.standard.set(duration, forKey: durationPrefix + bookID)
    }

    static func savedPosition(for bookID: String) -> (time: TimeInterval, duration: TimeInterval)? {
        let time = UserDefaults.standard.double(forKey: prefix + bookID)
        let duration = UserDefaults.standard.double(forKey: durationPrefix + bookID)
        guard time > 0, duration > 0 else { return nil }
        return (time, duration)
    }

    static func clear(for bookID: String) {
        UserDefaults.standard.removeObject(forKey: prefix + bookID)
        UserDefaults.standard.removeObject(forKey: durationPrefix + bookID)
    }
}
