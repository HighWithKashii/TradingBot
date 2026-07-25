import SwiftUI
import Charts

struct HeartRateZoneChart: View {
    let zoneMinutes: [(zone: HeartRateZone, minutes: Double)]

    var body: some View {
        Chart(zoneMinutes, id: \.zone) { entry in
            BarMark(
                x: .value("Minuten", entry.minutes),
                y: .value("Zone", entry.zone.label)
            )
            .foregroundStyle(color(for: entry.zone))
            .cornerRadius(6)
            .annotation(position: .trailing) {
                Text("\(Int(entry.minutes))min")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(height: 180)
    }

    private func color(for zone: HeartRateZone) -> Color {
        switch zone {
        case .zone1: return .strainBlue.opacity(0.35)
        case .zone2: return .strainBlue.opacity(0.55)
        case .zone3: return .recoveryYellow.opacity(0.7)
        case .zone4: return Color(hex: "FF8A00")
        case .zone5: return .recoveryRed
        }
    }
}

#Preview {
    ZStack {
        Color.appBackground.ignoresSafeArea()
        HeartRateZoneChart(zoneMinutes: HeartRateZone.allCases.map { ($0, Double.random(in: 5...120)) })
            .padding()
    }
}
