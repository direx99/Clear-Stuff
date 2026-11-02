import SwiftUI

/// Shared, appearance-aware colors keep navigation, cards, and controls consistent.
enum AppTheme {
    static let accent = Color("ThemeAccent")
    static let action = Color.accentColor
    static let actionText = Color("ThemeActionText")
    static let canvas = Color("ThemeCanvas")
    static let surface = Color("ThemeSurface")
    static let sidebar = Color("ThemeSidebar")
    static let subtle = Color("ThemeSubtle")
    static let selection = Color("ThemeSelection")
    static let border = Color("ThemeBorder")
    static let secondaryText = Color("ThemeSecondaryText")
}

/// Keep filled actions legible in active, inactive, and disabled windows.
struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.medium)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isEnabled ? AppTheme.actionText : AppTheme.secondaryText)
            .background(
                isEnabled ? AppTheme.action.opacity(configuration.isPressed ? 0.82 : 1) : AppTheme.subtle,
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isEnabled ? Color.clear : AppTheme.border))
    }
}
