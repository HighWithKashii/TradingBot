import SwiftUI

struct HomeDashboardView: View {
    @State private var viewModel = HomeViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                if let recovery = viewModel.recovery {
                    RecoveryRingCard(recovery: recovery)
                        .padding(.horizontal)
                }

                WeeklyRingsScrollView(history: viewModel.last7DaysRecovery)

                HStack(spacing: 16) {
                    if let strain = viewModel.strain {
                        NavigationLink {
                            StrainView()
                        } label: {
                            StrainCardView(strain: strain)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                if let sleep = viewModel.sleepSession {
                    NavigationLink {
                        SleepDetailView()
                    } label: {
                        SleepCardView(session: sleep)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }

                NavigationLink {
                    StressMonitorView()
                } label: {
                    StressPreviewCardView()
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                NavigationLink {
                    JournalView()
                } label: {
                    JournalPromptCardView()
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                Spacer(minLength: 24)
            }
            .padding(.top, 8)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(Date().dayMonthLabel)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Guten Tag")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
            }
            Spacer()
        }
        .padding(.horizontal)
    }
}

private struct RecoveryRingCard: View {
    let recovery: RecoveryScore

    var body: some View {
        CardContainer(padding: 24) {
            VStack(spacing: 16) {
                CardHeader(title: "Recovery", systemImage: "bolt.heart.fill")

                ZStack {
                    GlowRingView(
                        progress: recovery.percentage / 100,
                        gradientColors: [recovery.zone.color.opacity(0.4), recovery.zone.color],
                        lineWidth: 24
                    )
                    .frame(width: 200, height: 200)

                    VStack(spacing: 4) {
                        AnimatedNumberText(value: recovery.percentage, font: .system(size: 56, weight: .bold, design: .rounded))
                        Text("%")
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                Text(recovery.summary)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct WeeklyRingsScrollView: View {
    let history: [RecoveryScore]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 18) {
                ForEach(history) { day in
                    SmallRingView(
                        progress: day.percentage / 100,
                        color: day.zone.color,
                        label: day.date.shortWeekdaySymbol
                    )
                }
            }
            .padding(.horizontal)
        }
    }
}

private struct StrainCardView: View {
    let strain: StrainScore

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Strain", systemImage: "flame.fill")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    AnimatedNumberText(value: strain.value, decimals: 1, font: .system(size: 34, weight: .bold, design: .rounded), color: .strainBlue)
                }
                Text("Ziel: \(strain.targetValue.asOneDecimal)")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                ProgressView(value: min(strain.progressAgainstTarget, 1))
                    .tint(.strainBlue)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SleepCardView: View {
    let session: SleepSession

    var body: some View {
        CardContainer {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    CardHeader(title: "Schlaf", systemImage: "bed.double.fill")
                    Text(session.timeAsleep.hoursMinutesLabel)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Effizienz \(Int(session.efficiencyPercentage))%")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
                SleepStagesSummaryBar(session: session)
                    .frame(width: 90)
            }
        }
    }
}

private struct StressPreviewCardView: View {
    var body: some View {
        CardContainer {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(Color.stressOrange)
                Text("Stress-Monitor")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }
}

private struct JournalPromptCardView: View {
    var body: some View {
        CardContainer {
            HStack {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(Color.recoveryGreen)
                Text("Heutigen Journal-Eintrag ausfüllen")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        HomeDashboardView()
    }
    .preferredColorScheme(.dark)
}
