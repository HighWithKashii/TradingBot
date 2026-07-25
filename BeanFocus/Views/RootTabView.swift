import SwiftUI

struct RootTabView: View {
    @State private var showsSettings = false

    var body: some View {
        TabView {
            NavigationStack {
                HomeDashboardView()
                    .toolbar { settingsToolbarItem }
            }
            .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack {
                RecoveryDetailView()
                    .toolbar { settingsToolbarItem }
            }
            .tabItem { Label("Recovery", systemImage: "bolt.heart.fill") }

            NavigationStack {
                StrainView()
                    .toolbar { settingsToolbarItem }
            }
            .tabItem { Label("Strain", systemImage: "flame.fill") }

            NavigationStack {
                TrendsView()
                    .toolbar { settingsToolbarItem }
            }
            .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
        }
        .tint(.recoveryGreen)
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
        .onAppear {
            UITabBar.appearance().backgroundColor = UIColor(Color.cardBackground)
        }
    }

    @ToolbarContentBuilder
    private var settingsToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                HapticManager.light()
                showsSettings = true
            } label: {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }
}

#Preview {
    RootTabView()
        .preferredColorScheme(.dark)
}
