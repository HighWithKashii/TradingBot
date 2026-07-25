import SwiftUI
import Charts

struct RecoveryDetailView: View {
    @State private var viewModel = RecoveryViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let recovery = viewModel.todayRecovery {
                    ringSection(recovery)
                    factorsSection(viewModel)
                }

                historySection
            }
            .padding(.vertical, 8)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Recovery")
        .task { await viewModel.load() }
    }

    private func ringSection(_ recovery: RecoveryScore) -> some View {
        CardContainer(padding: 28) {
            VStack(spacing: 18) {
                GlowRingView(
                    progress: recovery.percentage / 100,
                    gradientColors: [recovery.zone.color.opacity(0.4), recovery.zone.color],
                    lineWidth: 28
                )
                .frame(width: 240, height: 240)
                .overlay {
                    VStack(spacing: 4) {
                        AnimatedNumberText(value: recovery.percentage, font: .system(size: 64, weight: .bold, design: .rounded))
                        Text(recovery.zone.label.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(recovery.zone.color)
                    }
                }

                Text(recovery.summary)
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal)
    }

    private func factorsSection(_ viewModel: RecoveryViewModel) -> some View {
        CardContainer {
            VStack(spacing: 16) {
                CardHeader(title: "Faktoren")
                ForEach(viewModel.factorBreakdown, id: \.title) { factor in
                    HStack {
                        Image(systemName: factor.systemImage)
                            .foregroundStyle(Color.recoveryGreen)
                            .frame(width: 28)
                        Text(factor.title)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text(factor.value)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                    if factor.title != viewModel.factorBreakdown.last?.title {
                        Divider().background(Color.separator)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var historySection: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Letzte 30 Tage")
                TrendLineChart(
                    points: viewModel.history.map { TrendPoint(date: $0.date, value: $0.percentage) },
                    color: .recoveryGreen,
                    averageValue: viewModel.history.isEmpty ? nil : viewModel.history.reduce(0) { $0 + $1.percentage } / Double(viewModel.history.count)
                )
            }
        }
        .padding(.horizontal)
    }
}

#Preview {
    NavigationStack {
        RecoveryDetailView()
    }
    .preferredColorScheme(.dark)
}
