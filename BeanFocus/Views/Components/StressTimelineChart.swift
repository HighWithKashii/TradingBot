import SwiftUI
import Charts

/// Continuous stress timeline across the day, colored by zone the way
/// Whoop's Stress Monitor renders it - calm/balanced/stressed bands behind
/// a smooth line.
struct StressTimelineChart: View {
    let samples: [StressSample]

    var body: some View {
        Chart {
            RectangleMark(yStart: .value("Von", 0), yEnd: .value("Bis", 33))
                .foregroundStyle(Color.recoveryGreen.opacity(0.08))
            RectangleMark(yStart: .value("Von", 33), yEnd: .value("Bis", 66))
                .foregroundStyle(Color.recoveryYellow.opacity(0.08))
            RectangleMark(yStart: .value("Von", 66), yEnd: .value("Bis", 100))
                .foregroundStyle(Color.recoveryRed.opacity(0.08))

            ForEach(samples) { sample in
                LineMark(
                    x: .value("Zeit", sample.timestamp),
                    y: .value("Stress", sample.score)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.stressOrange)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                AreaMark(
                    x: .value("Zeit", sample.timestamp),
                    y: .value("Stress", sample.score)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(colors: [Color.stressOrange.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom)
                )
            }
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 33, 66, 100]) { _ in
                AxisGridLine().foregroundStyle(Color.separator)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                AxisGridLine().foregroundStyle(Color.separator)
                AxisValueLabel(format: .dateTime.hour(), centered: true)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(height: 200)
    }
}

#Preview {
    ZStack {
        Color.appBackground.ignoresSafeArea()
        StressTimelineChart(samples: MockData.stressTimeline())
            .padding()
    }
}
