import Foundation
import Combine
import SwiftUI

// MARK: - Open Library API Service
class OpenLibraryService {
    func fetchBookBy(isbn: String) async throws -> Book? {
        let urlString = "https://openlibrary.org/api/books?bibkeys=ISBN:\(isbn)&format=json&jscmd=data"
        guard let url = URL(string: urlString) else { return nil }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
           let bookData = json["ISBN:\(isbn)"] as? [String: Any] {
            
            let title = bookData["title"] as? String ?? "Título Desconhecido"
            var authorsList: [String] = []
            if let authorsMap = bookData["authors"] as? [[String: Any]] {
                authorsList = authorsMap.compactMap { $0["name"] as? String }
            }
            
            var coverURL: URL? = nil
            if let coverMap = bookData["cover"] as? [String: Any],
               let mediumCover = coverMap["medium"] as? String {
                coverURL = URL(string: mediumCover)
            }
            
            return Book(id: isbn, title: title, authors: authorsList, isbn: isbn, coverURL: coverURL)
        }
        return nil
    }
    
    func searchBooks(query: String) async throws -> [Book] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty,
              let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://openlibrary.org/search.json?q=\(encodedQuery)&limit=15") else {
            return []
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
           let docs = json["docs"] as? [[String: Any]] {
            
            return docs.compactMap { doc in
                let title = doc["title"] as? String ?? "Título Desconhecido"
                let authors = doc["author_name"] as? [String] ?? ["Autor Desconhecido"]
                let isbns = doc["isbn"] as? [String] ?? []
                let firstIsbn = isbns.first ?? UUID().uuidString
                
                var coverURL: URL? = nil
                if let coverId = doc["cover_i"] as? Int {
                    coverURL = URL(string: "https://covers.openlibrary.org/b/id/\(coverId)-M.jpg")
                }
                
                return Book(id: firstIsbn, title: title, authors: authors, isbn: firstIsbn, coverURL: coverURL)
            }
        }
        return []
    }
}

// MARK: - Gemma 4 AI Service (Ollama)
class GemmaRecommendationService {
    private let ollamaURL = "http://192.168.221.1:11434/api/generate"
    private let modelName = "gemma4"
    private let openLibrary = OpenLibraryService()
    
    func getRecommendations(for userBooks: [Book]) async -> [RecommendedBook] {
        let prompt = buildPrompt(from: userBooks)
        
        do {
            let rawText = try await callLocalOllama(prompt: prompt)
            
            let cleanJSON = rawText
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard let data = cleanJSON.data(using: .utf8) else { return [] }
            let suggestions = try JSONDecoder().decode([AIRecommendationItem].self, from: data)
            
            var results: [RecommendedBook] = []
            for item in suggestions {
                let query = "\(item.title) \(item.author)"
                if let foundBook = try? await openLibrary.searchBooks(query: query).first {
                    results.append(RecommendedBook(book: foundBook, reason: item.reason))
                } else {
                    let fallbackBook = Book(
                        id: UUID().uuidString,
                        title: item.title,
                        authors: [item.author],
                        isbn: "",
                        coverURL: nil
                    )
                    results.append(RecommendedBook(book: fallbackBook, reason: item.reason))
                }
            }
            return results
            
        } catch {
            print("Erro ao comunicar com Gemma 4: \(error.localizedDescription)")
            return []
        }
    }
    
    private func buildPrompt(from books: [Book]) -> String {
        let list = books.map { book in
            let ratingText = book.userRating != nil ? ", Avaliação: \(book.userRating!)/5" : ""
            return "- '\(book.title)' de \(book.authors.joined(separator: ", ")) (Estado: \(book.status.rawValue)\(ratingText))"
        }.joined(separator: "\n")
        
        return """
        Analisa os seguintes livros da biblioteca pessoal do utilizador:
        \(list.isEmpty ? "O utilizador ainda não adicionou livros." : list)
        
        Sugere 3 livros diferentes que correspondam aos seus gostos literários.
        Responde APENAS com um array JSON válido neste formato exato:
        [
          {"title": "Título do Livro", "author": "Autor", "reason": "Explicação curta de 1 frase em português"}
        ]
        """
    }
    
    private func callLocalOllama(prompt: String) async throws -> String {
        guard let url = URL(string: ollamaURL) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        
        let payload: [String: Any] = [
            "model": modelName,
            "prompt": prompt,
            "stream": false,
            "format": "json"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let responseText = json["response"] as? String {
            return responseText
        }
        return "[]"
    }
}

// MARK: - Server Configuration
enum ServerConfig {
    static let defaultBaseURL = "http://192.168.221.1:3000/api"
    private static let baseURLKey = "booknest_server_base_url"
    
    static var baseURL: String {
        get {
            let saved = UserDefaults.standard.string(forKey: baseURLKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return saved.isEmpty ? defaultBaseURL : saved.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        set {
            let cleaned = newValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            UserDefaults.standard.set(cleaned, forKey: baseURLKey)
        }
    }
}

enum RepositoryError: LocalizedError {
    case invalidURL
    case serverError(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL do servidor inválido."
        case .serverError(let statusCode):
            return "O servidor respondeu com erro (HTTP \(statusCode))."
        }
    }
}

// MARK: - Repository Pattern (Local Persistence + Web Server)
protocol BookRepository {
    func fetchBooks() async throws -> [Book]
    func fetchBook(bookId: String) async throws -> Book?
    func saveBook(_ book: Book) async throws
    func updateBookStatus(bookId: String, status: ReadingStatus) async throws
    func deleteBook(bookId: String) async throws
    
    func fetchReviews() async throws -> [Review]
    func fetchReviews(bookId: String) async throws -> [Review]
    func fetchReviews(username: String) async throws -> [Review]
    func saveReview(_ review: Review) async throws
}

class LocalBookRepository: BookRepository {
    private let booksKey = "booknest_saved_books_v1"
    private let reviewsKey = "booknest_saved_reviews_v1"
    
    func fetchBooks() async throws -> [Book] {
        guard let data = UserDefaults.standard.data(forKey: booksKey) else { return [] }
        return (try? JSONDecoder().decode([Book].self, from: data)) ?? []
    }
    
    func fetchBook(bookId: String) async throws -> Book? {
        let books = try await fetchBooks()
        return books.first(where: { $0.id == bookId })
    }
    
    func saveBook(_ book: Book) async throws {
        var current = try await fetchBooks()
        if !current.contains(where: { $0.id == book.id }) {
            current.append(book)
            if let data = try? JSONEncoder().encode(current) {
                UserDefaults.standard.set(data, forKey: booksKey)
            }
        }
    }
    
    func updateBookStatus(bookId: String, status: ReadingStatus) async throws {
        var current = try await fetchBooks()
        if let index = current.firstIndex(where: { $0.id == bookId }) {
            current[index].status = status
            if let data = try? JSONEncoder().encode(current) {
                UserDefaults.standard.set(data, forKey: booksKey)
            }
        }
    }
    
    func deleteBook(bookId: String) async throws {
        var current = try await fetchBooks()
        current.removeAll { $0.id == bookId }
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: booksKey)
        }
    }
    
    func fetchReviews() async throws -> [Review] {
        guard let data = UserDefaults.standard.data(forKey: reviewsKey) else { return [] }
        return (try? JSONDecoder().decode([Review].self, from: data)) ?? []
    }
    
    func fetchReviews(bookId: String) async throws -> [Review] {
        let reviews = try await fetchReviews()
        return reviews.filter { $0.bookId == bookId }
    }
    
    func fetchReviews(username: String) async throws -> [Review] {
        let reviews = try await fetchReviews()
        return reviews.filter { $0.username.caseInsensitiveCompare(username) == .orderedSame }
    }
    
    func saveReview(_ review: Review) async throws {
        var current = try await fetchReviews()
        current.insert(review, at: 0)
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: reviewsKey)
        }
    }
}

class RemoteBookRepository: BookRepository {
    private var baseURLString: String {
        ServerConfig.baseURL
    }
    
    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
    
    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
    
    private func makeURL(pathComponents: [String] = [], queryItems: [URLQueryItem] = []) throws -> URL {
        guard var url = URL(string: baseURLString) else {
            throw RepositoryError.invalidURL
        }
        for component in pathComponents {
            url.appendPathComponent(component)
        }
        if !queryItems.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw RepositoryError.invalidURL
            }
            components.queryItems = queryItems
            guard let finalURL = components.url else {
                throw RepositoryError.invalidURL
            }
            return finalURL
        }
        return url
    }
    
    private func makeRequest(url: URL, method: String, body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }
    
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RepositoryError.serverError(statusCode: httpResponse.statusCode)
        }
    }
    
    func checkHealth() async -> Bool {
        guard let url = try? makeURL(pathComponents: ["health"]) else { return false }
        let request = makeRequest(url: url, method: "GET")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            try validateResponse(response)
            return true
        } catch {
            return false
        }
    }
    
    func fetchBooks() async throws -> [Book] {
        let url = try makeURL(pathComponents: ["books"])
        let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url, method: "GET"))
        try validateResponse(response)
        return try makeDecoder().decode([Book].self, from: data)
    }
    
    func fetchBook(bookId: String) async throws -> Book? {
        let url = try makeURL(pathComponents: ["books", bookId])
        let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url, method: "GET"))
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
            return nil
        }
        try validateResponse(response)
        return try makeDecoder().decode(Book.self, from: data)
    }
    
    func saveBook(_ book: Book) async throws {
        let url = try makeURL(pathComponents: ["books"])
        let body = try makeEncoder().encode(book)
        let (_, response) = try await URLSession.shared.data(for: makeRequest(url: url, method: "POST", body: body))
        try validateResponse(response)
    }
    
    func updateBookStatus(bookId: String, status: ReadingStatus) async throws {
        let url = try makeURL(pathComponents: ["books", bookId])
        let body = try makeEncoder().encode(["status": status.rawValue])
        let (_, response) = try await URLSession.shared.data(for: makeRequest(url: url, method: "PATCH", body: body))
        try validateResponse(response)
    }
    
    func deleteBook(bookId: String) async throws {
        let url = try makeURL(pathComponents: ["books", bookId])
        let (_, response) = try await URLSession.shared.data(for: makeRequest(url: url, method: "DELETE"))
        try validateResponse(response)
    }
    
    func fetchReviews() async throws -> [Review] {
        let url = try makeURL(pathComponents: ["reviews"])
        let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url, method: "GET"))
        try validateResponse(response)
        return try makeDecoder().decode([Review].self, from: data)
    }
    
    func fetchReviews(bookId: String) async throws -> [Review] {
        let url = try makeURL(
            pathComponents: ["reviews"],
            queryItems: [URLQueryItem(name: "bookId", value: bookId)]
        )
        let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url, method: "GET"))
        try validateResponse(response)
        return try makeDecoder().decode([Review].self, from: data)
    }
    
    func fetchReviews(username: String) async throws -> [Review] {
        let url = try makeURL(
            pathComponents: ["reviews"],
            queryItems: [URLQueryItem(name: "username", value: username)]
        )
        let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url, method: "GET"))
        try validateResponse(response)
        return try makeDecoder().decode([Review].self, from: data)
    }
    
    func saveReview(_ review: Review) async throws {
        let url = try makeURL(pathComponents: ["reviews"])
        let body = try makeEncoder().encode(review)
        let (_, response) = try await URLSession.shared.data(for: makeRequest(url: url, method: "POST", body: body))
        try validateResponse(response)
    }
}

// MARK: - User Library Manager
@MainActor
class LibraryManager: ObservableObject {
    @Published var books: [Book] = []
    @Published var reviews: [Review] = []
    @Published var userReviews: [Review] = []
    @Published var isLoadingData: Bool = false
    @Published var errorMessage: String? = nil
    
    let currentUsername = "Hugo Marques"
    
    @Published var searchPath = NavigationPath()
    @Published var recommendationsPath = NavigationPath()
    @Published var libraryPath = NavigationPath()
    @Published var profilePath = NavigationPath()
    
    @Published var selectedTab: Int = 0 {
        didSet {
            if oldValue != selectedTab {
                resetAllNavigation()
            }
        }
    }
    
    private let repository: BookRepository
    
    init(repository: BookRepository = RemoteBookRepository()) {
        self.repository = repository
        Task { await loadInitialData() }
    }
    
    func loadInitialData() async {
        isLoadingData = true
        errorMessage = nil
        do {
            async let fetchedBooks = repository.fetchBooks()
            async let fetchedReviews = repository.fetchReviews()
            async let fetchedUserReviews = repository.fetchReviews(username: currentUsername)
            self.books = try await fetchedBooks
            self.reviews = try await fetchedReviews
            self.userReviews = try await fetchedUserReviews
        } catch {
            self.errorMessage = "Erro ao ligar ao servidor: \(error.localizedDescription)"
            print("Erro ao carregar dados: \(error.localizedDescription)")
        }
        isLoadingData = false
    }
    
    func refreshBooks() async {
        isLoadingData = true
        do {
            self.books = try await repository.fetchBooks()
            errorMessage = nil
        } catch {
            self.errorMessage = "Erro ao carregar biblioteca: \(error.localizedDescription)"
        }
        isLoadingData = false
    }
    
    func refreshBookDetails(bookId: String) async {
        do {
            async let fetchedBook = repository.fetchBook(bookId: bookId)
            async let fetchedReviews = repository.fetchReviews(bookId: bookId)
            
            if let updatedBook = try await fetchedBook {
                if let index = books.firstIndex(where: { $0.id == bookId }) {
                    books[index] = updatedBook
                } else {
                    books.append(updatedBook)
                }
            }
            
            let bookReviews = try await fetchedReviews
            reviews.removeAll { $0.bookId == bookId }
            reviews.insert(contentsOf: bookReviews, at: 0)
            errorMessage = nil
        } catch {
            self.errorMessage = "Erro ao carregar detalhes do livro: \(error.localizedDescription)"
        }
    }
    
    func refreshReviewsForBook(bookId: String) async {
        do {
            let bookReviews = try await repository.fetchReviews(bookId: bookId)
            reviews.removeAll { $0.bookId == bookId }
            reviews.insert(contentsOf: bookReviews, at: 0)
            errorMessage = nil
        } catch {
            self.errorMessage = "Erro ao carregar críticas: \(error.localizedDescription)"
        }
    }
    
    func refreshUserReviews() async {
        isLoadingData = true
        do {
            self.userReviews = try await repository.fetchReviews(username: currentUsername)
            errorMessage = nil
        } catch {
            self.errorMessage = "Erro ao carregar as tuas avaliações: \(error.localizedDescription)"
        }
        isLoadingData = false
    }
    
    func resetAllNavigation() {
        searchPath = NavigationPath()
        recommendationsPath = NavigationPath()
        libraryPath = NavigationPath()
        profilePath = NavigationPath()
    }
    
    func addBook(_ book: Book) {
        guard !books.contains(where: { $0.id == book.id }) else { return }
        books.append(book)
        Task {
            do {
                try await repository.saveBook(book)
                errorMessage = nil
            } catch {
                errorMessage = "Erro ao guardar livro no servidor: \(error.localizedDescription)"
            }
        }
    }
    
    func updateStatus(for bookId: String, status: ReadingStatus) {
        if let index = books.firstIndex(where: { $0.id == bookId }) {
            books[index].status = status
            Task {
                do {
                    try await repository.updateBookStatus(bookId: bookId, status: status)
                    errorMessage = nil
                } catch {
                    errorMessage = "Erro ao atualizar estado no servidor: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func removeBook(bookId: String) {
        books.removeAll { $0.id == bookId }
        Task {
            do {
                try await repository.deleteBook(bookId: bookId)
                errorMessage = nil
            } catch {
                errorMessage = "Erro ao remover livro do servidor: \(error.localizedDescription)"
            }
        }
    }
    
    func addReview(bookId: String, username: String? = nil, content: String, rating: Int) {
        let authorName = username ?? currentUsername
        let newReview = Review(bookId: bookId, username: authorName, content: content, rating: rating)
        reviews.insert(newReview, at: 0)
        if authorName.caseInsensitiveCompare(currentUsername) == .orderedSame {
            userReviews.insert(newReview, at: 0)
        }
        
        if let index = books.firstIndex(where: { $0.id == bookId }) {
            books[index].userRating = rating
        }
        
        Task {
            do {
                try await repository.saveReview(newReview)
                errorMessage = nil
            } catch {
                errorMessage = "Erro ao guardar crítica no servidor: \(error.localizedDescription)"
            }
        }
    }
    
    func reviewsFor(bookId: String) -> [Review] {
        reviews.filter { $0.bookId == bookId }
    }
}
