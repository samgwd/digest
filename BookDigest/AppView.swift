import SwiftUI

struct AppView: View {
    @State private var selectedTab: AppTab = .home
    @State private var playerBook: Book?
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var speechController: SpeechController

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LibraryView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
            .tag(AppTab.home)
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }

            NavigationStack {
                MyLibraryView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
            .tag(AppTab.library)
            .tabItem {
                Label("Library", systemImage: "books.vertical.fill")
            }

            NavigationStack {
                CategoriesView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
            .tag(AppTab.categories)
            .tabItem {
                Label("Categories", systemImage: "square.grid.2x2.fill")
            }

            NavigationStack {
                SearchView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
            .tag(AppTab.search)
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }

            NavigationStack {
                SettingsView()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { miniPlayer }
            .tag(AppTab.settings)
            .tabItem {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
        }
        .tint(EditorialTheme.forest)
        .fullScreenCover(item: $playerBook) { book in
            BookPlaybackView(book: book, digestText: DigestStorage.load(for: book.id)?.text ?? "")
                .environmentObject(settings)
                .environmentObject(speechController)
        }
    }

    private var miniPlayer: some View {
        MiniPlayerBar { book in
            playerBook = book
        }
    }
}

enum AppTab: Hashable {
    case home, library, categories, search, settings
}
