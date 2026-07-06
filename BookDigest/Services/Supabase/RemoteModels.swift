import Foundation

enum RemoteStatus: String, Decodable {
    case pending
    case generating
    case ready
    case failed
}

struct DigestRow: Decodable {
    let bookID: String
    let title: String
    let author: String
    let status: RemoteStatus
    let digestText: String?
    let error: String?
    let audioStatus: RemoteStatus
    let audioStoragePath: String?
    let audioError: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case bookID = "book_id"
        case title
        case author
        case status
        case digestText = "digest_text"
        case error
        case audioStatus = "audio_status"
        case audioStoragePath = "audio_storage_path"
        case audioError = "audio_error"
        case updatedAt = "updated_at"
    }

    var updatedAtDate: Date {
        guard let updatedAt else { return Date() }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: updatedAt) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: updatedAt) ?? Date()
    }
}
