import Foundation
import Supabase

// Single gateway to the shared digest backend. Reads go straight to Postgres
// via the SDK (RLS read-only); generation goes through the generate-digest
// edge function, which receives the user's API keys per-request and never
// stores them.
@MainActor
final class SupabaseService {
    enum ServiceError: LocalizedError {
        case generationTimedOut
        case generationFailed(String)
        case backendRejected(String)

        var errorDescription: String? {
            switch self {
            case .generationTimedOut:
                return "The digest is still being generated. Check back in a few minutes."
            case .generationFailed(let message):
                return message
            case .backendRejected(let message):
                return message
            }
        }
    }

    private let client: SupabaseClient

    // Generation runs in OpenAI background mode, so a poll can never kill the
    // job — a longer deadline just keeps the UI attached to slow generations.
    private static let pollInterval: Duration = .seconds(5)
    private static let pollDeadline: TimeInterval = 600

    init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.url,
            supabaseKey: SupabaseConfig.publishableKey
        )
    }

    func ensureSignedIn() async throws {
        if (try? await client.auth.session) != nil {
            return
        }
        try await client.auth.signInAnonymously()
    }

    // MARK: - Digest text

    func fetchDigest(bookID: String) async throws -> DigestRow? {
        try await ensureSignedIn()
        let rows: [DigestRow] = try await client
            .from("digests")
            .select()
            .eq("book_id", value: bookID)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    // "Ready" means fully playable: the shelf offers listening, so a digest
    // whose narration failed or hasn't generated yet doesn't belong on it.
    func fetchReadyDigests() async throws -> [DigestRow] {
        try await ensureSignedIn()
        return try await client
            .from("digests")
            .select()
            .eq("status", value: "ready")
            .eq("audio_status", value: "ready")
            .order("updated_at", ascending: false)
            .execute()
            .value
    }

    func requestDigestGeneration(book: Book, openAIKey: String) async throws {
        try await ensureSignedIn()
        let key = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = GenerateRequest(
            action: "digest",
            book: GenerateRequest.BookPayload(
                id: book.id,
                title: book.title,
                author: book.author,
                angle: book.angle
            ),
            openaiKey: key.isEmpty ? nil : key,
            elevenLabsKey: nil
        )
        try await invokeGenerate(body: body)
    }

    // Each poll asks the edge function to check the background response held
    // by OpenAI; whichever poll first sees a terminal state writes the row.
    // The key is needed to read the response and is sent per-request, never
    // stored — same contract as requesting generation.
    func waitForDigest(book: Book, openAIKey: String) async throws -> DigestRow {
        let key = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = GenerateRequest(
            action: "check",
            book: GenerateRequest.BookPayload(
                id: book.id,
                title: book.title,
                author: book.author,
                angle: book.angle
            ),
            openaiKey: key.isEmpty ? nil : key,
            elevenLabsKey: nil
        )

        let deadline = Date().addingTimeInterval(Self.pollDeadline)
        while Date() < deadline {
            try Task.checkCancellation()

            var checked: GenerateResponse?
            do {
                try await ensureSignedIn()
                checked = try await client.functions.invoke(
                    "generate-digest",
                    options: FunctionInvokeOptions(body: body)
                )
            } catch {
                // A failed poll says nothing about the generation itself;
                // keep polling until the deadline.
                checked = nil
            }

            switch checked?.status {
            case "ready":
                if let row = try await fetchDigest(bookID: book.id), row.status == .ready {
                    return row
                }
            case "failed":
                throw ServiceError.generationFailed(checked?.error ?? "Digest generation failed.")
            default:
                break
            }

            try await Task.sleep(for: Self.pollInterval)
        }
        throw ServiceError.generationTimedOut
    }

    // MARK: - Audio

    func requestAudioGeneration(book: Book, elevenLabsKey: String) async throws {
        try await ensureSignedIn()
        let key = elevenLabsKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = GenerateRequest(
            action: "audio",
            book: GenerateRequest.BookPayload(
                id: book.id,
                title: book.title,
                author: book.author,
                angle: book.angle
            ),
            openaiKey: nil,
            elevenLabsKey: key.isEmpty ? nil : key
        )
        try await invokeGenerate(body: body)
    }

    func waitForAudio(bookID: String) async throws -> DigestRow {
        let deadline = Date().addingTimeInterval(Self.pollDeadline)
        while Date() < deadline {
            try Task.checkCancellation()
            if let row = try await fetchDigest(bookID: bookID) {
                if row.audioStatus == .ready, row.audioStoragePath != nil {
                    return row
                }
                if row.audioStatus == .failed {
                    throw ServiceError.generationFailed(Self.friendlyAudioError(row.audioError))
                }
            }
            try await Task.sleep(for: Self.pollInterval)
        }
        throw ServiceError.generationTimedOut
    }

    // Rows written before the edge function started storing user-facing
    // messages hold raw ElevenLabs responses like
    // "ElevenLabs error (status 401): Invalid API key" — translate those
    // instead of showing them verbatim.
    private static func friendlyAudioError(_ stored: String?) -> String {
        guard let stored, !stored.isEmpty else {
            return "Audio generation failed. Please try again."
        }
        guard stored.lowercased().contains("elevenlabs") else {
            return stored
        }
        let lowered = stored.lowercased()
        if lowered.contains("quota") {
            return "The ElevenLabs account is out of credits, so the narration couldn't be generated."
        }
        if lowered.contains("401") || lowered.contains("403")
            || lowered.contains("unauthorized") || lowered.contains("invalid api key") {
            return "ElevenLabs rejected the API key. Check your ElevenLabs key in Settings and try again."
        }
        if lowered.contains("429") || lowered.contains("too many requests") {
            return "ElevenLabs is busy right now. Please try again in a few minutes."
        }
        if lowered.contains("status 5") {
            return "ElevenLabs is having trouble right now. Please try again later."
        }
        return stored
    }

    func signedAudioURL(path: String) async throws -> URL {
        try await ensureSignedIn()
        return try await client.storage
            .from("digest-audio")
            .createSignedURL(path: path, expiresIn: 3600)
    }

    // MARK: - Function invocation

    private struct GenerateRequest: Encodable {
        struct BookPayload: Encodable {
            let id: String
            let title: String
            let author: String
            let angle: String
        }

        let action: String
        let book: BookPayload
        let openaiKey: String?
        let elevenLabsKey: String?
    }

    private struct GenerateResponse: Decodable {
        let status: String?
        let error: String?
    }

    private func invokeGenerate(body: GenerateRequest) async throws {
        do {
            let response: GenerateResponse = try await client.functions.invoke(
                "generate-digest",
                options: FunctionInvokeOptions(body: body)
            )
            if let message = response.error {
                throw ServiceError.backendRejected(message)
            }
        } catch let error as FunctionsError {
            if case .httpError(_, let data) = error,
               let decoded = try? JSONDecoder().decode(GenerateResponse.self, from: data),
               let message = decoded.error {
                throw ServiceError.backendRejected(message)
            }
            throw error
        }
    }
}
