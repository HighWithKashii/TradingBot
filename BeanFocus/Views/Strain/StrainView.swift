import SwiftUI

struct StrainView: View {
    @State private var viewModel = StrainViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let strain = viewModel.todayStrain {
                    ringSection(strain)
                }

                liveWorkoutSection

                if let strain = viewModel.todayStrain {
                    zoneSection(strain)
                }

                workoutsSection

                historySection
            }
            .padding(.vertical, 8)
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Strain")
        .task { await viewModel.load() }
    }

    private func ringSection(_ strain: StrainScore) -> some View {
        CardContainer(padding: 28) {
            VStack(spacing: 16) {
                GlowRingView(
                    progress: min(strain.value / 21, 1),
                    gradientColors: [Color.strainBlue.opacity(0.4), Color.strainBlue],
                    lineWidth: 28
                )
                .frame(width: 220, height: 220)
                .overlay {
                    VStack(spacing: 4) {
                        AnimatedNumberText(value: strain.value, decimals: 1, font: .system(size: 56, weight: .bold, design: .rounded), color: .strainBlue)
                        Text(strain.level.rawValue.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                HStack(spacing: 32) {
                    statColumn(title: "Ziel", value: strain.targetValue.asOneDecimal)
                    statColumn(title: "Ø Puls", value: strain.averageHeartRate.asBPM)
                    statColumn(title: "Kalorien", value: "\(Int(strain.activeCalories)) kcal")
                }
            }
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

    private var liveWorkoutSection: some View {
        CardContainer {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.isLiveWorkoutActive ? "Training läuft" : "Live-Training starten")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    if let hr = viewModel.liveHeartRate {
                        Text(hr.asBPM)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.recoveryRed)
                    }
                }
                Spacer()
                Button {
                    HapticManager.medium()
                    viewModel.isLiveWorkoutActive ? viewModel.stopLiveWorkout() : viewModel.startLiveWorkout()
                } label: {
                    Image(systemName: viewModel.isLiveWorkoutActive ? "stop.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(viewModel.isLiveWorkoutActive ? Color.recoveryRed : Color.recoveryGreen)
                }
            }
        }
        .padding(.horizontal)
    }

    private func zoneSection(_ strain: StrainScore) -> some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Herzfrequenzzonen")
                HeartRateZoneChart(zoneMinutes: viewModel.zoneBreakdown)
            }
        }
        .padding(.horizontal)
    }

    private var workoutsSection: some View {
        Group {
            if !viewModel.workouts.isEmpty {
                CardContainer {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Trainingseinheiten")
                        ForEach(viewModel.workouts) { workout in
                            HStack {
                                Image(systemName: "figure.run")
                                    .foregroundStyle(Color.strainBlue)
                                VStack(alignment: .leading) {
                                    Text(workout.activityName)
                                        .font(.system(.body, design: .rounded, weight: .semibold))
                                        .foregroundStyle(Color.textPrimary)
                                    Text(workout.start.timeLabel + " · " + workout.duration.hoursMinutesLabel)
                                        .font(.caption)
                                        .foregroundStyle(Color.textTertiary)
                                }
                                Spacer()
                                Text(workout.strainContribution.asOneDecimal)
                                    .font(.system(.headline, design: .rounded, weight: .bold))
                                    .foregroundStyle(Color.strainBlue)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var historySection: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: "Letzte 30 Tage")
                TrendLineChart(
                    points: viewModel.history.map { TrendPoint(date: $0.date, value: $0.value) },
                    color: .strainBlue,
                    averageValue: viewModel.history.isEmpty ? nil : viewModel.history.reduce(0) { $0 + $1.value } / Double(viewModel.history.count)
                )
            }
        }
        .padding(.horizontal)
    }
}

#Preview {
    NavigationStack {
        StrainView()
    }
    .preferredColorScheme(.dark)
}
