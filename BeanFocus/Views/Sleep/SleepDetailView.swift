import SwiftUI

struct SleepDetailView: View {
    @State private var viewModel = SleepViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let session = viewModel.todaySession {
                    summaryCard(session)
                    hypnogramCard(session)
                    stagesCard(session)
                }
                debtAndConsistencyCard
            }
            .padding(.vertical, 8)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Schlaf")
        .task { await viewModel.load() }
    }

    private func summaryCard(_ session: SleepSession) -> some View {
        CardContainer(padding: 24) {
            VStack(spacing: 12) {
                Text(session.timeAsleep.hoursMinutesLabel)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.sleepPurple)
                Text("\(session.bedtime.timeLabel) – \(session.wakeTime.timeLabel)")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.textSecondary)

                HStack(spacing: 32) {
                    statColumn(title: "Effizienz", value: "\(Int(session.efficiencyPercentage))%")
                    statColumn(title: "Schlafschuld", value: session.sleepDebtSeconds.hoursMinutesLabel)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal)
    }

    private func statColumn(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func hypnogramCard(_ session: SleepSession) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Schlafphasen")
                SleepHypnogramChart(session: session)
            }
        }
        .padding(.horizontal)
    }

    private func stagesCard(_ session: SleepSession) -> some View {
        CardContainer {
            VStack(spacing: 12) {
                ForEach(session.stageBreakdown, id: \.stage) { entry in
                    HStack {
                        Text(entry.stage.rawValue)
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text(entry.duration.hoursMinutesLabel)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var debtAndConsistencyCard: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                CardHeader(title: "Konsistenz & Empfehlung")
                HStack {
                    Text("Konsistenz-Score")
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text("\(Int(viewModel.consistencyScore))%")
                        .font(.system(.body, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.sleepPurple)
                }
                if let recommended = viewModel.recommendedBedtime {
                    HStack {
                        Text("Empfohlene Schlafenszeit")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text(recommended.timeLabel)
                            .font(.system(.body, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.sleepPurple)
                    }
                }
            }
        }
        .padding(.horizontal)
    }
}

#Preview {
    NavigationStack {
        SleepDetailView()
    }
    .preferredColorScheme(.dark)
}
