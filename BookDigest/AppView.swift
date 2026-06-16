import SwiftUI

struct AppView: View {
    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                LibraryView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
            .tag(AppTab.home)
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }

            NavigationStack {
                CategoriesView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
            .tag(AppTab.categories)
            .tabItem {
                Label("Categories", systemImage: "square.grid.2x2.fill")
            }

            NavigationStack {
                SearchView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
            .tag(AppTab.search)
            .tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }

            NavigationStack {
                SettingsView()
            }
            .tag(AppTab.settings)
            .tabItem {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
        }
        .tint(EditorialTheme.forest)
    }
}

enum AppTab: Hashable {
    case home, categories, search, settings
}
