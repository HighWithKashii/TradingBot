import SwiftUI

extension View {
    /// Fires a light haptic whenever `trigger` changes - handy for score
    /// rings finishing their fill animation or tab changes.
    func hapticFeedback(onChangeOf trigger: some Equatable, style: HapticStyle = .light) -> some View {
        self.onChange(of: trigger) { _, _ in
            switch style {
            case .light: HapticManager.light()
            case .medium: HapticManager.medium()
            case .selection: HapticManager.selection()
            case .success: HapticManager.success()
            }
        }
    }
}

enum HapticStyle {
    case light, medium, selection, success
}
