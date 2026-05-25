import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var auth: AuthenticationManager
    @AppStorage("vault.hasSeenFirstRunGuide") private var hasSeenFirstRunGuide = false
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.english.rawValue

    private var selectedLanguage: AppLanguage {
        AppLanguage(rawValue: language) ?? .english
    }

    var body: some View {
        Group {
            if !hasSeenFirstRunGuide {
                FirstRunGuideView {
                    hasSeenFirstRunGuide = true
                }
            } else if !auth.isConfigured {
                OnboardingView()
            } else {
                switch auth.sessionMode {
                case .cover:
                    PalimpsestCoverView()
                case .realVault:
                    MainAppView()
                case .decoyVault:
                    DecoyVaultView()
                }
            }
        }
        .preferredColorScheme(.light)
        .environment(\.locale, selectedLanguage.locale)
    }
}

struct FirstRunGuideView: View {
    let onStart: () -> Void

    var body: some View {
        ZStack {
            AppTheme.ink.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 54, weight: .semibold))
                            .foregroundStyle(AppTheme.success)
                        Text("Welcome to Palimpsest")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(.white)
                        Text("It looks like a file archive. Your encrypted private vault opens only with the correct gesture.")
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    VStack(spacing: 12) {
                        GuideStep(icon: "folder", title: "Disguised file tool", detail: "Daily launches show a normal file archive instead of exposing your real vault.")
                        GuideStep(icon: "scribble.variable", title: "Gesture entry", detail: "Use your own freeform gesture to enter the vault. Reset it with your security code if you forget it.")
                        GuideStep(icon: "square.and.arrow.down", title: "Encrypt on import", detail: "Photos, videos, and files are encrypted on this device before optional iCloud sync.")
                        GuideStep(icon: "theatermasks", title: "Decoy vault", detail: "Wrong gestures or access codes open a realistic archive, so real content stays hidden.")
                    }

                    Button("Set Up Palimpsest", action: onStart)
                        .buttonStyle(AppButtonStyle())
                }
                .padding(28)
            }
        }
    }
}

private struct GuideStep: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppTheme.success)
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
            }
        }
        .padding(14)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthenticationManager())
        .environmentObject(CloudKitSyncService())
        .environmentObject(VaultStore())
        .environmentObject(SubscriptionManager())
}
