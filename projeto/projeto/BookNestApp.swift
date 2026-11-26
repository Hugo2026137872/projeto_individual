import SwiftUI

@main
struct BookNestApp: App {
    @StateObject private var libraryManager = LibraryManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(libraryManager)
        }
    }
}
