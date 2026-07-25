import SwiftUI
import Charts

struct TrendPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let value: Double
}

/// Generic trend line used across the Trends tab for Recovery/Strain/HRV/etc,
/// with a soft fill gradient and an animated draw-in on appear.
struct TrendLineChart: View {
    let points: [TrendPoint]
    let color: Color
    let averageValue: Double?

    @State private var animationProgress: CGFloat = 0

    var body: some View {
        Chart {
            if let averageValue {
                RuleMark(y: .value("Durchschnitt", averageValue))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Color.textTertiary)
            }

            ForEach(points) { point in
                LineMark(
                    x: .value("Datum", point.date),
                    y: .value("Wert", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))

                AreaMark(
                    x: .value("Datum", point.date),
                    y: .value("Wert", point.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(colors: [color.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Color.separator)
                AxisValueLabel().foregroundStyle(Color.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(Color.separator)
                AxisValueLabel().foregroundStyle(Color.textTertiary)
            }
        }
        .mask(
            GeometryReader { geo in
                Rectangle().frame(width: geo.size.width * animationProgress)
            }
        )
        .onAppear {
            withAnimation(.easeOut(duration: 1.1)) {
                animationProgress = 1
            }
        }
        .onChange(of: points.map(\.value)) { _, _ in
            animationProgress = 0
            withAnimation(.easeOut(duration: 0.9)) {
                animationProgress = 1
            }
        }
        .frame(height: 220)
    }
}

#Preview {
    ZStack {
        Color.appBackground.ignoresSafeArea()
        TrendLineChart(
            points: MockData.recoveryHistory(days: 30).map { TrendPoint(date: $0.date, value: $0.percentage) },
            color: .recoveryGreen,
            averageValue: 62
        )
        .padding()
    }
}
