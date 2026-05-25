import SwiftUI

enum AppTheme {
    static let primary = Color(red: 15 / 255, green: 118 / 255, blue: 110 / 255)
    static let accent = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)
    static let ink = Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255)
    static let background = Color(red: 247 / 255, green: 249 / 255, blue: 252 / 255)
    static let card = Color.white
    static let danger = Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255)
    static let warning = Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)
    static let success = Color(red: 20 / 255, green: 184 / 255, blue: 166 / 255)
    static let line = Color(red: 226 / 255, green: 232 / 255, blue: 240 / 255)
    static let secondaryText = Color(red: 71 / 255, green: 85 / 255, blue: 105 / 255)
}

struct AppButtonStyle: ButtonStyle {
    var role: ButtonRole?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(role == .destructive ? AppTheme.danger : AppTheme.primary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(AppTheme.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(AppTheme.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

struct StatusPill: View {
    let title: String
    let systemImage: String
    var tint: Color = AppTheme.success

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.1))
            .clipShape(Capsule())
    }
}

struct AppCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppTheme.line, lineWidth: 1)
            )
    }
}

