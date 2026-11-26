import Foundation

enum ReadingStatus: String, CaseIterable, Codable {
    case interested = "Com interesse"
    case reading = "A ler"
    case read = "Lido"
    case dropped = "Desisti de ler"
}

struct Book: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let authors: [String]
    let isbn: String
    let coverURL: URL?
    var status: ReadingStatus = .interested
    var userRating: Int? = nil
}

struct Review: Identifiable, Codable, Hashable {
    var id = UUID()
    let bookId: String
    let username: String
    let content: String
    let rating: Int
    let date: Date = Date()
}

struct AIRecommendationItem: Codable {
    let title: String
    let author: String
    let reason: String
}

struct RecommendedBook: Identifiable {
    let id = UUID()
    let book: Book
    let reason: String
}
