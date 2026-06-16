import Foundation

struct OpenLibraryClient {
    static func fetchSynopsis(title: String, author: String) async -> String? {
        guard let workKey = await searchWorkKey(title: title, author: author) else { return nil }

        guard let workURL = URL(string: "https://openlibrary.org\(workKey).json"),
              let (workData, workResponse) = try? await URLSession.shared.data(from: workURL),
              let workHTTP = workResponse as? HTTPURLResponse,
              (200..<300).contains(workHTTP.statusCode) else {
            return nil
        }

        let work = try? JSONDecoder().decode(OpenLibraryWork.self, from: workData)
        let description = work?.descriptionText
        guard let description, !description.isEmpty else { return nil }
        return description
    }

    static func fetchTableOfContents(title: String, author: String) async -> [String]? {
        guard var components = URLComponents(string: "https://openlibrary.org/search.json") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "author", value: author),
            URLQueryItem(name: "fields", value: "edition_key"),
            URLQueryItem(name: "limit", value: "1")
        ]

        guard let searchURL = components.url,
              let (searchData, searchResponse) = try? await URLSession.shared.data(from: searchURL),
              let searchHTTP = searchResponse as? HTTPURLResponse,
              (200..<300).contains(searchHTTP.statusCode) else {
            return nil
        }

        let result = try? JSONDecoder().decode(OLEditionSearchResponse.self, from: searchData)
        guard let editionKeys = result?.docs.first?.editionKeys, !editionKeys.isEmpty else {
            return nil
        }

        for editionKey in editionKeys.prefix(5) {
            guard let editionURL = URL(string: "https://openlibrary.org/books/\(editionKey).json"),
                  let (editionData, editionResponse) = try? await URLSession.shared.data(from: editionURL),
                  let editionHTTP = editionResponse as? HTTPURLResponse,
                  (200..<300).contains(editionHTTP.statusCode) else {
                continue
            }

            let edition = try? JSONDecoder().decode(OLEdition.self, from: editionData)
            guard let toc = edition?.tableOfContents, !toc.isEmpty else { continue }

            let titles = toc
                .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
                .map { $0.hasSuffix(" --") ? String($0.dropLast(3)) : $0 }
                .filter { !$0.isEmpty }

            if !titles.isEmpty { return titles }
        }

        return nil
    }

    private static func searchWorkKey(title: String, author: String) async -> String? {
        guard var components = URLComponents(string: "https://openlibrary.org/search.json") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "author", value: author),
            URLQueryItem(name: "fields", value: "key"),
            URLQueryItem(name: "limit", value: "1")
        ]

        guard let searchURL = components.url,
              let (searchData, searchResponse) = try? await URLSession.shared.data(from: searchURL),
              let searchHTTP = searchResponse as? HTTPURLResponse,
              (200..<300).contains(searchHTTP.statusCode) else {
            return nil
        }

        let searchResult = try? JSONDecoder().decode(OpenLibrarySearchResponse.self, from: searchData)
        return searchResult?.docs.first?.key
    }
}

private struct OpenLibrarySearchResponse: Decodable {
    let docs: [OpenLibraryDoc]
}

private struct OpenLibraryDoc: Decodable {
    let key: String
}

private struct OpenLibraryWork: Decodable {
    let description: DescriptionValue?

    var descriptionText: String? {
        description?.text
    }
}

private enum DescriptionValue: Decodable {
    case string(String)
    case object(ObjectDescription)

    var text: String? {
        switch self {
        case .string(let s): return s
        case .object(let o): return o.value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            self = .object(try container.decode(ObjectDescription.self))
        }
    }
}

private struct ObjectDescription: Decodable {
    let value: String
}

private struct OLEditionSearchResponse: Decodable {
    let docs: [OLEditionDoc]
}

private struct OLEditionDoc: Decodable {
    let editionKeys: [String]?

    enum CodingKeys: String, CodingKey {
        case editionKeys = "edition_key"
    }
}

private struct OLEdition: Decodable {
    let tableOfContents: [OLTocItem]?

    enum CodingKeys: String, CodingKey {
        case tableOfContents = "table_of_contents"
    }
}

private struct OLTocItem: Decodable {
    let title: String
}

enum SynopsisStorage {
    static func save(_ text: String, for bookID: String) {
        UserDefaults.standard.set(text, forKey: "synopsis.\(bookID)")
    }

    static func load(for bookID: String) -> String? {
        UserDefaults.standard.string(forKey: "synopsis.\(bookID)")
    }
}

enum ContentsStorage {
    static func save(_ items: [String], for bookID: String) {
        UserDefaults.standard.set(items, forKey: "contents.\(bookID)")
    }

    static func load(for bookID: String) -> [String]? {
        let items = UserDefaults.standard.stringArray(forKey: "contents.\(bookID)")
        guard let items, !items.isEmpty else { return nil }
        return items
    }
}
