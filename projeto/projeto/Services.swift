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

// MARK: - Repository Pattern (Local Persistence + Future Web Server Ready)
protocol BookRepository {
    func fetchBooks() async throws -> [Book]
    func saveBook(_ book: Book) async throws
    func updateBookStatus(bookId: String, status: ReadingStatus) async throws
    func deleteBook(bookId: String) async throws
    
    func fetchReviews() async throws -> [Review]
    func saveReview(_ review: Review) async throws
}

class LocalBookRepository: BookRepository {
    private let booksKey = "booknest_saved_books_v1"
    private let reviewsKey = "booknest_saved_reviews_v1"
    
    func fetchBooks() async throws -> [Book] {
        guard let data = UserDefaults.standard.data(forKey: booksKey) else { return [] }
        return (try? JSONDecoder().decode([Book].self, from: data)) ?? []
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
    
    func saveReview(_ review: Review) async throws {
        var current = try await fetchReviews()
        current.insert(review, at: 0)
        if let data = try? JSONEncoder().encode(current) {
            UserDefaults.standard.set(data, forKey: reviewsKey)
        }
    }
}

class RemoteBookRepository: BookRepository {
    private let baseURL = "https://your-server.com/api"
    
    func fetchBooks() async throws -> [Book] {
        guard let url = URL(string: "\(baseURL)/books") else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([Book].self, from: data)
    }
    
    func saveBook(_ book: Book) async throws {
        guard let url = URL(string: "\(baseURL)/books") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(book)
        _ = try await URLSession.shared.data(for: request)
    }
    
    func updateBookStatus(bookId: String, status: ReadingStatus) async throws {
        guard let url = URL(string: "\(baseURL)/books/\(bookId)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["status": status.rawValue])
        _ = try await URLSession.shared.data(for: request)
    }
    
    func deleteBook(bookId: String) async throws {
        guard let url = URL(string: "\(baseURL)/books/\(bookId)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        _ = try await URLSession.shared.data(for: request)
    }
    
    func fetchReviews() async throws -> [Review] {
        guard let url = URL(string: "\(baseURL)/reviews") else { throw URLError(.badURL) }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([Review].self, from: data)
    }
    
    func saveReview(_ review: Review) async throws {
        guard let url = URL(string: "\(baseURL)/reviews") else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(review)
        _ = try await URLSession.shared.data(for: request)
    }
}

// MARK: - User Library Manager
@MainActor
class LibraryManager: ObservableObject {
    @Published var books: [Book] = []
    @Published var reviews: [Review] = []
    @Published var isLoadingData: Bool = false
    
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
    
    init(repository: BookRepository = LocalBookRepository()) {
        self.repository = repository
        Task { await loadInitialData() }
    }
    
    func loadInitialData() async {
        isLoadingData = true
        do {
            async let fetchedBooks = repository.fetchBooks()
            async let fetchedReviews = repository.fetchReviews()
            self.books = try await fetchedBooks
            self.reviews = try await fetchedReviews
        } catch {
            print("Erro ao carregar dados: \(error.localizedDescription)")
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
        Task { try? await repository.saveBook(book) }
    }
    
    func updateStatus(for bookId: String, status: ReadingStatus) {
        if let index = books.firstIndex(where: { $0.id == bookId }) {
            books[index].status = status
            Task { try? await repository.updateBookStatus(bookId: bookId, status: status) }
        }
    }
    
    func removeBook(bookId: String) {
        books.removeAll { $0.id == bookId }
        Task { try? await repository.deleteBook(bookId: bookId) }
    }
    
    func addReview(bookId: String, username: String = "Hugo Marques", content: String, rating: Int) {
        let newReview = Review(bookId: bookId, username: username, content: content, rating: rating)
        reviews.insert(newReview, at: 0)
        
        if let index = books.firstIndex(where: { $0.id == bookId }) {
            books[index].userRating = rating
        }
        
        Task { try? await repository.saveReview(newReview) }
    }
    
    func reviewsFor(bookId: String) -> [Review] {
        reviews.filter { $0.bookId == bookId }
    }
}
