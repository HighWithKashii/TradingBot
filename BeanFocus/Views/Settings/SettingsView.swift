import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Circle()
                            .fill(Color.recoveryGreen.opacity(0.2))
                            .frame(width: 56, height: 56)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .foregroundStyle(Color.recoveryGreen)
                                    .font(.title2)
                            )
                        VStack(alignment: .leading) {
                            Text(viewModel.userName)
                                .font(.system(.headline, design: .rounded, weight: .bold))
                            Text("Profil bearbeiten")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                    .listRowBackground(Color.cardBackground)
                }

                Section("Daten") {
                    Toggle("Mock-Daten verwenden", isOn: $viewModel.useMockData)
                        .tint(.recoveryGreen)
                    Text("Im Simulator gibt es keine echten Gesundheitssensoren - Mock-Daten sorgen dafür, dass alle Screens trotzdem vollständig aussehen.")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                .listRowBackground(Color.cardBackground)

                Section("Benachrichtigungen") {
                    Toggle("Stress-Hinweise", isOn: Binding(
                        get: { viewModel.stressNotificationsEnabled },
                        set: { _ in Task { await viewModel.requestNotificationPermission() } }
                    ))
                    .tint(.recoveryGreen)
                }
                .listRowBackground(Color.cardBackground)

                Section("HealthKit") {
                    Label("Berechtigungen in der Health-App verwalten", systemImage: "heart.text.square")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
                .listRowBackground(Color.cardBackground)

                Section {
                    Text("BeanFocus · Version 1.0")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                .listRowBackground(Color.cardBackground)
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Profil & Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    SettingsView()
}
