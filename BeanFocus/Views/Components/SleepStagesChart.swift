import SwiftUI
import Charts

/// Stacked horizontal bar showing the proportion of REM/Light/Deep sleep,
/// plus a timeline view of stage transitions across the night.
struct SleepStagesSummaryBar: View {
    let session: SleepSession

    private static let colors: [SleepStage: Color] = [
        .deep: .sleepPurple,
        .rem: Color.sleepPurple.opacity(0.6),
        .light: Color.sleepPurple.opacity(0.3),
        .awake: Color.white.opacity(0.15)
    ]

    var body: some View {
        Chart(session.stageBreakdown, id: \.stage) { item in
            BarMark(
                x: .value("Dauer", item.duration / 60),
                y: .value("Schlaf", "Phasen")
            )
            .foregroundStyle(Self.colors[item.stage] ?? .gray)
            .cornerRadius(6)
        }
        .chartLegend(.hidden)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 28)
    }
}

/// Timeline chart of sleep stages across the night, similar to Whoop's
/// stepped hypnogram.
struct SleepHypnogramChart: View {
    let session: SleepSession

    var body: some View {
        Chart(session.stages) { interval in
            RectangleMark(
                xStart: .value("Start", interval.start),
                xEnd: .value("Ende", interval.end),
                yStart: .value("Von", yValue(interval.stage)),
                yEnd: .value("Bis", yValue(interval.stage) + 1)
            )
            .foregroundStyle(color(for: interval.stage))
            .cornerRadius(3)
        }
        .chartYAxis {
            AxisMarks(values: [0, 1, 2, 3]) { value in
                if let intValue = value.as(Int.self), let stage = stage(for: intValue) {
                    AxisValueLabel(stage.rawValue)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                AxisGridLine().foregroundStyle(Color.separator)
                AxisValueLabel(format: .dateTime.hour(), centered: true)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(height: 140)
    }

    private func yValue(_ stage: SleepStage) -> Int {
        switch stage {
        case .awake: return 3
        case .rem: return 2
        case .light: return 1
        case .deep: return 0
        }
    }

    private func stage(for yValue: Int) -> SleepStage? {
        switch yValue {
        case 3: return .awake
        case 2: return .rem
        case 1: return .light
        case 0: return .deep
        default: return nil
        }
    }

    private func color(for stage: SleepStage) -> Color {
        switch stage {
        case .deep: return .sleepPurple
        case .rem: return Color.sleepPurple.opacity(0.65)
        case .light: return Color.sleepPurple.opacity(0.35)
        case .awake: return Color.white.opacity(0.2)
        }
    }
}

#Preview {
    ZStack {
        Color.appBackground.ignoresSafeArea()
        VStack {
            SleepHypnogramChart(session: MockData.sleepSession(for: Date()))
                .padding()
        }
    }
}
