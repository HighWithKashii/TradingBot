import SwiftUI

struct TrendsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = TrendsViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                pickers
                chartCard
                if let insight = viewModel.shortSleepInsight {
                    insightCard(text: insight)
                }
                ForEach(viewModel.insights.prefix(3)) { insight in
                    insightCard(text: insight.headline)
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Trends")
        .task { await viewModel.load(modelContext: modelContext) }
        .onChange(of: viewModel.range) { _, _ in
            Task { await viewModel.load(modelContext: modelContext) }
        }
    }

    private var pickers: some View {
        VStack(spacing: 12) {
            Picker("Zeitraum", selection: $viewModel.range) {
                ForEach(TrendRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(TrendMetric.allCases) { metric in
                        Button {
                            HapticManager.selection()
                            viewModel.metric = metric
                        } label: {
                            Text(metric.rawValue)
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule().fill(viewModel.metric == metric ? Color.recoveryGreen.opacity(0.2) : Color.cardBackground)
                                )
                                .foregroundStyle(viewModel.metric == metric ? Color.recoveryGreen : Color.textSecondary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var chartCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: viewModel.metric.rawValue, trailing: "Ø \(viewModel.averageValue.asOneDecimal)")
                TrendLineChart(
                    points: viewModel.dailyMetrics.map { TrendPoint(date: $0.date, value: viewModel.value(for: viewModel.metric, in: $0)) },
                    color: color(for: viewModel.metric),
                    averageValue: viewModel.averageValue
                )
            }
        }
        .padding(.horizontal)
    }

    private func insightCard(text: String) -> some View {
        CardContainer {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(Color.recoveryYellow)
                Text(text)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal)
    }

    private func color(for metric: TrendMetric) -> Color {
        switch metric {
        case .recovery: return .recoveryGreen
        case .strain: return .strainBlue
        case .hrv: return .recoveryGreen
        case .restingHeartRate: return .recoveryRed
        case .sleep: return .sleepPurple
        }
    }
}

#Preview {
    NavigationStack {
        TrendsView()
    }
    .preferredColorScheme(.dark)
    .modelContainer(for: [DailyMetrics.self, JournalEntry.self], inMemory: true)
}
