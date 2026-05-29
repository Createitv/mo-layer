import SwiftUI
import UIKit

enum AppTheme {
    static let primary = adaptiveColor(
        light: UIColor(red: 37 / 255, green: 99 / 255, blue: 235 / 255, alpha: 1),
        dark: UIColor(red: 96 / 255, green: 165 / 255, blue: 250 / 255, alpha: 1)
    )
    static let primaryFill = adaptiveColor(
        light: UIColor(red: 37 / 255, green: 99 / 255, blue: 235 / 255, alpha: 1),
        dark: UIColor(red: 59 / 255, green: 130 / 255, blue: 246 / 255, alpha: 1)
    )
    static let primarySoft = adaptiveColor(
        light: UIColor(red: 37 / 255, green: 99 / 255, blue: 235 / 255, alpha: 0.08),
        dark: UIColor(red: 96 / 255, green: 165 / 255, blue: 250 / 255, alpha: 0.18)
    )
    static let accent = adaptiveColor(
        light: UIColor(red: 14 / 255, green: 165 / 255, blue: 233 / 255, alpha: 1),
        dark: UIColor(red: 56 / 255, green: 189 / 255, blue: 248 / 255, alpha: 1)
    )
    static let ink = adaptiveColor(
        light: UIColor(red: 15 / 255, green: 23 / 255, blue: 42 / 255, alpha: 1),
        dark: UIColor(red: 241 / 255, green: 245 / 255, blue: 249 / 255, alpha: 1)
    )
    static let background = adaptiveColor(
        light: .white,
        dark: UIColor(red: 2 / 255, green: 6 / 255, blue: 23 / 255, alpha: 1)
    )
    static let card = adaptiveColor(
        light: UIColor(red: 248 / 255, green: 250 / 255, blue: 252 / 255, alpha: 1),
        dark: UIColor(red: 15 / 255, green: 23 / 255, blue: 42 / 255, alpha: 1)
    )
    static let danger = adaptiveColor(
        light: UIColor(red: 220 / 255, green: 38 / 255, blue: 38 / 255, alpha: 1),
        dark: UIColor(red: 248 / 255, green: 113 / 255, blue: 113 / 255, alpha: 1)
    )
    static let dangerFill = adaptiveColor(
        light: UIColor(red: 220 / 255, green: 38 / 255, blue: 38 / 255, alpha: 1),
        dark: UIColor(red: 239 / 255, green: 68 / 255, blue: 68 / 255, alpha: 1)
    )
    static let warning = adaptiveColor(
        light: UIColor(red: 217 / 255, green: 119 / 255, blue: 6 / 255, alpha: 1),
        dark: UIColor(red: 251 / 255, green: 191 / 255, blue: 36 / 255, alpha: 1)
    )
    static let success = adaptiveColor(
        light: UIColor(red: 37 / 255, green: 99 / 255, blue: 235 / 255, alpha: 1),
        dark: UIColor(red: 96 / 255, green: 165 / 255, blue: 250 / 255, alpha: 1)
    )
    static let line = adaptiveColor(
        light: UIColor(red: 219 / 255, green: 234 / 255, blue: 254 / 255, alpha: 1),
        dark: UIColor(red: 30 / 255, green: 41 / 255, blue: 59 / 255, alpha: 1)
    )
    static let secondaryText = adaptiveColor(
        light: UIColor(red: 71 / 255, green: 85 / 255, blue: 105 / 255, alpha: 1),
        dark: UIColor(red: 148 / 255, green: 163 / 255, blue: 184 / 255, alpha: 1)
    )

    private static func adaptiveColor(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
        ? dark
        : light
        })
    }
}

struct AppButtonStyle: ButtonStyle {
    var role: ButtonRole?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(role == .destructive ? AppTheme.dangerFill : AppTheme.primaryFill)
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
            .background(AppTheme.primarySoft)
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
