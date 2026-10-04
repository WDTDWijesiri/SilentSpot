import SwiftUI

enum AppTheme {
    static let background = Color("AppBackground")
    static let accent = Color("AccentColor")
    static let quiet = Color("QuietGreen")
    static let softTeal = Color("SoftTeal")
    static let warning = Color("WarningOrange")
    static let noisy = Color("NoisyRed")
}

extension NoiseStatus {
    var color: Color {
        switch self {
        case .quiet: AppTheme.quiet
        case .moderate: AppTheme.warning
        case .noisy, .veryNoisy: AppTheme.noisy
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(.white)
            .background(AppTheme.accent.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundStyle(AppTheme.accent)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct StatusPill: View {
    let status: NoiseStatus
    var body: some View {
        Label(status.rawValue, systemImage: "circle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(status.color.opacity(0.14), in: Capsule())
    }
}

struct AppCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(.separator)))
    }
}
