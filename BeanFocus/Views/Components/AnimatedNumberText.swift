import SwiftUI

/// Counts a number up from 0 to `value` whenever it changes, used for the
/// large score digits so they feel alive rather than popping in instantly.
struct AnimatedNumberText: View {
    let value: Double
    var decimals: Int = 0
    var font: Font = .system(size: 64, weight: .bold, design: .rounded)
    var color: Color = .textPrimary

    @State private var displayedValue: Double = 0

    var body: some View {
        Text(formatted(displayedValue))
            .font(font)
            .foregroundStyle(color)
            .contentTransition(.numericText())
            .onAppear {
                withAnimation(.easeOut(duration: 1.4)) {
                    displayedValue = value
                }
            }
            .onChange(of: value) { _, newValue in
                withAnimation(.easeOut(duration: 0.8)) {
                    displayedValue = newValue
                }
            }
    }

    private func formatted(_ number: Double) -> String {
        String(format: "%.\(decimals)f", number)
    }
}
