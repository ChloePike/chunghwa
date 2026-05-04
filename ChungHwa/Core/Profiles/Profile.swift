import Foundation

enum ProfileSource: Codable, Sendable, Equatable {
    case file
    case url(URL)

    var displayName: String {
        switch self {
        case .file:   return "File"
        case .url(_): return "URL"
        }
    }

    var subscriptionURL: URL? {
        if case .url(let url) = self { return url }
        return nil
    }
}

struct Profile: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var source: ProfileSource
    var importedAt: Date
    var updatedAt: Date
}
