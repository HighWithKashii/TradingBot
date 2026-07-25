import SwiftUI

struct StressMonitorView: View {
    @State private var viewModel = StressViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                currentStateCard
                timelineCard
                breakdownCard
                notificationCard
            }
            .padding(.vertical, 8)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Stress-Monitor")
        .task { await viewModel.load() }
    }

    private var currentLevel: StressLevel { StressLevel.from(score: viewModel.currentScore) }

    private var currentStateCard: some View {
        CardContainer(padding: 28) {
            VStack(spacing: 12) {
                Text(currentLevel.rawValue)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(color(for: currentLevel))
                Text("Aktueller HRV-basierter Zustand")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
    }

    private var timelineCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Tagesverlauf")
                StressTimelineChart(samples: viewModel.timeline)
            }
        }
        .padding(.horizontal)
    }

    private var breakdownCard: some View {
        CardContainer {
            VStack(spacing: 12) {
                ForEach(StressLevel.allCases, id: \.self) { level in
                    HStack {
                        Circle()
                            .fill(color(for: level))
                            .frame(width: 10, height: 10)
                        Text(level.rawValue)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text(viewModel.timeSpent(in: level).hoursMinutesLabel)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var notificationCard: some View {
        CardContainer {
            Toggle(isOn: Binding(
                get: { viewModel.notificationsEnabled },
                set: { _ in Task { await viewModel.toggleNotifications() } }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hinweise bei anhaltendem Stress")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Push-Benachrichtigung bei über einer Stunde erhöhtem Stress.")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .tint(.stressOrange)
        }
        .padding(.horizontal)
    }

    private func color(for level: StressLevel) -> Color {
        switch level {
        case .calm: return .recoveryGreen
        case .balanced: return .recoveryYellow
        case .stressed: return .recoveryRed
        }
    }
}

#Preview {
    NavigationStack {
        StressMonitorView()
    }
    .preferredColorScheme(.dark)
}
