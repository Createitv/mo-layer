import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthenticationManager
    @EnvironmentObject private var subscription: SubscriptionManager
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var vaultStore: VaultStore
    @State private var step: SetupStep = .securityCode
    @State private var backupKey = ""
    @State private var confirmBackupKey = ""
    @State private var gesturePrimary: [GesturePoint] = []
    @State private var gestureConfirmation: [GesturePoint] = []
    @State private var animateMark = false
    @State private var showCloudRestore = false
    private let backupKeyLength = 6
    private var isPadLayout: Bool { horizontalSizeClass == .regular }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AppGlassBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: isPadLayout ? 28 : 22) {
                    SetupMotionMark(isAnimating: animateMark, step: step)

                    VStack(spacing: isPadLayout ? 12 : 8) {
                        Text(step.title)
                            .font(.system(isPadLayout ? .largeTitle : .title, design: .rounded, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                            .contentTransition(.numericText())
                        Text(step.subtitle)
                            .font(isPadLayout ? .title3 : .callout)
                            .foregroundStyle(AppTheme.secondaryText)
                            .multilineTextAlignment(.center)
                    }

                    SetupProgressView(step: step)

                    ZStack {
                        stepContent
                            .id(step)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                    .animation(.spring(response: 0.42, dampingFraction: 0.86), value: step)

                    HStack(spacing: isPadLayout ? 14 : 12) {
                        if step != .securityCode {
                            Button(L.string("Back")) {
                                withAnimation { step = step.previous }
                            }
                            .buttonStyle(SetupBackButtonStyle())
                        }

                        Button(step.primaryActionTitle) {
                            handlePrimaryAction()
                        }
                        .buttonStyle(AppButtonStyle())
                    }

                    if step == .securityCode {
                        Button {
                            showCloudRestore = true
                        } label: {
                            Label(L.string("Restore Existing iCloud Vault"), systemImage: "icloud.and.arrow.down")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }

                    if let message = auth.authMessage {
                        Text(message)
                            .font(isPadLayout ? .callout : .footnote)
                            .foregroundStyle(AppTheme.warning)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: isPadLayout ? 640 : .infinity)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
                .padding(.horizontal, isPadLayout ? 48 : 28)
                .padding(.vertical, isPadLayout ? 44 : 28)
                }
            }
        }
        .onAppear { animateMark = true }
        .sheet(isPresented: $showCloudRestore) {
            CloudVaultRestoreView()
                .environmentObject(auth)
                .environmentObject(subscription)
                .environmentObject(sync)
                .environmentObject(vaultStore)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .drawGesture:
            SetupCard(icon: "scribble.variable", title: L.string("Draw Your Gesture"), detail: L.string("Draw a familiar freeform motion. The system records route, rhythm, and length features; exact position does not need to match.")) {
                GestureTutorialCard()
                GestureCapturePad(title: L.string("First Gesture"), subtitle: L.string("Press and draw one complete motion. Release to record.")) { points in
                    recordPrimaryGesture(points)
                }
                if !gesturePrimary.isEmpty {
                    StatusPill(title: L.string("First gesture recorded"), systemImage: "checkmark.circle.fill", tint: AppTheme.success)
                }
            }
        case .confirmGesture:
            SetupCard(icon: "signature", title: L.string("Draw Again to Confirm"), detail: L.string("The second gesture confirms that you can reproduce the motion reliably. Return and redraw if similarity is too low.")) {
                GestureCapturePad(title: L.string("Confirmation Gesture"), subtitle: L.string("Keep a similar route and rhythm; size may differ slightly.")) { points in
                    recordConfirmationGesture(points)
                }
                if !gestureConfirmation.isEmpty {
                    StatusPill(title: L.string("Confirmation gesture recorded"), systemImage: "checkmark.circle.fill", tint: AppTheme.success)
                }
            }
        case .securityCode:
            SetupCard(icon: "key.fill") {
                BackupKeyGridInput(value: $backupKey, length: backupKeyLength)
            }
        case .confirmSecurityCode:
            SetupCard(icon: "checkmark.seal.fill", title: L.string("Confirm Security Code"), detail: L.string("Make sure you have saved or remembered it. If you forget your gesture later, this code lets you create a new one.")) {
                BackupKeyGridInput(value: $confirmBackupKey, length: backupKeyLength)
                if !confirmBackupKey.isEmpty && normalizedSecurityCode(confirmBackupKey) != normalizedSecurityCode(backupKey) {
                    Text(L.string("Security codes do not match"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.warning)
                }
            }
        }
    }

    private var canContinue: Bool {
        switch step {
        case .drawGesture:
            !gesturePrimary.isEmpty
        case .confirmGesture:
            !gestureConfirmation.isEmpty
        case .securityCode:
            normalizedSecurityCode(backupKey).count == backupKeyLength
        case .confirmSecurityCode:
            normalizedSecurityCode(confirmBackupKey) == normalizedSecurityCode(backupKey) && !confirmBackupKey.isEmpty
        }
    }

    private func handlePrimaryAction() {
        auth.authMessage = nil
        guard canContinue else {
            auth.authMessage = validationMessage
            return
        }
        switch step {
        case .securityCode, .confirmSecurityCode, .drawGesture:
            withAnimation { step = step.next }
        case .confirmGesture:
            do {
                let result = try GestureCredentialService.enrollmentMatchResult(
                    primary: gesturePrimary,
                    confirmation: gestureConfirmation
                )
                guard result.isMatch else {
                    gestureConfirmation = []
                    auth.authMessage = L.string("The two gestures are not similar enough. Please set them again.")
                    return
                }
                Task {
                    let success = await auth.configure(
                        backupKey: normalizedSecurityCode(backupKey),
                        gesture: (gesturePrimary, gestureConfirmation)
                    )
                    if !success {
                        gestureConfirmation = []
                    }
                }
            } catch {
                gestureConfirmation = []
                auth.authMessage = error.localizedDescription
            }
        }
    }

    private func recordPrimaryGesture(_ points: [GesturePoint]) {
        do {
            try GestureCredentialService.validateCandidate(points)
            gesturePrimary = points
            gestureConfirmation = []
            auth.authMessage = L.string("First gesture recorded. Draw it again with a similar route and rhythm.")
        } catch {
            gesturePrimary = []
            gestureConfirmation = []
            auth.authMessage = error.localizedDescription
        }
    }

    private func recordConfirmationGesture(_ points: [GesturePoint]) {
        do {
            try GestureCredentialService.validateCandidate(points)
            gestureConfirmation = points
            auth.authMessage = L.string("Confirmation gesture recorded.")
        } catch {
            gestureConfirmation = []
            auth.authMessage = error.localizedDescription
        }
    }

    private func normalizedSecurityCode(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(backupKeyLength))
    }

    private var validationMessage: String {
        switch step {
        case .drawGesture:
            L.string("Draw the first gesture first.")
        case .confirmGesture:
            L.string("Draw the confirmation gesture again.")
        case .securityCode:
            L.format("Security code must be exactly %d digits.", backupKeyLength)
        case .confirmSecurityCode:
            L.string("Security codes must match.")
        }
    }
}

struct CloudVaultRestoreView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthenticationManager
    @EnvironmentObject private var subscription: SubscriptionManager
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var vaultStore: VaultStore
    var onRestored: () -> Void = {}
    @State private var recoveryKey = ""
    @State private var isRestoring = false
    @State private var didRestore = false
    @State private var restoreMessage: String?

    init(onRestored: @escaping () -> Void = {}) {
        self.onRestored = onRestored
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L.string("Restore iCloud Vault"), systemImage: "icloud.and.arrow.down")
                        .font(.title3.bold())
                    Text(L.string("Enter the recovery key shown on your original device. The app will restore the same encryption root key, then you can set a new local gesture for this device."))
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }

                SecureField(L.string("Recovery key"), text: $recoveryKey)
                    .textContentType(.password)
                    .textInputAutocapitalization(.characters)
                    .textFieldStyle(.roundedBorder)

                if let error = vaultStore.lastError, !didRestore {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.warning)
                }

                if didRestore {
                    StatusPill(title: L.string("Root key restored. Continue setup."), systemImage: "checkmark.circle.fill", tint: AppTheme.success)
                }

                if let restoreMessage {
                    Text(restoreMessage)
                        .font(.footnote)
                        .foregroundStyle(didRestore ? AppTheme.success : AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    Task {
                        isRestoring = true
                        restoreMessage = L.string("Restoring encryption key and downloading iCloud files...")
                        didRestore = await vaultStore.restoreRootKeyFromCloud(
                            recoveryKey: recoveryKey,
                            context: modelContext,
                            sync: sync
                        )
                        isRestoring = false
                        if didRestore {
                            auth.refreshConfigurationFromSecureStorage()
                            restoreMessage = vaultStore.restoreStatusMessage ?? L.string("iCloud vault restored.")
                            onRestored()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                dismiss()
                            }
                        } else {
                            restoreMessage = vaultStore.lastError
                        }
                    }
                } label: {
                    Label(isRestoring ? L.string("Restoring") : L.string("Restore from iCloud"), systemImage: "key.icloud")
                }
                .buttonStyle(AppButtonStyle())
                .disabled(isRestoring || recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .navigationTitle(L.string("iCloud Restore"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.string("Close")) { dismiss() }
                }
            }
        }
    }
}

private struct BackupKeyGridInput: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var value: String
    let length: Int

    private let digits = (1...9).map(String.init) + ["0"]
    private var isPadLayout: Bool { horizontalSizeClass == .regular }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: isPadLayout ? 14 : 10), count: 3)
    }

    var body: some View {
        VStack(spacing: isPadLayout ? 18 : 14) {
            HStack(spacing: isPadLayout ? 9 : 7) {
                ForEach(0..<length, id: \.self) { index in
                    Circle()
                        .fill(index < value.count ? AppTheme.primary : AppTheme.line)
                        .frame(width: isPadLayout ? 18 : 14, height: isPadLayout ? 18 : 14)
                        .overlay(Circle().stroke(AppTheme.primary.opacity(0.18)))
                }
            }
            .accessibilityLabel(L.format("Security code has %d of %d digits", value.count, length))

            LazyVGrid(columns: columns, spacing: isPadLayout ? 14 : 10) {
                ForEach(digits, id: \.self) { digit in
                    Button {
                        guard value.count < length else { return }
                        value.append(digit)
                    } label: {
                        Text(digit)
                            .font(.system(isPadLayout ? .title : .title2, design: .rounded, weight: .bold))
                            .foregroundStyle(AppTheme.ink)
                            .frame(maxWidth: .infinity, minHeight: isPadLayout ? 72 : 58)
                            .background(AppTheme.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L.format("Enter %@", digit))
                }
            }

            Button {
                guard !value.isEmpty else { return }
                value.removeLast()
            } label: {
                Label(L.string("Delete"), systemImage: "delete.left")
                    .font(.system(isPadLayout ? .title3 : .body, design: .rounded, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)
                    .frame(maxWidth: .infinity, minHeight: isPadLayout ? 58 : 46)
                    .background(AppTheme.primary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.string("Delete one security-code digit"))
        }
    }
}

private struct GestureTutorialCard: View {
    @State private var animate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.primary.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line))

                TutorialGestureShape()
                    .trim(from: 0, to: animate ? 1 : 0.08)
                    .stroke(AppTheme.success, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .padding(24)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false), value: animate)

                Circle()
                    .fill(AppTheme.primaryFill)
                    .frame(width: 11, height: 11)
                    .offset(x: animate ? 82 : -88, y: animate ? 10 : 34)
                    .animation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false), value: animate)
            }
            .frame(height: 112)
            .onAppear { animate = true }

            VStack(alignment: .leading, spacing: 7) {
                Label(L.string("Press and draw one continuous stroke."), systemImage: "1.circle")
                Label(L.string("Make the motion long enough, with a clear curve or turn."), systemImage: "2.circle")
                Label(L.string("Draw it again with similar route and rhythm to confirm."), systemImage: "3.circle")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct TutorialGestureShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.08, y: rect.midY + rect.height * 0.26))
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.48, y: rect.midY - rect.height * 0.18),
            control1: CGPoint(x: rect.minX + rect.width * 0.20, y: rect.minY + rect.height * 0.02),
            control2: CGPoint(x: rect.minX + rect.width * 0.34, y: rect.maxY - rect.height * 0.10)
        )
        path.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.92, y: rect.midY + rect.height * 0.08),
            control1: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.02),
            control2: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.maxY - rect.height * 0.16)
        )
        return path
    }
}

enum SetupStep: Int, CaseIterable {
    case securityCode
    case confirmSecurityCode
    case drawGesture
    case confirmGesture

    var title: String {
        switch self {
        case .drawGesture: L.string("Draw Gesture")
        case .confirmGesture: L.string("Confirm Gesture")
        case .securityCode: L.string("Set Security Code")
        case .confirmSecurityCode: L.string("Confirm Security Code")
        }
    }

    var subtitle: String {
        switch self {
        case .drawGesture: L.string("Use muscle memory to create a more natural entry method.")
        case .confirmGesture: L.string("Draw the same gesture again so the app can confirm it matches.")
        case .securityCode: L.string("Enter a 6-digit security code.")
        case .confirmSecurityCode: L.string("Confirm the security code before entering the app.")
        }
    }

    var primaryActionTitle: String {
        self == .confirmGesture ? L.string("Create Vault") : L.string("Next")
    }

    var next: SetupStep {
        SetupStep(rawValue: min(rawValue + 1, SetupStep.allCases.count - 1)) ?? .confirmGesture
    }

    var previous: SetupStep {
        SetupStep(rawValue: max(rawValue - 1, 0)) ?? .securityCode
    }
}

private struct SetupProgressView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let step: SetupStep
    private var isPadLayout: Bool { horizontalSizeClass == .regular }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(SetupStep.allCases, id: \.rawValue) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? AppTheme.primary : AppTheme.line)
                    .frame(height: isPadLayout ? 8 : 6)
                    .overlay(alignment: .leading) {
                        if item == step {
                            Capsule()
                                .fill(AppTheme.accent.opacity(0.45))
                                .frame(width: isPadLayout ? 28 : 22, height: isPadLayout ? 8 : 6)
                                .offset(x: 6)
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.82), value: step)
            }
        }
    }
}

private struct SetupMotionMark: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let isAnimating: Bool
    let step: SetupStep
    private var isPadLayout: Bool { horizontalSizeClass == .regular }
    private var baseSize: CGFloat { isPadLayout ? 108 : 88 }
    private var stepSize: CGFloat { isPadLayout ? 24 : 18 }

    var body: some View {
        ZStack {
            ForEach(0..<3) { index in
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(index == 0 ? AppTheme.primary : AppTheme.line, lineWidth: index == 0 ? 3 : 1)
                    .frame(width: baseSize + CGFloat(index) * stepSize, height: baseSize + CGFloat(index) * stepSize)
                    .rotationEffect(.degrees(isAnimating ? Double(14 + index * 16) : Double(-14 - index * 10)))
                    .scaleEffect(isAnimating ? 1.0 + CGFloat(index) * 0.025 : 0.94)
                    .animation(.easeInOut(duration: 1.8 + Double(index) * 0.35).repeatForever(autoreverses: true), value: isAnimating)
            }

            Image(systemName: stepIcon)
                .font(.system(size: isPadLayout ? 44 : 36, weight: .semibold))
                .foregroundStyle(AppTheme.primary)
                .symbolEffect(.pulse, value: step.rawValue)
        }
        .frame(height: isPadLayout ? 164 : 132)
    }

    private var stepIcon: String {
        switch step {
        case .drawGesture: "scribble.variable"
        case .confirmGesture: "signature"
        case .securityCode: "key.fill"
        case .confirmSecurityCode: "checkmark.seal.fill"
        }
    }
}

private struct SetupCard<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let icon: String
    var title: String? = nil
    var detail: String? = nil
    @ViewBuilder var content: Content
    private var isPadLayout: Bool { horizontalSizeClass == .regular }

    var body: some View {
        VStack(alignment: .leading, spacing: isPadLayout ? 20 : 16) {
            if title != nil || detail != nil {
                HStack(alignment: .top, spacing: isPadLayout ? 14 : 12) {
                    Image(systemName: icon)
                        .font(isPadLayout ? .title2 : .title3)
                        .foregroundStyle(AppTheme.primary)
                        .frame(width: isPadLayout ? 48 : 40, height: isPadLayout ? 48 : 40)
                        .background(AppTheme.primary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 5) {
                        if let title {
                            Text(title)
                                .font(isPadLayout ? .title3.weight(.semibold) : .headline)
                                .foregroundStyle(AppTheme.ink)
                        }
                        if let detail {
                            Text(detail)
                                .font(isPadLayout ? .callout : .subheadline)
                                .foregroundStyle(AppTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            content
        }
        .padding(isPadLayout ? 24 : 18)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line))
    }
}

private struct SetupBackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(AppTheme.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.primary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

struct LockView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var auth: AuthenticationManager
    @State private var showResetGesture = false
    private var isPadLayout: Bool { horizontalSizeClass == .regular }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AppGlassBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: isPadLayout ? 30 : 24) {
                Image(systemName: "lock.fill")
                    .font(.system(size: isPadLayout ? 70 : 52, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)

                VStack(spacing: isPadLayout ? 12 : 8) {
                    Text(L.string("Private Space Locked"))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(L.string("Unlock to view the vault and security center."))
                        .font(isPadLayout ? .title3 : .body)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .multilineTextAlignment(.center)

                if auth.isGestureUnlockEnabled {
                    GestureCapturePad(
                        title: L.string("Draw Gesture to Unlock"),
                        subtitle: L.string("Size and position may differ, but route and rhythm should be close.")
                    ) { points in
                        auth.unlockWithGesture(points)
                    }
                }

                Button(L.string("Forgot gesture? Reset with security code")) {
                    showResetGesture = true
                }
                .buttonStyle(SecondaryButtonStyle())

                if let message = auth.authMessage {
                    Text(message)
                        .font(isPadLayout ? .callout : .footnote)
                        .foregroundStyle(AppTheme.warning)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: isPadLayout ? 620 : .infinity)
            .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
            .padding(.horizontal, isPadLayout ? 56 : 28)
            .padding(.vertical, isPadLayout ? 48 : 28)
                }
            }
        }
        .sheet(isPresented: $showResetGesture) {
            GestureResetView()
        }
    }
}

struct BiometricLockView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var auth: AuthenticationManager
    @State private var isAuthenticating = false
    private var isPadLayout: Bool { horizontalSizeClass == .regular }

    private var availability: BiometricAvailability {
        BiometricAuthService.availability()
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AppGlassBackground().ignoresSafeArea()
                ScrollView {
                    VStack(spacing: isPadLayout ? 30 : 24) {
                Image(systemName: "faceid")
                    .font(.system(size: isPadLayout ? 76 : 58, weight: .semibold))
                    .foregroundStyle(AppTheme.primary)

                VStack(spacing: isPadLayout ? 12 : 8) {
                    Text(L.string("Face ID Required"))
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(L.string("First verify this device with Face ID, then draw your private gesture to open the real vault."))
                        .font(isPadLayout ? .title3 : .body)
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }

                AppCard {
                    VStack(alignment: .leading, spacing: isPadLayout ? 16 : 12) {
                        SecurityStageRow(
                            number: "1",
                            title: L.string("Device owner check"),
                            detail: L.string("Face ID is verified by iOS. The app does not receive or store your face data."),
                            isActive: true
                        )
                        SecurityStageRow(
                            number: "2",
                            title: L.string("Gesture check"),
                            detail: L.string("After Face ID succeeds, draw your gesture. Only both checks together unlock private content."),
                            isActive: false
                        )
                    }
                }

                Button {
                    Task { await authenticate() }
                } label: {
                    Label(isAuthenticating ? L.string("Verifying Face ID") : L.string("Unlock with Face ID"), systemImage: "faceid")
                }
                .buttonStyle(AppButtonStyle())
                .disabled(isAuthenticating || !availability.canEvaluate)

                if !availability.canEvaluate {
                    Text(L.string("Face ID or device authentication is not available on this device. Enable Face ID and a device passcode in iPhone Settings."))
                        .font(isPadLayout ? .callout : .footnote)
                        .foregroundStyle(AppTheme.warning)
                        .multilineTextAlignment(.center)
                }

                if let message = auth.authMessage {
                    Text(message)
                        .font(isPadLayout ? .callout : .footnote)
                        .foregroundStyle(AppTheme.warning)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: isPadLayout ? 620 : .infinity)
            .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
            .padding(.horizontal, isPadLayout ? 56 : 28)
            .padding(.vertical, isPadLayout ? 48 : 28)
                }
            }
        }
        .task {
            guard availability.canEvaluate, !isAuthenticating else { return }
            await authenticate()
        }
    }

    private func authenticate() async {
        isAuthenticating = true
        await auth.unlockWithBiometrics()
        isAuthenticating = false
    }
}

private struct SecurityStageRow: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let number: String
    let title: String
    let detail: String
    let isActive: Bool
    private var isPadLayout: Bool { horizontalSizeClass == .regular }

    var body: some View {
        HStack(alignment: .top, spacing: isPadLayout ? 14 : 12) {
            Text(number)
                .font((isPadLayout ? Font.title3 : Font.headline).weight(.bold))
                .foregroundStyle(isActive ? .white : AppTheme.primary)
                .frame(width: isPadLayout ? 38 : 30, height: isPadLayout ? 38 : 30)
                .background(isActive ? AppTheme.primary : AppTheme.primary.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(isPadLayout ? .title3.weight(.semibold) : .headline)
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(isPadLayout ? .callout : .caption)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
