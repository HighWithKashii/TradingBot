import SwiftUI

/// The signature Whoop-style ring: a gradient stroke with a soft glow that
/// animates from 0 to its target value on appear, with a big number and
/// caption centered inside.
struct GlowRingView: View {
    let progress: Double // 0...1
    let gradientColors: [Color]
    let lineWidth: CGFloat
    var showsGlow: Bool = true

    @State private var animatedProgress: Double = 0

    init(progress: Double, gradientColors: [Color], lineWidth: CGFloat = 22, showsGlow: Bool = true) {
        self.progress = progress
        self.gradientColors = gradientColors
        self.lineWidth = lineWidth
        self.showsGlow = showsGlow
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.06), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(colors: gradientColors, center: .center, startAngle: .degrees(0), endAngle: .degrees(360)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: showsGlow ? gradientColors.last?.opacity(0.6) ?? .clear : .clear, radius: 12)
                .shadow(color: showsGlow ? gradientColors.first?.opacity(0.4) ?? .clear : .clear, radius: 20)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.easeOut(duration: 1.0)) {
                animatedProgress = newValue
            }
        }
    }
}

/// A compact version used in the 7-day horizontal scroller on the Home tab.
struct SmallRingView: View {
    let progress: Double
    let color: Color
    let label: String
    var size: CGFloat = 52

    @State private var animatedProgress: Double = 0

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: size, height: size)
            .onAppear {
                withAnimation(.easeOut(duration: 1.0).delay(0.1)) {
                    animatedProgress = progress
                }
            }

            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }
}

#Preview {
    ZStack {
        Color.appBackground.ignoresSafeArea()
        GlowRingView(progress: 0.78, gradientColors: [Color.recoveryGreen.opacity(0.5), Color.recoveryGreen])
            .frame(width: 220, height: 220)
    }
}
