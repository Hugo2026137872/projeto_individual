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
                let workKey = (doc["key"] as? String)?.replacingOccurrences(of: "/works/", with: "")
                let firstIsbn = isbns.first ?? workKey ?? UUID().uuidString
                
                var coverURL: URL? = nil
                if let coverId = doc["cover_i"] as? Int {
                    coverURL = URL(string: "https://covers.openlibrary.org/b/id/\(coverId)-M.jpg")
                }
                
                return Book(id: firstIsbn, title: title, authors: authors, isbn: isbns.first ?? "", coverURL: coverURL)
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

// MARK: - Auth Session Storage
enum AuthSession {
    private static let tokenKey = "booknest_auth_token"
    private static let userKey = "booknest_auth_user"
    
    static var token: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: tokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: tokenKey)
            }
        }
    }
    
    static var user: User? {
        get {
            guard let data = UserDefaults.standard.data(forKey: userKey) else { return nil }
            return try? JSONDecoder().decode(User.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: userKey)
            } else {
                UserDefaults.standard.removeObject(forKey: userKey)
            }
        }
    }
    
    static func clear() {
        token = nil
        user = nil
    }
}

enum RepositoryError: LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(statusCode: Int, message: String? = nil)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL do servidor inválido."
        case .unauthorized:
            return "Sessão inválida ou expirada. Inicia sessão novamente."
        case .serverError(let statusCode, let message):
            if let message, !message.isEmpty {
                return message
            }
            return "O servidor respondeu com erro (HTTP \(statusCode))."
        }
    }
}

private func parseServerErrorMessage(from data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let message = json["error"] as? String else {
        return nil
    }
    return message
}

// MARK: - Auth Service
class AuthService {
    private var baseURLString: String {
        ServerConfig.baseURL
    }
    
    private func makeURL(pathComponents: [String]) throws -> URL {
        guard var url = URL(string: baseURLString) else {
            throw RepositoryError.invalidURL
        }
        for component in pathComponents {
            url.appendPathComponent(component)
        }
        return url
    }
    
    private func sendJSONRequest<Body: Encodable>(pathComponents: [String], body: Body) async throws -> (Data, HTTPURLResponse) {
        let url = try makeURL(pathComponents: pathComponents)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, httpResponse)
    }
    
    func register(name: String, email: String, password: String) async throws -> AuthResponse {
        let payload = ["name": name, "email": email, "password": password]
        let (data, response) = try await sendJSONRequest(pathComponents: ["auth", "register"], body: payload)
        guard (200..<300).contains(response.statusCode) else {
            throw RepositoryError.serverError(statusCode: response.statusCode, message: parseServerErrorMessage(from: data))
        }
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }
    
    func login(email: String, password: String) async throws -> AuthResponse {
        let payload = ["email": email, "password": password]
        let (data, response) = try await sendJSONRequest(pathComponents: ["auth", "login"], body: payload)
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 {
                throw RepositoryError.serverError(statusCode: 401, message: parseServerErrorMessage(from: data) ?? "Email ou palavra-passe inválidos.")
            }
            throw RepositoryError.serverError(statusCode: response.statusCode, message: parseServerErrorMessage(from: data))
        }
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }
    
    func fetchCurrentUser(token: String) async throws -> User {
        let url = try makeURL(pathComponents: ["auth", "me"])
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if httpResponse.statusCode == 401 {
            throw RepositoryError.unauthorized
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RepositoryError.serverError(statusCode: httpResponse.statusCode, message: parseServerErrorMessage(from: data))
        }
        return try JSONDecoder().decode(User.self, from: data)
    }
    
    func logout(token: String) async {
        guard let url = try? makeURL(pathComponents: ["auth", "logout"]) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
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
    func fetchReviews(bookId: String, bookTitle: String?) async throws -> [Review]
    func fetchUserReviews() async throws -> [Review]
    func saveReview(_ review: Review) async throws
}

extension BookRepository {
    func fetchReviews(bookId: String) async throws -> [Review] {
        try await fetchReviews(bookId: bookId, bookTitle: nil)
    }
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
    
    func fetchReviews(bookId: String, bookTitle: String?) async throws -> [Review] {
        let reviews = try await fetchReviews()
        let normalizedTitle = bookTitle?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return reviews.filter { review in
            if review.bookId == bookId { return true }
            if let normalizedTitle, !normalizedTitle.isEmpty,
               let reviewTitle = review.bookTitle?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               reviewTitle == normalizedTitle {
                return true
            }
            return false
        }
    }
    
    func fetchUserReviews() async throws -> [Review] {
        let reviews = try await fetchReviews()
        if let currentName = AuthSession.user?.name {
            return reviews.filter { $0.username.caseInsensitiveCompare(currentName) == .orderedSame }
        }
        return reviews
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
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractionalFormatter.date(from: dateString) {
                return date
            }
            
            let standardFormatter = ISO8601DateFormatter()
            standardFormatter.formatOptions = [.withInternetDateTime]
            if let date = standardFormatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date string: \(dateString)"
            )
        }
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
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token = AuthSession.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }
    
    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if httpResponse.statusCode == 401 {
            throw RepositoryError.unauthorized
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw RepositoryError.serverError(
                statusCode: httpResponse.statusCode,
                message: parseServerErrorMessage(from: data)
            )
        }
    }
    
    func checkHealth() async -> Bool {
        guard let url = try? makeURL(pathComponents: ["health"]) else { return false }
        let request = makeRequest(url: url, method: "GET")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            try validateResponse(response, data: data)
            return true
        } catch {
            return false
        }
    }
    
    func fetchBooks() async throws -> [Book] {
        let url = try makeURL(pathComponents: ["books"])
        let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url, method: "GET"))
        try validateResponse(response, data: data)
        return try makeDecoder().decode([Book].self, from: data)
    }
    
    func fetchBook(bookId: String) async throws -> Book? {
        let url = try makeURL(pathComponents: ["books", bookId])
        let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url, method: "GET"))
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 {
            return nil
        }
        try validateResponse(response, data: data)
        return try makeDecoder().decode(Book.self, from: data)
    }
    
    func saveBook(_ book: Book) async throws {
        let url = try makeURL(pathComponents: ["books"])
        let body = try makeEncoder().encode(book)
        let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url, method: "POST", body: body))
        try validateResponse(response, data: data)
    }
    
    func updateBookStatus(bookId: String, status: ReadingStatus) async throws {
        let url = try makeURL(pathComponents: ["books", bookId])
        let body = try makeEncoder().encode(["status": status.rawValue])
        let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url, method: "PATCH", body: body))
        try validateResponse(response, data: data)
    }
    
    func deleteBook(bookId: String) async throws {
        let url = try makeURL(pathComponents: ["books", bookId])
        let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url, method: "DELETE"))
        try validateResponse(response, data: data)
    }
    
    func fetchReviews() async throws -> [Review] {
        let url = try makeURL(pathComponents: ["reviews"])
        let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url, method: "GET"))
        try validateResponse(response, data: data)
        return try makeDecoder().decode([Review].self, from: data)
    }
    
    func fetchReviews(bookId: String, bookTitle: String?) async throws -> [Review] {
        var queryItems = [URLQueryItem(name: "bookId", value: bookId)]
        if let bookTitle, !bookTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "title", value: bookTitle))
        }
        let url = try makeURL(
            pathComponents: ["reviews"],
            queryItems: queryItems
        )
        let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url, method: "GET"))
        try validateResponse(response, data: data)
        return try makeDecoder().decode([Review].self, from: data)
    }
    
    func fetchUserReviews() async throws -> [Review] {
        let url = try makeURL(
            pathComponents: ["reviews"],
            queryItems: [URLQueryItem(name: "mine", value: "true")]
        )
        let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url, method: "GET"))
        try validateResponse(response, data: data)
        return try makeDecoder().decode([Review].self, from: data)
    }
    
    func saveReview(_ review: Review) async throws {
        let url = try makeURL(pathComponents: ["reviews"])
        let body = try makeEncoder().encode(review)
        let (data, response) = try await URLSession.shared.data(for: makeRequest(url: url, method: "POST", body: body))
        try validateResponse(response, data: data)
    }
}

// MARK: - User Library Manager
@MainActor
class LibraryManager: ObservableObject {
    @Published var currentUser: User? = nil
    @Published var books: [Book] = []
    @Published var reviews: [Review] = []
    @Published var userReviews: [Review] = []
    @Published var isLoadingData: Bool = false
    @Published var errorMessage: String? = nil
    
    var isAuthenticated: Bool {
        currentUser != nil && AuthSession.token != nil
    }
    
    var firstName: String {
        let name = currentUser?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.split(separator: " ").first.map(String.init) ?? "Leitor"
    }
    
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
    private let authService: AuthService
    private var pendingBookMutations = 0
    
    init(repository: BookRepository = RemoteBookRepository(), authService: AuthService = AuthService()) {
        self.repository = repository
        self.authService = authService
        
        if let savedUser = AuthSession.user, AuthSession.token != nil {
            self.currentUser = savedUser
            Task { await restoreSession() }
        }
    }
    
    func restoreSession() async {
        guard let token = AuthSession.token else { return }
        do {
            let freshUser = try await authService.fetchCurrentUser(token: token)
            self.currentUser = freshUser
            AuthSession.user = freshUser
            await loadInitialData()
        } catch RepositoryError.unauthorized {
            clearLocalSession()
        } catch {
            // Keep cached user if server is temporarily unreachable and surface error
            await loadInitialData()
        }
    }
    
    func register(name: String, email: String, password: String) async throws {
        let response = try await authService.register(name: name, email: email, password: password)
        AuthSession.token = response.token
        AuthSession.user = response.user
        self.currentUser = response.user
        self.selectedTab = 0
        await loadInitialData()
    }
    
    func login(email: String, password: String) async throws {
        let response = try await authService.login(email: email, password: password)
        AuthSession.token = response.token
        AuthSession.user = response.user
        self.currentUser = response.user
        self.selectedTab = 0
        await loadInitialData()
    }
    
    func logout() async {
        if let token = AuthSession.token {
            await authService.logout(token: token)
        }
        clearLocalSession()
    }
    
    private func clearLocalSession() {
        AuthSession.clear()
        self.currentUser = nil
        self.books = []
        self.reviews = []
        self.userReviews = []
        self.errorMessage = nil
        self.selectedTab = 0
        resetAllNavigation()
    }
    
    func loadInitialData() async {
        guard isAuthenticated else { return }
        isLoadingData = true
        errorMessage = nil
        do {
            async let fetchedBooks = repository.fetchBooks()
            async let fetchedReviews = repository.fetchReviews()
            async let fetchedUserReviews = repository.fetchUserReviews()
            self.books = try await fetchedBooks
            self.reviews = try await fetchedReviews
            self.userReviews = try await fetchedUserReviews
        } catch RepositoryError.unauthorized {
            clearLocalSession()
        } catch {
            self.errorMessage = "Erro ao ligar ao servidor: \(error.localizedDescription)"
            print("Erro ao carregar dados: \(error.localizedDescription)")
        }
        isLoadingData = false
    }
    
    func refreshBooks() async {
        guard isAuthenticated else { return }
        if pendingBookMutations > 0 { return }
        isLoadingData = true
        do {
            let fetchedBooks = try await repository.fetchBooks()
            if pendingBookMutations == 0 {
                self.books = fetchedBooks
            }
            errorMessage = nil
        } catch RepositoryError.unauthorized {
            clearLocalSession()
        } catch {
            self.errorMessage = "Erro ao carregar biblioteca: \(error.localizedDescription)"
        }
        isLoadingData = false
    }
    
    func refreshBookDetails(book: Book) async {
        guard isAuthenticated else { return }
        do {
            async let fetchedBook = repository.fetchBook(bookId: book.id)
            async let fetchedReviews = repository.fetchReviews(bookId: book.id, bookTitle: book.title)
            
            if let updatedBook = try await fetchedBook {
                if let index = books.firstIndex(where: { $0.id == book.id }) {
                    books[index] = updatedBook
                } else {
                    books.append(updatedBook)
                }
            }
            
            let bookReviews = try await fetchedReviews
            mergeBookReviews(bookReviews, for: book)
            errorMessage = nil
        } catch RepositoryError.unauthorized {
            clearLocalSession()
        } catch {
            self.errorMessage = "Erro ao carregar detalhes do livro: \(error.localizedDescription)"
        }
    }
    
    func fetchReviewsForBook(_ book: Book) async -> [Review] {
        guard isAuthenticated else { return reviewsFor(book: book) }
        do {
            let bookReviews = try await repository.fetchReviews(bookId: book.id, bookTitle: book.title)
            mergeBookReviews(bookReviews, for: book)
            errorMessage = nil
            return bookReviews
        } catch RepositoryError.unauthorized {
            clearLocalSession()
            return []
        } catch {
            self.errorMessage = "Erro ao carregar críticas: \(error.localizedDescription)"
            return reviewsFor(book: book)
        }
    }
    
    private func mergeBookReviews(_ fetched: [Review], for book: Book) {
        let fetchedIds = Set(fetched.map(\.id))
        reviews.removeAll { review in
            fetchedIds.contains(review.id) || matchesBook(review, book: book)
        }
        reviews.insert(contentsOf: fetched, at: 0)
    }
    
    private func matchesBook(_ review: Review, book: Book) -> Bool {
        if review.bookId == book.id { return true }
        let targetTitle = book.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let reviewTitle = review.bookTitle?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return !targetTitle.isEmpty && !reviewTitle.isEmpty && reviewTitle == targetTitle
    }
    
    func refreshUserReviews() async {
        guard isAuthenticated else { return }
        isLoadingData = true
        do {
            self.userReviews = try await repository.fetchUserReviews()
            errorMessage = nil
        } catch RepositoryError.unauthorized {
            clearLocalSession()
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
        pendingBookMutations += 1
        Task {
            do {
                try await repository.saveBook(book)
                errorMessage = nil
            } catch RepositoryError.unauthorized {
                clearLocalSession()
            } catch {
                errorMessage = "Erro ao guardar livro no servidor: \(error.localizedDescription)"
            }
            pendingBookMutations = max(0, pendingBookMutations - 1)
        }
    }
    
    func updateStatus(for bookId: String, status: ReadingStatus) {
        if let index = books.firstIndex(where: { $0.id == bookId }) {
            books[index].status = status
            pendingBookMutations += 1
            Task {
                do {
                    try await repository.updateBookStatus(bookId: bookId, status: status)
                    errorMessage = nil
                } catch RepositoryError.unauthorized {
                    clearLocalSession()
                } catch {
                    errorMessage = "Erro ao atualizar estado no servidor: \(error.localizedDescription)"
                }
                pendingBookMutations = max(0, pendingBookMutations - 1)
            }
        }
    }
    
    func removeBook(bookId: String) {
        books.removeAll { $0.id == bookId }
        pendingBookMutations += 1
        Task {
            do {
                try await repository.deleteBook(bookId: bookId)
                errorMessage = nil
            } catch RepositoryError.unauthorized {
                clearLocalSession()
            } catch {
                errorMessage = "Erro ao remover livro do servidor: \(error.localizedDescription)"
            }
            pendingBookMutations = max(0, pendingBookMutations - 1)
        }
    }
    
    func addReview(bookId: String, bookTitle: String? = nil, content: String, rating: Int) {
        let authorName = currentUser?.name ?? "Utilizador"
        let newReview = Review(
            bookId: bookId,
            bookTitle: bookTitle,
            username: authorName,
            content: content,
            rating: rating
        )
        reviews.insert(newReview, at: 0)
        userReviews.insert(newReview, at: 0)
        
        if let index = books.firstIndex(where: { $0.id == bookId }) {
            books[index].userRating = rating
        }
        
        Task {
            do {
                try await repository.saveReview(newReview)
                errorMessage = nil
            } catch RepositoryError.unauthorized {
                clearLocalSession()
            } catch {
                errorMessage = "Erro ao guardar crítica no servidor: \(error.localizedDescription)"
            }
        }
    }
    
    func reviewsFor(bookId: String) -> [Review] {
        reviews.filter { $0.bookId == bookId }
    }
    
    func reviewsFor(book: Book) -> [Review] {
        reviews.filter { matchesBook($0, book: book) }
    }
}
