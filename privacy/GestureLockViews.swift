import SwiftUI

struct GestureCapturePad: View {
    let title: String
    let subtitle: String
    var onComplete: ([GesturePoint]) -> Void

    @State private var points: [GesturePoint] = []
    @State private var currentLocation: CGPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }

            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(AppTheme.primary.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line))

                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: CGPoint(x: first.x * proxy.size.width, y: first.y * proxy.size.height))
                        for point in points.dropFirst() {
                            path.addLine(to: CGPoint(x: point.x * proxy.size.width, y: point.y * proxy.size.height))
                        }
                    }
                    .stroke(AppTheme.primary, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

                    if points.isEmpty {
                        Image(systemName: "scribble.variable")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(AppTheme.primary.opacity(0.34))
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let normalized = GesturePoint(
                                x: min(max(value.location.x / max(proxy.size.width, 1), 0), 1),
                                y: min(max(value.location.y / max(proxy.size.height, 1), 0), 1),
                                t: Date().timeIntervalSinceReferenceDate
                            )
                            points.append(normalized)
                            currentLocation = value.location
                        }
                        .onEnded { _ in
                            onComplete(points)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                points = []
                                currentLocation = nil
                            }
                        }
                )
            }
            .frame(height: 190)
        }
    }
}

struct GestureEnrollmentPanel: View {
    @Binding var primary: [GesturePoint]
    @Binding var confirmation: [GesturePoint]
    var onValidationFailure: (String) -> Void = { _ in }

    private var hasPrimary: Bool { !primary.isEmpty }
    private var hasConfirmation: Bool { !confirmation.isEmpty }

    var body: some View {
        VStack(spacing: 12) {
            GestureCapturePad(
                title: hasPrimary ? L.string("Draw Gesture Again") : L.string("Set Gesture Passcode"),
                subtitle: hasPrimary ? L.string("The second pass confirms muscle memory and similarity.") : L.string("Draw a motion you can remember but others cannot easily reproduce.")
            ) { points in
                do {
                    try GestureCredentialService.validateCandidate(points)
                    if !hasPrimary || hasConfirmation {
                        primary = points
                        confirmation = []
                    } else {
                        confirmation = points
                    }
                } catch {
                    onValidationFailure(error.localizedDescription)
                }
            }

            HStack {
                StatusPill(title: hasPrimary ? L.string("First Pass Recorded") : L.string("Waiting for First Pass"), systemImage: hasPrimary ? "checkmark.circle" : "1.circle", tint: hasPrimary ? AppTheme.success : AppTheme.warning)
                StatusPill(title: hasConfirmation ? L.string("Confirmation Recorded") : L.string("Waiting for Confirmation"), systemImage: hasConfirmation ? "checkmark.circle" : "2.circle", tint: hasConfirmation ? AppTheme.success : AppTheme.warning)
            }
        }
    }
}

struct GestureResetView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthenticationManager
    @State private var backupKey = ""
    @State private var primary: [GesturePoint] = []
    @State private var confirmation: [GesturePoint] = []
    private let backupKeyLength = 6

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.background.ignoresSafeArea()
                VStack(spacing: 18) {
                    SecureField(L.string("Enter security code"), text: $backupKey)
                        .textContentType(.password)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: backupKey) { _, newValue in
                            backupKey = normalizedSecurityCode(newValue)
                        }
                    Text(L.format("Security code is %d digits and is only used to reset the gesture.", backupKeyLength))
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)

                    GestureEnrollmentPanel(primary: $primary, confirmation: $confirmation) { message in
                        auth.authMessage = message
                    }

                    Button(L.string("Reset Gesture")) {
                        let securityCode = normalizedSecurityCode(backupKey)
                        guard securityCode.count == backupKeyLength else {
                            auth.authMessage = L.format("Security code must be exactly %d digits.", backupKeyLength)
                            return
                        }
                        guard !primary.isEmpty, !confirmation.isEmpty else {
                            auth.authMessage = L.string("Complete both new gesture passes first.")
                            return
                        }
                        let success = auth.resetGesture(backupKey: securityCode, primary: primary, confirmation: confirmation)
                        if success {
                            dismiss()
                        } else if GestureCredentialService.verifyBackupKey(securityCode) {
                            confirmation = []
                        }
                    }
                    .buttonStyle(AppButtonStyle())

                    if let message = auth.authMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(AppTheme.warning)
                    }
                }
                .padding(24)
            }
            .navigationTitle(L.string("Reset Gesture"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.string("Close")) { dismiss() }
                        .foregroundStyle(AppTheme.primary)
                }
            }
        }
    }

    private func normalizedSecurityCode(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(backupKeyLength))
    }
}
