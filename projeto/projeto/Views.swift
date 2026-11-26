import SwiftUI

// MARK: - Navegação Principal (Auth + TabView)
struct ContentView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    
    var body: some View {
        Group {
            if libraryManager.isAuthenticated {
                TabView(selection: $libraryManager.selectedTab) {
                    InicioView()
                        .tabItem { Label("Início", systemImage: "house") }
                        .tag(0)
                    
                    PesquisarView()
                        .tabItem { Label("Pesquisar", systemImage: "magnifyingglass") }
                        .tag(1)
                    
                    RecomendacoesView()
                        .tabItem { Label("Recomendações", systemImage: "sparkles") }
                        .tag(2)
                    
                    BibliotecaView()
                        .tabItem { Label("Biblioteca", systemImage: "book.closed") }
                        .tag(3)
                    
                    PerfilView()
                        .tabItem { Label("Perfil", systemImage: "person") }
                        .tag(4)
                }
                .tint(.green)
            } else {
                AuthView()
            }
        }
    }
}

// MARK: - Autenticação (Login e Registo)
struct AuthView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @State private var isRegisterMode = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil
    @State private var showingServerSettings = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 56))
                            .foregroundColor(.green)
                        Text("BookNest")
                            .font(.largeTitle)
                            .bold()
                        Text(isRegisterMode ? "Cria a tua conta para começar." : "Inicia sessão na tua biblioteca.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 24)
                    
                    Picker("Modo", selection: $isRegisterMode) {
                        Text("Entrar").tag(false)
                        Text("Criar Conta").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: isRegisterMode) { _ in
                        errorMessage = nil
                    }
                    
                    VStack(spacing: 14) {
                        if isRegisterMode {
                            TextField("Nome completo", text: $name)
                                .textContentType(.name)
                                .padding()
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(12)
                        }
                        
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.emailAddress)
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                        
                        SecureField("Palavra-passe", text: $password)
                            .textContentType(isRegisterMode ? .newPassword : .password)
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                    }
                    
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                    
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isSubmitting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(isRegisterMode ? "Criar Conta" : "Entrar")
                                    .font(.headline)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isSubmitting || !canSubmit)
                    
                    Button {
                        showingServerSettings = true
                    } label: {
                        Label("Configurar Servidor (\(ServerConfig.baseURL))", systemImage: "gearshape")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)
                }
                .padding()
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingServerSettings) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Fechar") {
                                    showingServerSettings = false
                                }
                            }
                        }
                }
            }
        }
    }
    
    private var canSubmit: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if isRegisterMode {
            return !trimmedName.isEmpty && !trimmedEmail.isEmpty && !password.isEmpty
        }
        return !trimmedEmail.isEmpty && !password.isEmpty
    }
    
    @MainActor
    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        do {
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            if isRegisterMode {
                let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                try await libraryManager.register(name: trimmedName, email: trimmedEmail, password: password)
            } else {
                try await libraryManager.login(email: trimmedEmail, password: password)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}

// MARK: - Aba 1: Início
struct InicioView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Olá, \(libraryManager.firstName)!")
                            .font(.largeTitle)
                            .bold()
                        Text("Descobre o teu próximo livro.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                    
                    Button(action: {
                        libraryManager.selectedTab = 1
                    }) {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundColor(.gray)
                            Text("Pesquisar livros, autores, géneros...").foregroundColor(.gray)
                            Spacer()
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Em destaque")
                            .font(.title2)
                            .bold()
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 16) {
                                ZStack(alignment: .bottomLeading) {
                                    Rectangle()
                                        .fill(Color(UIColor.darkGray))
                                        .frame(width: 300, height: 180)
                                        .cornerRadius(16)
                                    
                                    VStack(alignment: .leading) {
                                        Text("O Limiar do Amanhã")
                                            .font(.title3)
                                            .bold()
                                            .foregroundColor(.white)
                                        Text("Hugo Marques")
                                            .font(.subheadline)
                                            .foregroundColor(.white.opacity(0.8))
                                        
                                        HStack(spacing: 2) {
                                            ForEach(0..<5) { _ in
                                                Image(systemName: "star.fill").foregroundColor(.yellow).font(.caption)
                                            }
                                            Text("4.5").font(.caption).bold().foregroundColor(.white)
                                        }
                                        .padding(.top, 2)
                                    }
                                    .padding()
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Explorar")
                            .font(.title2)
                            .bold()
                            .padding(.horizontal)
                        
                        HStack(spacing: 16) {
                            Button(action: { libraryManager.selectedTab = 1 }) {
                                ExplorarCard(icon: "magnifyingglass", title: "Descobrir")
                            }
                            Button(action: { libraryManager.selectedTab = 2 }) {
                                ExplorarCard(icon: "sparkles", title: "Recomendações")
                            }
                            Button(action: { libraryManager.selectedTab = 3 }) {
                                ExplorarCard(icon: "books.vertical", title: "Biblioteca")
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text("BookNest").font(.title2).bold()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { libraryManager.selectedTab = 4 }) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .id(libraryManager.navigationResetID)
    }
}

struct ExplorarCard: View {
    let icon: String
    let title: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
            Text(title)
                .font(.caption)
                .bold()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.green.opacity(0.1))
        .foregroundColor(Color(UIColor.darkGray))
        .cornerRadius(12)
    }
}

// MARK: - Aba 2: Pesquisar
struct PesquisarView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @State private var textoPesquisa = ""
    @State private var filtroSelecionado = "Todos"
    @State private var resultados: [Book] = []
    @State private var isSearching = false
    
    let filtros = ["Todos", "Ficção", "Não-ficção", "Fantasia", "História"]
    private let apiService = OpenLibraryService()
    
    var body: some View {
        NavigationStack(path: $libraryManager.searchPath) {
            VStack(spacing: 0) {
                VStack {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.gray)
                        
                        TextField("Título, autor...", text: $textoPesquisa)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit {
                                Task { await realizarPesquisa() }
                            }
                        
                        if isSearching {
                            ProgressView()
                                .padding(.horizontal, 8)
                        } else if !textoPesquisa.isEmpty {
                            Button {
                                textoPesquisa = ""
                                resultados = []
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                            }
                        }
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(filtros, id: \.self) { filtro in
                                Text(filtro)
                                    .font(.subheadline)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(filtroSelecionado == filtro ? Color(UIColor.darkGray) : Color.gray.opacity(0.1))
                                    .foregroundColor(filtroSelecionado == filtro ? .white : .primary)
                                    .cornerRadius(20)
                                    .onTapGesture {
                                        filtroSelecionado = filtro
                                        if !textoPesquisa.isEmpty {
                                            Task { await realizarPesquisa() }
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 12)
                }
                
                List {
                    Section(header: Text("Resultados").font(.headline).foregroundColor(.primary).textCase(nil)) {
                        if resultados.isEmpty && !isSearching {
                            Text(textoPesquisa.isEmpty ? "Escreva algo para pesquisar na Open Library." : "Nenhum livro encontrado.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(resultados) { livro in
                                NavigationLink(value: livro) {
                                    PesquisaRow(livro: livro)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Pesquisar livros")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Book.self) { livro in
                BookDetailView(book: livro)
            }
        }
        .id(libraryManager.navigationResetID)
    }
    
    @MainActor
    func realizarPesquisa() async {
        guard !textoPesquisa.isEmpty else { return }
        isSearching = true
        
        var queryFinal = textoPesquisa
        if filtroSelecionado != "Todos" {
            queryFinal += " subject:\(filtroSelecionado.lowercased())"
        }
        
        do {
            resultados = try await apiService.searchBooks(query: queryFinal)
        } catch {
            print("Erro ao pesquisar: \(error)")
            resultados = []
        }
        
        isSearching = false
    }
}

struct PesquisaRow: View {
    let livro: Book
    
    var body: some View {
        HStack(spacing: 16) {
            AsyncImage(url: livro.coverURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(Color.gray.opacity(0.3))
            }
            .frame(width: 60, height: 90)
            .cornerRadius(8)
            .clipped()
            
            VStack(alignment: .leading, spacing: 4) {
                Text(livro.title)
                    .font(.headline)
                    .lineLimit(2)
                Text(livro.authors.first ?? "Autor Desconhecido")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Aba 3: Recomendações (Gemma 4)
struct RecomendacoesView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @State private var recomendacoes: [RecommendedBook] = []
    @State private var isLoading = false
    
    private let gemmaService = GemmaRecommendationService()
    
    var body: some View {
        NavigationStack(path: $libraryManager.recommendationsPath) {
            List {
                Section(header: Text("Sugestões geradas pelo Gemma 4 com base na tua biblioteca").textCase(nil)) {
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView("O Gemma 4 está a analisar os teus gostos...")
                                .padding()
                            Spacer()
                        }
                    } else if recomendacoes.isEmpty {
                        Text("Adiciona alguns livros à tua biblioteca e clica em atualizar para receberes sugestões personalizadas.")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(recomendacoes) { item in
                            NavigationLink(value: item.book) {
                                HStack(alignment: .top, spacing: 12) {
                                    AsyncImage(url: item.book.coverURL) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Rectangle().fill(Color.gray.opacity(0.3))
                                    }
                                    .frame(width: 55, height: 85)
                                    .cornerRadius(8)
                                    .clipped()
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.book.title)
                                            .font(.headline)
                                            .lineLimit(2)
                                        
                                        Text(item.book.authors.joined(separator: ", "))
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        
                                        Text("✨ \(item.reason)")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                            .padding(.top, 2)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Recomendações")
            .navigationDestination(for: Book.self) { book in
                BookDetailView(book: book)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        Task { await carregarRecomendacoes() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .task {
                if recomendacoes.isEmpty {
                    await carregarRecomendacoes()
                }
            }
        }
        .id(libraryManager.navigationResetID)
    }
    
    @MainActor
    func carregarRecomendacoes() async {
        isLoading = true
        recomendacoes = await gemmaService.getRecommendations(for: libraryManager.books)
        isLoading = false
    }
}

// MARK: - Aba 4: Biblioteca
struct BibliotecaView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @State private var filtroSelecionado = "Todos"
    @State private var mostrarScanner = false
    
    let filtros = ["Todos", "Com interesse", "A ler", "Lido", "Desisti de ler"]
    
    var livrosFiltrados: [Book] {
        if filtroSelecionado == "Todos" {
            return libraryManager.books
        } else {
            return libraryManager.books.filter { $0.status.rawValue == filtroSelecionado }
        }
    }
    
    var body: some View {
        NavigationStack(path: $libraryManager.libraryPath) {
            VStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(filtros, id: \.self) { filtro in
                            Text(filtro)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(filtroSelecionado == filtro ? Color.green.opacity(0.8) : Color.gray.opacity(0.1))
                                .foregroundColor(filtroSelecionado == filtro ? .white : .primary)
                                .cornerRadius(20)
                                .onTapGesture {
                                    filtroSelecionado = filtro
                                }
                        }
                    }
                    .padding(.horizontal)
                }
                
                if let errorMessage = libraryManager.errorMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.primary)
                        Spacer()
                        Button("Tentar") {
                            Task { await libraryManager.loadInitialData() }
                        }
                        .font(.caption.bold())
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
                
                List {
                    if libraryManager.isLoadingData && libraryManager.books.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView("A sincronizar biblioteca...")
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    } else if livrosFiltrados.isEmpty {
                        Text(filtroSelecionado == "Todos" ? "A tua biblioteca está vazia. Adiciona livros!" : "Nenhum livro com este estado.")
                            .foregroundColor(.secondary)
                            .padding()
                            .listRowSeparator(.hidden)
                    } else {
                        ForEach(livrosFiltrados) { livro in
                            NavigationLink(value: livro) {
                                HStack(spacing: 12) {
                                    AsyncImage(url: livro.coverURL) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Rectangle().fill(Color.gray.opacity(0.3))
                                    }
                                    .frame(width: 50, height: 75)
                                    .cornerRadius(8)
                                    .clipped()
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(livro.title)
                                            .font(.headline)
                                            .lineLimit(2)
                                        Text(livro.authors.first ?? "Autor desconhecido")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    
                                    Spacer()
                                    
                                    Text(livro.status.rawValue)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.green.opacity(0.1))
                                        .foregroundColor(.green)
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await libraryManager.loadInitialData()
                }
            }
            .navigationTitle("Biblioteca")
            .navigationDestination(for: Book.self) { livro in
                LibraryBookDetailView(book: livro)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        mostrarScanner = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $mostrarScanner) {
                ScanContainerView()
            }
            .task {
                await libraryManager.refreshBooks()
            }
        }
        .id(libraryManager.navigationResetID)
    }
}

// MARK: - Vista de Gestão do Livro na Biblioteca
struct LibraryBookDetailView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(\.dismiss) var dismiss
    var book: Book
    
    var currentBook: Book {
        libraryManager.books.first(where: { $0.id == book.id }) ?? book
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    AsyncImage(url: currentBook.coverURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 80, height: 120)
                    .cornerRadius(8)
                    .clipped()
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(currentBook.title)
                            .font(.title3)
                            .bold()
                        Text(currentBook.authors.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 2) {
                            ForEach(0..<4) { _ in Image(systemName: "star.fill").foregroundColor(.yellow).font(.caption) }
                            Image(systemName: "star.fill").foregroundColor(.gray.opacity(0.4)).font(.caption)
                            Text("4,5 (1.234)").font(.caption).foregroundColor(.secondary).padding(.leading, 4)
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Estado de leitura")
                        .font(.headline)
                    
                    VStack(spacing: 0) {
                        ForEach(ReadingStatus.allCases, id: \.self) { status in
                            Button(action: {
                                libraryManager.updateStatus(for: currentBook.id, status: status)
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: currentBook.status == status ? "largecircle.fill.circle" : "circle")
                                        .foregroundColor(currentBook.status == status ? .green : .gray)
                                    
                                    Image(systemName: iconForStatus(status))
                                        .foregroundColor(.primary)
                                        .frame(width: 20)
                                    
                                    Text(status.rawValue)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                }
                                .padding()
                                .background(currentBook.status == status ? Color.green.opacity(0.08) : Color.clear)
                            }
                            if status != ReadingStatus.allCases.last {
                                Divider()
                            }
                        }
                    }
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                }
                
                VStack(spacing: 0) {
                    NavigationLink(destination: WriteReviewView(book: currentBook)) {
                        HStack {
                            Image(systemName: "star")
                            Text("Avaliar e comentar")
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.gray)
                        }
                        .padding()
                        .foregroundColor(.primary)
                    }
                    
                    Divider()
                    
                    Button(action: {
                        libraryManager.removeBook(bookId: currentBook.id)
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Remover da biblioteca")
                            Spacer()
                        }
                        .padding()
                        .foregroundColor(.red)
                    }
                }
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
                
                let bookReviews = libraryManager.reviewsFor(book: currentBook)
                if !bookReviews.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Avaliações e críticas (\(bookReviews.count))")
                            .font(.headline)
                            .padding(.top, 8)
                        
                        ForEach(bookReviews) { review in
                            ReviewCardView(review: review)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: book.id) {
            await libraryManager.refreshBookDetails(book: currentBook)
        }
    }
    
    func iconForStatus(_ status: ReadingStatus) -> String {
        switch status {
        case .interested: return "heart"
        case .reading: return "book"
        case .read: return "checkmark.circle"
        case .dropped: return "xmark.circle"
        }
    }
}

// MARK: - Aba 5: Perfil
struct PerfilView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    
    var body: some View {
        NavigationStack(path: $libraryManager.profilePath) {
            List {
                HStack(spacing: 16) {
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .frame(width: 60, height: 60)
                        .foregroundColor(.gray.opacity(0.5))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(libraryManager.currentUser?.name ?? "Utilizador")
                            .font(.title2)
                            .bold()
                        Text(libraryManager.currentUser?.email ?? "")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                
                Section {
                    Button(action: { libraryManager.selectedTab = 3 }) {
                        Label("A minha biblioteca", systemImage: "book")
                            .foregroundColor(.primary)
                    }
                    NavigationLink(destination: MyReviewsListView()) {
                        Label("As minhas avaliações", systemImage: "star")
                    }
                    NavigationLink(destination: Text("Os meus gostos")) {
                        Label("Os meus gostos", systemImage: "heart")
                    }
                    NavigationLink(destination: SettingsView()) {
                        Label("Definições", systemImage: "gearshape")
                    }
                }
                
                Section(header: Text("Modelo de IA")) {
                    NavigationLink(destination: Text("Gemma 4 (Ollama Local)")) {
                        Label("Gemma 4 (Ollama)", systemImage: "cpu")
                    }
                }
                
                Section(header: Text("Privacidade")) {
                    NavigationLink(destination: Text("Gestão de dados")) {
                        Label("Gestão de dados", systemImage: "lock.shield")
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        Task { await libraryManager.logout() }
                    } label: {
                        Label("Terminar sessão", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Perfil")
            .navigationBarTitleDisplayMode(.large)
        }
        .id(libraryManager.navigationResetID)
    }
}

struct MyReviewsListView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            if libraryManager.isLoadingData && libraryManager.userReviews.isEmpty {
                HStack {
                    Spacer()
                    ProgressView("A carregar avaliações...")
                    Spacer()
                }
                .listRowSeparator(.hidden)
            } else if libraryManager.userReviews.isEmpty {
                Text("Ainda não escreveste nenhuma avaliação.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(libraryManager.userReviews) { review in
                    ReviewCardView(review: review)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("As minhas avaliações")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Label("Perfil", systemImage: "chevron.left")
                }
            }
        }
        .task {
            await libraryManager.refreshUserReviews()
        }
        .refreshable {
            await libraryManager.refreshUserReviews()
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @State private var serverURL: String = ServerConfig.baseURL
    @State private var connectionStatus: String? = nil
    @State private var isTesting = false
    
    var body: some View {
        Form {
            Section(header: Text("Servidor Web (API)")) {
                TextField("URL da API", text: $serverURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                
                Button("Usar IP Host (192.168.221.1:3000)") {
                    serverURL = "http://192.168.221.1:3000/api"
                }
                
                Button("Usar Localhost (localhost:3000)") {
                    serverURL = "http://localhost:3000/api"
                }
            }
            
            Section {
                Button {
                    Task { await saveAndTest() }
                } label: {
                    HStack {
                        Text("Guardar e Sincronizar")
                        Spacer()
                        if isTesting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isTesting || serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                
                if let connectionStatus {
                    Text(connectionStatus)
                        .font(.footnote)
                        .foregroundColor(connectionStatus.contains("Ligado") ? .green : .red)
                }
            }
        }
        .navigationTitle("Definições")
    }
    
    @MainActor
    private func saveAndTest() async {
        isTesting = true
        ServerConfig.baseURL = serverURL
        serverURL = ServerConfig.baseURL
        
        let healthy = await RemoteBookRepository().checkHealth()
        if healthy {
            if libraryManager.isAuthenticated {
                await libraryManager.loadInitialData()
                connectionStatus = "Ligado ao servidor e biblioteca sincronizada."
            } else {
                connectionStatus = "Ligado ao servidor com sucesso."
            }
        } else {
            connectionStatus = "Não foi possível ligar a \(ServerConfig.baseURL)."
        }
        isTesting = false
    }
}

// MARK: - Vistas Auxiliares (Scanner e Detalhes)
struct ScanContainerView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(\.dismiss) var dismiss
    @State private var isShowingScanner = false
    @State private var scannedISBN: String?
    @State private var manualISBN: String = ""
    @State private var isFetching = false
    @State private var foundBook: Book?
    
    private let openLibraryService = OpenLibraryService()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let book = foundBook {
                    BookDetailView(book: book)
                    
                    Button("Pesquisar outro livro") {
                        foundBook = nil
                        manualISBN = ""
                        scannedISBN = nil
                    }
                    .padding(.top)
                } else {
                    Image(systemName: "text.book.closed")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                        .padding(.bottom, 10)
                    
                    VStack(spacing: 12) {
                        Text("Insira o ISBN manualmente:")
                            .font(.headline)
                        
                        TextField("Ex: 9780132350884", text: $manualISBN)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                            .padding(.horizontal)
                        
                        Button("Pesquisar") {
                            let cleanISBN = manualISBN.replacingOccurrences(of: " ", with: "")
                            if !cleanISBN.isEmpty {
                                Task { await fetchBookData(isbn: cleanISBN) }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(manualISBN.isEmpty)
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    Text("OU")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                    
                    Button(action: {
                        isShowingScanner = true
                    }) {
                        Label("Abrir Câmara", systemImage: "barcode.viewfinder")
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
            .navigationTitle("Adicionar Livro")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fechar") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isShowingScanner) {
                BarcodeScannerView(scannedISBN: $scannedISBN)
            }
            .onChange(of: scannedISBN) { isbn in
                if let isbn = isbn {
                    manualISBN = isbn
                    Task { await fetchBookData(isbn: isbn) }
                }
            }
            .overlay {
                if isFetching {
                    ProgressView("A pesquisar na Open Library...")
                        .padding()
                        .background(Color(UIColor.systemBackground).opacity(0.9))
                        .cornerRadius(10)
                }
            }
        }
    }
    
    func fetchBookData(isbn: String) async {
        isFetching = true
        foundBook = try? await openLibraryService.fetchBookBy(isbn: isbn)
        isFetching = false
    }
}

struct BookDetailView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    var book: Book
    
    @State private var mostrarSucesso = false
    @State private var bookReviews: [Review] = []
    @State private var isLoadingReviews = false
    @Environment(\.dismiss) var dismiss
    
    var livroJaAdicionado: Bool {
        libraryManager.books.contains(where: { $0.id == book.id })
    }
    
    private var averageRating: Double? {
        guard !bookReviews.isEmpty else { return nil }
        let total = bookReviews.reduce(0) { $0 + $1.rating }
        return Double(total) / Double(bookReviews.count)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                AsyncImage(url: book.coverURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Rectangle().fill(Color.gray.opacity(0.3))
                }
                .frame(height: 250)
                .cornerRadius(12)
                .shadow(radius: 5)
                
                Text(book.title)
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.center)
                
                Text(book.authors.joined(separator: ", "))
                    .font(.title3)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    if let averageRating {
                        let filledStars = Int(averageRating.rounded())
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: "star.fill")
                                .foregroundColor(star <= filledStars ? .yellow : .gray.opacity(0.4))
                        }
                        Text(String(format: "%.1f (%d)", averageRating, bookReviews.count))
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(1...5, id: \.self) { _ in
                            Image(systemName: "star")
                                .foregroundColor(.gray.opacity(0.5))
                        }
                        Text("Sem avaliações")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sinopse")
                        .font(.headline)
                    Text("Um livro fascinante adicionado através da Open Library API. Descubra mais sobre o universo literário desta obra e acompanhe a sua leitura na biblioteca pessoal.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top)
                
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Avaliações e críticas (\(bookReviews.count))")
                            .font(.headline)
                        Spacer()
                        NavigationLink(destination: WriteReviewView(book: book)) {
                            Text("Escrever crítica")
                                .font(.subheadline)
                                .foregroundColor(.green)
                        }
                    }
                    
                    if isLoadingReviews && bookReviews.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView("A carregar críticas...")
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    } else if bookReviews.isEmpty {
                        Text("Ainda não existem críticas para este livro. Sê o primeiro a avaliar!")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(bookReviews) { review in
                            ReviewCardView(review: review)
                        }
                    }
                }
                .padding(.top, 8)
                
                Spacer(minLength: 30)
                
                if livroJaAdicionado {
                    Button(action: {}) {
                        Label("Já está na tua biblioteca", systemImage: "checkmark")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.gray)
                    .disabled(true)
                } else {
                    Button(action: {
                        libraryManager.addBook(book)
                        mostrarSucesso = true
                    }) {
                        Text("Adicionar à biblioteca")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(UIColor.darkGray))
                }
            }
            .padding()
        }
        .navigationTitle("Detalhes")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await loadBookReviews() }
        }
        .fullScreenCover(isPresented: $mostrarSucesso) {
            EcraSucessoView(tituloLivro: book.title)
        }
    }
    
    @MainActor
    private func loadBookReviews() async {
        isLoadingReviews = true
        bookReviews = await libraryManager.fetchReviewsForBook(book)
        isLoadingReviews = false
    }
}

// MARK: - Vista de Sucesso
struct EcraSucessoView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    var tituloLivro: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 120, height: 120)
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 50))
                    .foregroundColor(Color(UIColor.darkGray))
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.green)
                    .offset(x: 30, y: 30)
            }
            
            Text("Livro adicionado à tua biblioteca!")
                .font(.title2)
                .bold()
                .multilineTextAlignment(.center)
            
            Text("O '\(tituloLivro)' foi adicionado à tua biblioteca.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            VStack(spacing: 12) {
                Button(action: {
                    libraryManager.selectedTab = 3
                    dismiss()
                }) {
                    Text("Ver na biblioteca")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(UIColor.darkGray))
                
                Button(action: {
                    dismiss()
                }) {
                    Text("Continuar a explorar")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.bordered)
                .foregroundColor(Color(UIColor.darkGray))
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Vista de Escrever Avaliação e Crítica
struct WriteReviewView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(\.dismiss) var dismiss
    var book: Book
    
    @State private var rating: Int = 4
    @State private var comment: String = ""
    private let maxCharacters = 500
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) {
                    AsyncImage(url: book.coverURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 70, height: 105)
                    .cornerRadius(8)
                    .clipped()
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.title)
                            .font(.headline)
                        Text(book.authors.joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Avaliação")
                        .font(.headline)
                    
                    HStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= rating ? "star.fill" : "star")
                                .font(.title)
                                .foregroundColor(star <= rating ? .yellow : .gray.opacity(0.4))
                                .onTapGesture {
                                    rating = star
                                }
                        }
                        
                        Text("\(rating)/5")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.leading, 8)
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Comentário")
                        .font(.headline)
                    
                    ZStack(alignment: .topLeading) {
                        if comment.isEmpty {
                            Text("Escreve a tua opinião sobre o livro...")
                                .foregroundColor(.gray.opacity(0.6))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 14)
                        }
                        
                        TextEditor(text: $comment)
                            .frame(minHeight: 140)
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .onChange(of: comment) { newValue in
                                if newValue.count > maxCharacters {
                                    comment = String(newValue.prefix(maxCharacters))
                                }
                            }
                    }
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                    
                    HStack {
                        Spacer()
                        Text("\(comment.count)/\(maxCharacters)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Button(action: {
                    let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                    libraryManager.addReview(bookId: book.id, bookTitle: book.title, content: trimmed, rating: rating)
                    dismiss()
                }) {
                    Text("Publicar")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(UIColor.darkGray))
                .disabled(comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .navigationTitle("Avaliar")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Componente Visual de uma Crítica
struct ReviewCardView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    let review: Review

    private var isCurrentUserReview: Bool {
        guard let currentName = libraryManager.currentUser?.name
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !currentName.isEmpty else {
            return false
        }

        return review.username.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(currentName) == .orderedSame
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundColor(.gray)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(review.username)
                            .font(.subheadline)
                            .bold()

                        if isCurrentUserReview {
                            Text("A tua avaliação")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.green)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(star <= review.rating ? .yellow : .gray.opacity(0.3))
                        }
                        Text("• \(review.date, style: .relative)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.leading, 4)
                    }
                }
                Spacer()
            }
            
            Text(review.content)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
        .padding()
        .background(
            isCurrentUserReview
                ? Color.green.opacity(0.08)
                : Color(UIColor.secondarySystemBackground)
        )
        .cornerRadius(12)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isCurrentUserReview ? Color.green.opacity(0.45) : .clear,
                    lineWidth: 1.5
                )
        }
    }
}
