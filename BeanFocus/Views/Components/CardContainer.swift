import SwiftUI

/// Standard card background used across the app: rounded corners, subtle
/// elevation, dark surface color, matching the "kartenbasiertes Layout".
struct CardContainer<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 8)
    }
}

struct CardHeader: View {
    let title: String
    var systemImage: String?
    var trailing: String?

    var body: some View {
        HStack {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.textSecondary)
            }
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }
}
