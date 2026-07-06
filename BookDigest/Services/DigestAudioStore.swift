import Foundation

// Local store for shared digest MP3s downloaded from Supabase Storage.
// One file per book: DigestAudio/{bookID}.mp3 under Application Support.
enum DigestAudioStore {
    static func url(for bookID: String) -> URL? {
        let destination = destination(for: bookID)
        guard FileManager.default.fileExists(atPath: destination.path) else {
            return nil
        }
        return destination
    }

    static func destination(for bookID: String) -> URL {
        directory().appendingPathComponent("\(bookID).mp3")
    }

    static func download(
        from remote: URL,
        for bookID: String,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> URL {
        let (bytes, response) = try await URLSession.shared.bytes(from: remote)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let expectedLength = response.expectedContentLength
        var data = Data()
        if expectedLength > 0 {
            data.reserveCapacity(Int(expectedLength))
        }

        var lastReportedFraction = 0.0
        for try await byte in bytes {
            data.append(byte)

            if expectedLength > 0 {
                let fraction = Double(data.count) / Double(expectedLength)
                if fraction - lastReportedFraction >= 0.01 {
                    lastReportedFraction = fraction
                    let capped = min(fraction, 1)
                    await progress(capped)
                }
            }
        }

        guard !data.isEmpty else {
            throw URLError(.zeroByteResource)
        }

        let destination = destination(for: bookID)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
        await progress(1)
        return destination
    }

    private static func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "BookDigest"
        return base.appendingPathComponent(bundleID).appendingPathComponent("DigestAudio")
    }
}
