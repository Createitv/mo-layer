import AVFoundation
import Combine
import CoreImage
import CoreImage.CIFilterBuiltins
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
#if canImport(VisionKit)
import VisionKit
#endif

struct ImportHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var subscription: SubscriptionManager
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var importQueue: VaultImportQueue
    var showsCloseButton = false
    var destinationFolderId: String? = nil
    var onImported: (ImportSummary) -> Void = { _ in }
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var showAudioRecorder = false
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if !subscription.canImportAndSync {
                        AppCard {
                            Label(L.string("Renew Pro to import new files."), systemImage: "star.circle")
                                .foregroundStyle(AppTheme.warning)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    PhotosPicker(selection: $pickerItems, matching: .any(of: [.images, .videos, .livePhotos])) {
                        ActionRow(icon: "photo.on.rectangle", title: L.string("Import from Photos"), subtitle: L.string("Photos and videos"))
                    }
                    .buttonStyle(.plain)
                    .disabled(!subscription.canImportAndSync)

                    Button {
                        showFileImporter = true
                    } label: {
                        ActionRow(icon: "folder", title: L.string("Import from Files"), subtitle: L.string("PDFs, documents, and archives"))
                    }
                    .buttonStyle(.plain)
                    .disabled(!subscription.canImportAndSync)

                    Button {
                        showCamera = true
                    } label: {
                        ActionRow(icon: "camera.viewfinder", title: L.string("Take Photo or Video"), subtitle: L.string("Use the full-screen camera and save directly to the vault"))
                    }
                    .buttonStyle(.plain)
                    .disabled(!subscription.canImportAndSync || !UIImagePickerController.isSourceTypeAvailable(.camera))

                    Button {
                        showAudioRecorder = true
                    } label: {
                        ActionRow(icon: "waveform.circle", title: L.string("Record Audio"), subtitle: L.string("Record a voice memo directly into the vault"))
                    }
                    .buttonStyle(.plain)
                    .disabled(!subscription.canImportAndSync)

                    Button {
                        showScanner = true
                    } label: {
                        ActionRow(icon: "doc.viewfinder", title: L.string("Scan Document"), subtitle: L.string("IDs, contracts, and receipts as encrypted images"))
                    }
                    .buttonStyle(.plain)
                    .disabled(!subscription.canImportAndSync || !isDocumentScannerAvailable)
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle(L.string("Import"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                vaultStore.setWriteAccess(subscription.canImportAndSync)
            }
            .onChange(of: subscription.canImportAndSync) { _, canWrite in
                vaultStore.setWriteAccess(canWrite)
            }
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L.string("Close")) { dismiss() }
                    }
                }
            }
            .onChange(of: pickerItems) { _, newItems in
                guard subscription.canImportAndSync else {
                    pickerItems = []
                    return
                }
                guard !newItems.isEmpty else { return }
                importQueue.importPickerItems(newItems, context: modelContext, vaultStore: vaultStore, sync: sync, folderId: destinationFolderId) { summary in
                    handleImported(summary)
                }
                pickerItems = []
                if showsCloseButton {
                    dismiss()
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                guard subscription.canImportAndSync else { return }
                if case .success(let urls) = result {
                    importQueue.importFiles(urls: urls, context: modelContext, vaultStore: vaultStore, sync: sync, folderId: destinationFolderId) { summary in
                        handleImported(summary)
                    }
                    if showsCloseButton {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                NativeCameraCaptureView { media in
                    guard subscription.canImportAndSync else { return }
                    Task {
                        let summary = await media.importSummary(context: modelContext, vaultStore: vaultStore, sync: sync, folderId: destinationFolderId)
                        handleImported(summary)
                    }
                }
            }
            .fullScreenCover(isPresented: $showAudioRecorder) {
                AudioRecorderView { url, completion in
                    guard subscription.canImportAndSync else {
                        completion(false)
                        return
                    }
                    Task {
                        let summary = await ImportService.importFiles(
                            urls: [url],
                            context: modelContext,
                            vaultStore: vaultStore,
                            sync: sync,
                            source: "Recorder",
                            folderId: destinationFolderId
                        )
                        try? FileManager.default.removeItem(at: url)
                        handleImported(summary)
                        completion(summary.importedCount > 0)
                    }
                }
            }
            .sheet(isPresented: $showScanner) { scannerSheet }
        }
    }

    private func handleImported(_ summary: ImportSummary) {
        guard summary.importedCount > 0 || summary.failedCount > 0 else { return }
        onImported(summary)
        if showsCloseButton {
            dismiss()
        }
    }

    private var isDocumentScannerAvailable: Bool {
        #if canImport(VisionKit)
        VNDocumentCameraViewController.isSupported
        #else
        false
        #endif
    }

    @ViewBuilder
    private var scannerSheet: some View {
        #if canImport(VisionKit)
        DocumentScannerView { images in
            guard subscription.canImportAndSync else { return }
            Task {
                var summary = ImportSummary()
                for (index, image) in images.enumerated() {
                    guard let data = image.jpegData(compressionQuality: 0.9) else { continue }
                    let success = await vaultStore.importData(
                        data,
                        originalName: "Scan-\(Date().timeIntervalSince1970)-\(index + 1).jpg",
                        mimeType: "image/jpeg",
                        source: "Scanner",
                        kind: .image,
                        context: modelContext,
                        sync: sync,
                        folderId: destinationFolderId
                    )
                    if success {
                        summary.record(.image)
                    } else {
                        summary.recordFailure()
                    }
                }
                handleImported(summary)
            }
        }
        #else
        EmptyView()
        #endif
    }
}

enum CapturedVaultMedia {
    case photo(UIImage)
    case video(URL)
    case livePhoto(LivePhotoPackage, originalName: String)

    @MainActor
    func importSummary(
        context: ModelContext,
        vaultStore: VaultStore,
        sync: CloudKitSyncService,
        source: String = "Camera",
        folderId: String? = nil
    ) async -> ImportSummary {
        var summary = ImportSummary()
        switch self {
        case .photo(let image):
            guard let data = image.jpegData(compressionQuality: 0.92) else {
                summary.recordFailure()
                return summary
            }
            let success = await vaultStore.importData(
                data,
                originalName: "Photo-\(Int(Date().timeIntervalSince1970)).jpg",
                mimeType: "image/jpeg",
                source: source,
                kind: .image,
                context: context,
                sync: sync,
                folderId: folderId
            )
            success ? summary.record(.image) : summary.recordFailure()
        case .video(let url):
            summary = await ImportService.importFiles(
                urls: [url],
                context: context,
                vaultStore: vaultStore,
                sync: sync,
                source: source,
                folderId: folderId
            )
            try? FileManager.default.removeItem(at: url)
        case .livePhoto(let package, let originalName):
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            guard let data = try? encoder.encode(package) else {
                summary.recordFailure()
                return summary
            }
            let success = await vaultStore.importData(
                data,
                originalName: originalName,
                mimeType: "application/vnd.apple.live-photo",
                source: source,
                kind: .livePhoto,
                context: context,
                sync: sync,
                folderId: folderId
            )
            success ? summary.record(.livePhoto) : summary.recordFailure()
        }
        return summary
    }
}

struct ActionRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        AppCard {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: 42, height: 42)
                    .background(AppTheme.primary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}

struct SecurityCenterView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var auth: AuthenticationManager
    @EnvironmentObject private var subscription: SubscriptionManager
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var vaultStore: VaultStore
    @EnvironmentObject private var remoteChanges: CloudSyncRemoteChangeRouter
    @State private var isBackingUp = false

    var body: some View {
        let diagnostics = sync.diagnosticSnapshot(lastRemoteChange: remoteChanges.lastReason)
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(L.string("Security Status"))
                                    .font(.title3.bold())
                                Spacer()
                                StatusPill(title: L.string("Encrypted"), systemImage: "lock.shield")
                            }
                            Text(L.string("Recovery Key"))
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                            Text(VaultCryptoService.currentRecoveryKey())
                                .font(.system(.callout, design: .monospaced, weight: .semibold))
                                .textSelection(.enabled)
                                .foregroundStyle(AppTheme.ink)
                        }
                    }

                    AppCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(L.string("Two-step vault unlock"), systemImage: "lock.shield")
                                .font(.headline)
                                .foregroundStyle(AppTheme.ink)
                            Text(L.string("Palimpsest now requires two checks before showing private content: first Face ID through iOS, then your private gesture template stored on this device."))
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            VStack(alignment: .leading, spacing: 8) {
                                SecurityNoteLine(icon: "faceid", text: L.string("Set up Face ID and a device passcode in iPhone Settings. The app only receives a yes or no result from iOS."))
                                SecurityNoteLine(icon: "scribble.variable", text: L.string("After Face ID succeeds, draw the gesture you enrolled. Wrong gestures continue into the decoy space."))
                                SecurityNoteLine(icon: "lock.rotation", text: L.string("Leaving the app locks both layers again and clears temporary decrypted previews."))
                            }
                        }
                    }

                    AppCard {
                        Toggle(isOn: $auth.requiresBiometricUnlock) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(L.string("Require Face ID"))
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.ink)
                                Text(L.string("When enabled, opening the real vault requires Face ID first, then your gesture. When disabled, only the gesture is required."))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(AppTheme.primary)
                    }

                    SecurityRow(icon: "faceid", title: L.string("Face ID Gate"), detail: L.string("The first unlock layer uses iOS device authentication before the gesture screen appears."), status: auth.requiresBiometricUnlock ? L.string("Enabled") : L.string("Off"))
                    SecurityRow(icon: "scribble.variable", title: L.string("Gesture Unlock"), detail: L.string("Verified from the on-device gesture template. Never uploaded to a server."), status: auth.isGestureUnlockEnabled ? L.string("Enabled") : L.string("Not Set"))
                    SecurityRow(icon: "icloud", title: L.string("CloudKit Encrypted Sync"), detail: sync.state.detail, status: sync.state.title)
                    AppCard {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.icloud.fill")
                                .font(.title3)
                                .foregroundStyle(AppTheme.success)
                                .frame(width: 34, height: 34)
                                .background(AppTheme.success.opacity(0.12))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 5) {
                                Text(L.string("Encrypted iCloud Sync is always on"))
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.ink)
                                Text(L.string("Vault items are encrypted on this device and backed up to your private iCloud when available. This uses your iCloud storage and can restore data on your own devices signed in with the same iCloud account."))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    SecurityRow(icon: "eye.slash", title: L.string("Background Shield"), detail: L.string("Locks and clears temporary files when the app leaves the foreground."), status: L.string("On"))
                    SecurityRow(icon: "note.text", title: L.string("Decoy Notes"), detail: L.string("Wrong gestures open a realistic notes space with todos and conversation notes."), status: L.string("Enabled"))
                    SecurityRow(icon: "camera.viewfinder", title: L.string("Intrusion Capture"), detail: L.string("Camera permission is requested only after you enable it."), status: L.string("Off"))
                    SecurityRow(
                        icon: "antenna.radiowaves.left.and.right",
                        title: L.string("Multi-Device Push"),
                        detail: diagnostics.subscriptionDetail,
                        status: diagnostics.subscriptionStatus
                    )
                    CloudSyncDiagnosticsCard(
                        snapshot: diagnostics,
                        remoteNotificationStatus: remoteChanges.registrationStatus
                    )

                    Button {
                        Task { await sync.checkAccountStatus() }
                    } label: {
                        Label(L.string("Recheck iCloud"), systemImage: "arrow.clockwise.icloud")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    if !subscription.canImportAndSync {
                        AppCard {
                            Label(L.string("Active Pro is required to upload encrypted files to iCloud."), systemImage: "star.circle")
                                .font(.caption)
                                .foregroundStyle(AppTheme.warning)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    Button {
                        Task { await runManualBackup() }
                    } label: {
                        Label(backupButtonTitle, systemImage: "icloud.and.arrow.up")
                    }
                    .buttonStyle(AppButtonStyle())
                    .disabled(isBackingUp || !subscription.canImportAndSync)

                    if let summary = sync.lastRunSummary {
                        AppCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L.string("Last iCloud Backup"))
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.ink)
                                Text(summary.statusText)
                                    .font(.caption)
                                    .foregroundStyle(summary.totalFailed == 0 ? AppTheme.success : AppTheme.warning)
                                ForEach(summary.failureMessages, id: \.self) { message in
                                    Text(message)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(AppTheme.secondaryText)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    NavigationLink {
                        CloudSyncLogFileView()
                    } label: {
                        AppCard {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .foregroundStyle(AppTheme.primary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L.string("View iCloud Sync Log File"))
                                        .font(.headline)
                                        .foregroundStyle(AppTheme.ink)
                                    Text(L.string("Detailed technical logs are saved locally in the app and are not shown on this page."))
                                        .font(.caption)
                                        .foregroundStyle(AppTheme.secondaryText)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle(L.string("Security Center"))
        }
    }

    private var backupButtonTitle: String {
        if isBackingUp {
            return L.string("Backing Up All Files")
        }
        return L.string("Back Up All Files to iCloud")
    }

    @MainActor
    private func runManualBackup() async {
        isBackingUp = true
        defer { isBackingUp = false }
        vaultStore.setWriteAccess(subscription.canImportAndSync)
        _ = await vaultStore.backupAllFilesToCloud(
            context: modelContext,
            sync: sync,
            allowsCloudSync: subscription.canImportAndSync
        )
    }
}

private struct CloudSyncDiagnosticsCard: View {
    let snapshot: CloudSyncDiagnosticSnapshot
    let remoteNotificationStatus: String

    var body: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(L.string("iCloud Development Diagnostics"), systemImage: "stethoscope")
                    .font(.headline)
                    .foregroundStyle(AppTheme.ink)
                diagnosticRow(L.string("Container"), snapshot.containerIdentifier)
                diagnosticRow(L.string("Environment"), snapshot.environment)
                diagnosticRow(L.string("Database"), snapshot.databaseScope)
                diagnosticRow(L.string("Sync Trigger"), snapshot.remoteTriggerMode)
                diagnosticRow(L.string("Record Types"), snapshot.subscriptionRecordTypes.joined(separator: ", "))
                diagnosticRow(L.string("Schema Status"), snapshot.schemaStatus)
                diagnosticRow(L.string("Schema Detail"), snapshot.schemaDetail)
                if !snapshot.missingRecordTypes.isEmpty {
                    diagnosticRow(L.string("Missing Record Types"), snapshot.missingRecordTypes.joined(separator: ", "))
                }
                if !snapshot.missingQueryableIndexes.isEmpty {
                    diagnosticRow(L.string("Missing Queryable Indexes"), snapshot.missingQueryableIndexes.joined(separator: ", "))
                }
                diagnosticRow(L.string("APNs Registration"), remoteNotificationStatus)
                diagnosticRow(L.string("iCloud Status"), snapshot.iCloudStatus)
                diagnosticRow(L.string("Last Successful Sync"), snapshot.lastSuccessfulSync)
                diagnosticRow(L.string("Last Remote Change"), snapshot.lastRemoteChange)
                if let lastSchemaError = snapshot.lastSchemaError, !lastSchemaError.isEmpty {
                    diagnosticRow(L.string("Last CloudKit Schema Error"), lastSchemaError)
                }
                if let lastError = snapshot.lastError, !lastError.isEmpty {
                    diagnosticRow(L.string("Last Sync Error"), lastError)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func diagnosticRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(AppTheme.ink)
            Text(value)
                .font(.caption2.monospaced())
                .foregroundStyle(AppTheme.secondaryText)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct CloudSyncLogFileView: View {
    @EnvironmentObject private var sync: CloudKitSyncService
    @State private var logText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                AppCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L.string("Local Log File"))
                            .font(.headline)
                            .foregroundStyle(AppTheme.ink)
                        Text(sync.logFileURL.path)
                            .font(.caption2.monospaced())
                            .foregroundStyle(AppTheme.secondaryText)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(logText.isEmpty ? L.string("No iCloud sync log has been written yet.") : logText)
                    .font(.caption2.monospaced())
                    .foregroundStyle(AppTheme.secondaryText)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(AppTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line))
            }
            .padding()
        }
        .background(AppTheme.background)
        .navigationTitle(L.string("iCloud Sync Log"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    UIPasteboard.general.string = logText
                } label: {
                    Label(L.string("Copy"), systemImage: "doc.on.doc")
                }
                .disabled(logText.isEmpty)
            }
        }
        .task {
            reload()
        }
    }

    private func reload() {
        logText = sync.readLogFile()
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject private var auth: AuthenticationManager
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var subscription: SubscriptionManager
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.english.rawValue
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue

    private var preferenceRefreshToken: SettingsPreferenceRefreshToken {
        SettingsPreferenceRefreshToken(language: language, appearance: appearance)
    }

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.icloud.fill")
                        .foregroundStyle(AppTheme.success)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L.string("Encrypted iCloud Sync"))
                            .foregroundStyle(AppTheme.ink)
                        Text(L.string("Always on. Existing vault content continues syncing even when adding new files requires Pro."))
                            .font(.caption)
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    Text(sync.state.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            } header: {
                Text(L.string("iCloud"))
            }

            Section {
                NavigationLink {
                    MembershipView()
                        .environmentObject(subscription)
                } label: {
                    SettingsNavigationRow(
                        icon: "star.circle",
                        title: L.string("Membership"),
                        detail: L.string("Manage trial, monthly, yearly, lifetime, and restore purchases")
                    )
                }

                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    SettingsNavigationRow(
                        icon: "circle.lefthalf.filled",
                        title: L.string("Appearance"),
                        detail: L.string("Light Mode, Dark Mode, or Follow System")
                    )
                }

                NavigationLink {
                    AppLanguageSettingsView()
                } label: {
                    SettingsNavigationRow(
                        icon: "globe",
                        title: L.string("App Language"),
                        detail: L.string("Choose the language used inside the app")
                    )
                }

                NavigationLink {
                    UnlockGracePeriodSettingsView()
                        .environmentObject(auth)
                } label: {
                    SettingsNavigationRow(
                        icon: "timer",
                        title: L.string("Unlock Grace Period"),
                        detail: L.string("Skip repeated Face ID and gesture checks after returning from the background")
                    )
                }
            } header: {
                Text(L.string("General Settings"))
            }
        }
        .id(preferenceRefreshToken)
        .navigationTitle(L.string("General Settings"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct UnlockGracePeriodSettingsView: View {
    @EnvironmentObject private var auth: AuthenticationManager

    var body: some View {
        List {
            Section {
                ForEach(AuthenticationManager.ReauthenticationGracePeriod.allCases) { option in
                    Button {
                        auth.reauthenticationGracePeriod = option
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.title)
                                    .foregroundStyle(AppTheme.ink)
                                Text(option.detail)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()

                            if auth.reauthenticationGracePeriod == option {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppTheme.primary)
                            }
                        }
                    }
                }
            } footer: {
                Text(L.string("When enabled, Palimpsest remembers a successful unlock for the selected time after the app enters the background. Closing or relaunching the app still starts locked."))
            }
        }
        .navigationTitle(L.string("Unlock Grace Period"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AppearanceSettingsView: View {
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.english.rawValue

    private var preferenceRefreshToken: SettingsPreferenceRefreshToken {
        SettingsPreferenceRefreshToken(language: language, appearance: appearance)
    }

    var body: some View {
        List {
            Section {
                ForEach(AppAppearance.allCases) { option in
                    Button {
                        appearance = option.rawValue
                        Task { @MainActor in
                            option.applyToConnectedWindows()
                        }
                    } label: {
                        HStack {
                            Text(option.title)
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            if appearance == option.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppTheme.primary)
                            }
                        }
                    }
                }
            } footer: {
                Text(L.string("Choose how the app should appear on this device."))
            }
        }
        .id(preferenceRefreshToken)
        .navigationTitle(L.string("Appearance"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AppLanguageSettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.english.rawValue
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue

    private var preferenceRefreshToken: SettingsPreferenceRefreshToken {
        SettingsPreferenceRefreshToken(language: language, appearance: appearance)
    }

    var body: some View {
        List {
            Section {
                ForEach(AppLanguage.allCases) { option in
                    Button {
                        language = option.rawValue
                    } label: {
                        HStack {
                            Text(option.title)
                                .foregroundStyle(AppTheme.ink)
                            Spacer()
                            if language == option.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppTheme.primary)
                            }
                        }
                    }
                }
            } footer: {
                Text(L.string("Default follows your iPhone language and region. Choose a language here to override it inside the app."))
            }
        }
        .id(preferenceRefreshToken)
        .navigationTitle(L.string("App Language"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        DocumentPage(title: L.string("Privacy Policy"), subtitle: L.string("Last updated: May 29, 2026")) {
            DocumentSection(
                title: L.string("Overview"),
                paragraphs: [
                    L.string("Palimpsest is designed as a private vault that keeps your sensitive files under your control."),
                    L.string("Your vault content is encrypted on this device before storage. If iCloud sync is enabled, encrypted files and metadata are synced through your private iCloud container.")
                ]
            )

            DocumentSection(
                title: L.string("Data We Store"),
                paragraphs: [
                    L.string("The app stores vault files, thumbnails, encrypted metadata, folders, import records, sync status, and local security settings needed to operate the vault."),
                    L.string("Gesture templates and recovery information are stored on this device using local protected storage. They are not sent to an app server.")
                ]
            )

            DocumentSection(
                title: L.string("iCloud Sync"),
                paragraphs: [
                    L.string("When iCloud sync is available, encrypted vault data may be copied to your private iCloud container so your own devices can recover or download it."),
                    L.string("iCloud availability, account access, and storage behavior are controlled by Apple and your iCloud account settings.")
                ]
            )

            DocumentSection(
                title: L.string("Sharing and Export"),
                paragraphs: [
                    L.string("We do not sell your data or upload decrypted vault files to an app server. Sharing and export actions are started only when you choose them."),
                    L.string("When you export or share an item, iOS may hand the selected file to the destination app or system service you choose.")
                ]
            )

            DocumentSection(
                title: L.string("Your Control"),
                paragraphs: [
                    L.string("You can delete vault items, manage permissions in iPhone Settings, and choose whether to use iCloud features."),
                    L.string("Deleting an item from the vault removes the app's local record and attempts to remove the matching encrypted cloud copy when sync is active.")
                ]
            )
        }
        .navigationTitle(L.string("Privacy Policy"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DocumentPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(AppTheme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                content
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppTheme.background)
    }
}

private struct DocumentSection: View {
    let title: String
    let paragraphs: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppTheme.ink)

            ForEach(paragraphs, id: \.self) { paragraph in
                Text(paragraph)
                    .font(.body)
                    .lineSpacing(4)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct UserPermissionsView: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        DocumentPage(title: L.string("User Permissions"), subtitle: L.string("Permissions used by this app")) {
            DocumentSection(
                title: L.string("How Permissions Work"),
                paragraphs: [
                    L.string("Palimpsest asks for a permission only when a feature needs it. You can change most permissions later in iPhone Settings."),
                    L.string("Denying a permission may disable the related feature, but the rest of the vault continues to work locally.")
                ]
            )

            VStack(alignment: .leading, spacing: 12) {
                PermissionDocumentRow(
                    icon: "photo",
                    title: L.string("Photos"),
                    detail: L.string("Used only when you import photos or videos into the encrypted vault.")
                )
                PermissionDocumentRow(
                    icon: "camera",
                    title: L.string("Camera"),
                    detail: L.string("Requested only when you capture directly into the vault.")
                )
                PermissionDocumentRow(
                    icon: "faceid",
                    title: L.string("Device Authentication"),
                    detail: L.string("Used as the first unlock layer before your private gesture can open the encrypted vault.")
                )
                PermissionDocumentRow(
                    icon: "location",
                    title: L.string("Location"),
                    detail: L.string("Used only when you choose location-related protection features that need your current location.")
                )
                PermissionDocumentRow(
                    icon: "icloud",
                    title: L.string("iCloud"),
                    detail: L.string("Used to sync encrypted vault data through your private iCloud account.")
                )
                PermissionDocumentRow(
                    icon: "folder",
                    title: L.string("Files"),
                    detail: L.string("Used when you import or export files with the system file picker.")
                )
                PermissionDocumentRow(
                    icon: "square.and.arrow.up",
                    title: L.string("Share Extension"),
                    detail: L.string("Lets other apps send files into this app for encrypted saving.")
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                DocumentSection(
                    title: L.string("Manage Permissions"),
                    paragraphs: [
                        L.string("Open iPhone Settings to review or change camera, photo, location, and notification-style system permissions for this app.")
                    ]
                )

                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label(L.string("Open iPhone Settings"), systemImage: "gear")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .navigationTitle(L.string("User Permissions"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PermissionDocumentRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(AppTheme.primary)
                .frame(width: 34, height: 34)
                .background(AppTheme.primary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.footnote)
                    .lineSpacing(3)
                    .foregroundStyle(AppTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

private struct SettingsNavigationRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.primary)
                .frame(width: 30, height: 30)
                .background(AppTheme.primary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}

private struct PermissionInfoRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppTheme.primary)
                .frame(width: 30, height: 30)
                .background(AppTheme.primary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .foregroundStyle(AppTheme.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct SecurityNoteLine: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.primary)
                .frame(width: 20, height: 20)
            Text(text)
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SecurityRow: View {
    let icon: String
    let title: String
    let detail: String
    let status: String

    var body: some View {
        AppCard {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(AppTheme.primary)
                    .frame(width: 36, height: 36)
                    .background(AppTheme.primary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(AppTheme.secondaryText)
                }
                Spacer()
                Text(status)
                    .font(.caption.bold())
                    .foregroundStyle(AppTheme.primary)
            }
        }
    }
}

struct NativeCameraCaptureView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onMedia: (CapturedVaultMedia) -> Void

    func makeUIViewController(context: Context) -> VaultCameraViewController {
        let controller = VaultCameraViewController()
        controller.onMedia = { media in
            onMedia(media)
            dismiss()
        }
        controller.onCancel = {
            dismiss()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: VaultCameraViewController, context: Context) {}
}

final class VaultCameraViewController: UIViewController {
    var onMedia: ((CapturedVaultMedia) -> Void)?
    var onCancel: (() -> Void)?

    private enum CaptureMode: Int, CaseIterable {
        case photo
        case video
        case live

        var title: String {
            switch self {
            case .photo: L.string("PHOTO")
            case .video: L.string("VIDEO")
            case .live: L.string("LIVE")
            }
        }
    }

    private enum CameraFilter: Int, CaseIterable {
        case original
        case vivid
        case warm
        case cool
        case mono
        case noir

        var title: String {
            switch self {
            case .original: L.string("Original")
            case .vivid: L.string("Vivid")
            case .warm: L.string("Warm")
            case .cool: L.string("Cool")
            case .mono: L.string("Mono")
            case .noir: L.string("Noir")
            }
        }
    }

    private enum TimerDelay: Int, CaseIterable {
        case off = 0
        case three = 3
        case ten = 10

        var title: String {
            switch self {
            case .off: L.string("Timer")
            case .three: L.string("3s")
            case .ten: L.string("10s")
            }
        }
    }

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "app.landlady.www.privacy.camera")
    private let previewView = CameraPreviewView()
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let ciContext = CIContext()

    private var videoDeviceInput: AVCaptureDeviceInput?
    private var captureMode: CaptureMode = .photo
    private var cameraFilter: CameraFilter = .original
    private var timerDelay: TimerDelay = .off
    private var flashMode: AVCaptureDevice.FlashMode = .auto
    private var isGridVisible = false
    private var useMaxDimensions = true
    private var isFocusLocked = false
    private var pendingPhotoData: Data?
    private var pendingLivePhotoURL: URL?
    private var recordingURL: URL?
    private var countdownTimer: Timer?
    private var recordingTimer: Timer?
    private var recordingStartedAt: Date?
    private var currentZoomFactor: CGFloat = 1

    private let topBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let bottomBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let closeButton = UIButton(type: .system)
    private let flashButton = UIButton(type: .system)
    private let liveButton = UIButton(type: .system)
    private let maxButton = UIButton(type: .system)
    private let gridButton = UIButton(type: .system)
    private let timerButton = UIButton(type: .system)
    private let flipButton = UIButton(type: .system)
    private let shutterButton = UIButton(type: .system)
    private let modeControl = UISegmentedControl(items: CaptureMode.allCases.map(\.title))
    private let filterControl = UISegmentedControl(items: CameraFilter.allCases.map(\.title))
    private let zoomStack = UIStackView()
    private let gridOverlay = CameraGridOverlayView()
    private let focusRing = UIView()
    private let statusLabel = UILabel()
    private let countdownLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureUI()
        configureGestures()
        requestAccessAndConfigure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewView.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        countdownTimer?.invalidate()
        recordingTimer?.invalidate()
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configureUI() {
        previewView.session = session
        previewView.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.addSubview(previewView)
        previewView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        gridOverlay.isHidden = true
        gridOverlay.backgroundColor = .clear
        view.addSubview(gridOverlay)
        gridOverlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            gridOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gridOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gridOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            gridOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        configureControlButton(closeButton, systemName: "xmark")
        configureControlButton(flashButton, systemName: "bolt.badge.automatic")
        configureControlButton(liveButton, systemName: "livephoto")
        configureControlButton(maxButton, title: "MAX")
        configureControlButton(gridButton, systemName: "grid")
        configureControlButton(timerButton, systemName: "timer")
        configureControlButton(flipButton, systemName: "arrow.triangle.2.circlepath.camera")
        configureShutterButton()

        closeButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        flashButton.addTarget(self, action: #selector(cycleFlash), for: .touchUpInside)
        liveButton.addTarget(self, action: #selector(liveTapped), for: .touchUpInside)
        maxButton.addTarget(self, action: #selector(toggleMax), for: .touchUpInside)
        gridButton.addTarget(self, action: #selector(toggleGrid), for: .touchUpInside)
        timerButton.addTarget(self, action: #selector(cycleTimer), for: .touchUpInside)
        flipButton.addTarget(self, action: #selector(flipCamera), for: .touchUpInside)
        shutterButton.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)

        topBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)
        view.addSubview(bottomBar)

        let topStack = UIStackView(arrangedSubviews: [closeButton, UIView(), flashButton, liveButton, maxButton, gridButton, timerButton])
        topStack.axis = .horizontal
        topStack.spacing = 10
        topStack.alignment = .center
        topStack.translatesAutoresizingMaskIntoConstraints = false
        topBar.contentView.addSubview(topStack)

        modeControl.selectedSegmentIndex = captureMode.rawValue
        modeControl.selectedSegmentTintColor = .white
        modeControl.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.72)], for: .normal)
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)

        filterControl.selectedSegmentIndex = cameraFilter.rawValue
        filterControl.selectedSegmentTintColor = UIColor.white.withAlphaComponent(0.92)
        filterControl.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        filterControl.setTitleTextAttributes([.foregroundColor: UIColor.white.withAlphaComponent(0.72), .font: UIFont.systemFont(ofSize: 11, weight: .semibold)], for: .normal)
        filterControl.setTitleTextAttributes([.foregroundColor: UIColor.black, .font: UIFont.systemFont(ofSize: 11, weight: .semibold)], for: .selected)
        filterControl.addTarget(self, action: #selector(filterChanged), for: .valueChanged)

        zoomStack.axis = .horizontal
        zoomStack.spacing = 8
        zoomStack.alignment = .center
        [0.5, 1, 2, 3].forEach { factor in
            let button = UIButton(type: .system)
            button.setTitle(factor == 1 ? "1x" : "\(factor)x", for: .normal)
            button.tag = Int(factor * 10)
            button.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
            button.setTitleColor(.white, for: .normal)
            button.backgroundColor = UIColor.black.withAlphaComponent(factor == 1 ? 0.75 : 0.42)
            button.layer.cornerRadius = 16
            button.addTarget(self, action: #selector(zoomButtonTapped(_:)), for: .touchUpInside)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
            button.heightAnchor.constraint(equalToConstant: 32).isActive = true
            zoomStack.addArrangedSubview(button)
        }

        statusLabel.textColor = .white
        statusLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        statusLabel.textAlignment = .center
        statusLabel.text = ""

        let bottomStack = UIStackView(arrangedSubviews: [filterControl, zoomStack, modeControl, controlsRow()])
        bottomStack.axis = .vertical
        bottomStack.spacing = 14
        bottomStack.alignment = .center
        bottomStack.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.contentView.addSubview(bottomStack)

        view.addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        countdownLabel.textColor = .white
        countdownLabel.font = .systemFont(ofSize: 76, weight: .bold)
        countdownLabel.textAlignment = .center
        countdownLabel.isHidden = true
        view.addSubview(countdownLabel)
        countdownLabel.translatesAutoresizingMaskIntoConstraints = false

        focusRing.layer.borderColor = UIColor.systemYellow.cgColor
        focusRing.layer.borderWidth = 2
        focusRing.layer.cornerRadius = 42
        focusRing.alpha = 0
        view.addSubview(focusRing)

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.topAnchor.constraint(equalTo: view.topAnchor),

            topStack.leadingAnchor.constraint(equalTo: topBar.contentView.leadingAnchor, constant: 16),
            topStack.trailingAnchor.constraint(equalTo: topBar.contentView.trailingAnchor, constant: -16),
            topStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            topStack.bottomAnchor.constraint(equalTo: topBar.contentView.bottomAnchor, constant: -10),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            bottomStack.leadingAnchor.constraint(greaterThanOrEqualTo: bottomBar.contentView.leadingAnchor, constant: 16),
            bottomStack.trailingAnchor.constraint(lessThanOrEqualTo: bottomBar.contentView.trailingAnchor, constant: -16),
            bottomStack.centerXAnchor.constraint(equalTo: bottomBar.contentView.centerXAnchor),
            bottomStack.topAnchor.constraint(equalTo: bottomBar.contentView.topAnchor, constant: 14),
            bottomStack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14),

            modeControl.widthAnchor.constraint(equalTo: bottomBar.contentView.widthAnchor, multiplier: 0.72),
            filterControl.widthAnchor.constraint(equalTo: bottomBar.contentView.widthAnchor, multiplier: 0.92),

            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: bottomBar.topAnchor, constant: -14),

            countdownLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            countdownLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        updateButtons()
    }

    private func controlsRow() -> UIStackView {
        let row = UIStackView(arrangedSubviews: [UIView(), shutterButton, flipButton])
        row.axis = .horizontal
        row.spacing = 34
        row.alignment = .center
        row.distribution = .equalCentering
        row.widthAnchor.constraint(equalToConstant: 230).isActive = true
        return row
    }

    private func configureControlButton(_ button: UIButton, systemName: String? = nil, title: String? = nil) {
        if let systemName {
            button.setImage(UIImage(systemName: systemName), for: .normal)
        }
        if let title {
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 12, weight: .bold)
        }
        button.tintColor = .white
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.34)
        button.layer.cornerRadius = 18
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func configureShutterButton() {
        shutterButton.backgroundColor = .white
        shutterButton.layer.cornerRadius = 36
        shutterButton.layer.borderWidth = 5
        shutterButton.layer.borderColor = UIColor.white.withAlphaComponent(0.38).cgColor
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            shutterButton.widthAnchor.constraint(equalToConstant: 72),
            shutterButton.heightAnchor.constraint(equalToConstant: 72)
        ])
    }

    private func configureGestures() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleFocusTap(_:)))
        previewView.addGestureRecognizer(tap)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleFocusLock(_:)))
        previewView.addGestureRecognizer(longPress)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        previewView.addGestureRecognizer(pinch)
    }

    private func requestAccessAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.configureSession() : self?.showPermissionMessage()
                }
            }
        default:
            showPermissionMessage()
        }
    }

    private func showPermissionMessage() {
        statusLabel.text = L.string("Camera permission is required.")
        shutterButton.isEnabled = false
    }

    private func configureSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }

            guard let videoDevice = self.preferredDevice(position: .back),
                  let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
                  self.session.canAddInput(videoInput) else {
                DispatchQueue.main.async { self.statusLabel.text = L.string("Unable to start camera.") }
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(videoInput)
            self.videoDeviceInput = videoInput

            if let audioDevice = AVCaptureDevice.default(for: .audio),
               let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
               self.session.canAddInput(audioInput) {
                self.session.addInput(audioInput)
            }

            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
                if self.photoOutput.isLivePhotoCaptureSupported {
                    self.photoOutput.isLivePhotoCaptureEnabled = true
                }
            }

            self.configureMovieOutputIfNeeded()
            self.session.commitConfiguration()
            self.session.startRunning()
            DispatchQueue.main.async { self.updateButtons() }
        }
    }

    private func configureMovieOutputIfNeeded() {
        if captureMode == .video {
            if !session.outputs.contains(movieOutput), session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
            session.sessionPreset = .high
        } else if session.outputs.contains(movieOutput) {
            session.removeOutput(movieOutput)
            session.sessionPreset = .photo
        }
    }

    private func preferredDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: position
        )
        return discovery.devices.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    @objc private func modeChanged() {
        guard let mode = CaptureMode(rawValue: modeControl.selectedSegmentIndex) else { return }
        captureMode = mode
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.configureMovieOutputIfNeeded()
            self.session.commitConfiguration()
        }
        updateButtons()
    }

    @objc private func filterChanged() {
        cameraFilter = CameraFilter(rawValue: filterControl.selectedSegmentIndex) ?? .original
    }

    @objc private func cycleFlash() {
        switch flashMode {
        case .auto: flashMode = .on
        case .on: flashMode = .off
        case .off: flashMode = .auto
        @unknown default: flashMode = .auto
        }
        updateButtons()
    }

    @objc private func liveTapped() {
        captureMode = .live
        modeControl.selectedSegmentIndex = CaptureMode.live.rawValue
        modeChanged()
    }

    @objc private func toggleMax() {
        useMaxDimensions.toggle()
        updateButtons()
    }

    @objc private func toggleGrid() {
        isGridVisible.toggle()
        gridOverlay.isHidden = !isGridVisible
        updateButtons()
    }

    @objc private func cycleTimer() {
        let all = TimerDelay.allCases
        let index = all.firstIndex(of: timerDelay) ?? 0
        timerDelay = all[(index + 1) % all.count]
        updateButtons()
    }

    @objc private func flipCamera() {
        guard let current = videoDeviceInput else { return }
        let newPosition: AVCaptureDevice.Position = current.device.position == .back ? .front : .back
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = self.preferredDevice(position: newPosition),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            self.session.beginConfiguration()
            self.session.removeInput(current)
            if self.session.canAddInput(input) {
                self.session.addInput(input)
                self.videoDeviceInput = input
            } else {
                self.session.addInput(current)
            }
            self.session.commitConfiguration()
            DispatchQueue.main.async {
                self.currentZoomFactor = 1
                self.updateZoomButtons(selected: 1)
                self.updateButtons()
            }
        }
    }

    @objc private func shutterTapped() {
        if captureMode == .video {
            movieOutput.isRecording ? stopRecording() : startRecording()
            return
        }
        if timerDelay == .off {
            capturePhoto()
        } else {
            startCountdown(seconds: timerDelay.rawValue)
        }
    }

    private func startCountdown(seconds: Int) {
        countdownTimer?.invalidate()
        var remaining = seconds
        countdownLabel.text = "\(remaining)"
        countdownLabel.isHidden = false
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { return }
            remaining -= 1
            if remaining <= 0 {
                timer.invalidate()
                self.countdownLabel.isHidden = true
                self.capturePhoto()
            } else {
                self.countdownLabel.text = "\(remaining)"
            }
        }
    }

    private func capturePhoto() {
        pendingPhotoData = nil
        pendingLivePhotoURL = nil
        let settings = AVCapturePhotoSettings()
        if photoOutput.supportedFlashModes.contains(flashMode) {
            settings.flashMode = flashMode
        }
        if useMaxDimensions,
           let dimensions = videoDeviceInput?.device.activeFormat.supportedMaxPhotoDimensions.last {
            settings.maxPhotoDimensions = dimensions
        }
        if captureMode == .live, photoOutput.isLivePhotoCaptureSupported, photoOutput.isLivePhotoCaptureEnabled {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("Live-\(UUID().uuidString)")
                .appendingPathExtension("mov")
            settings.livePhotoMovieFileURL = url
            pendingLivePhotoURL = url
        }
        shutterButton.isEnabled = false
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func startRecording() {
        guard !movieOutput.isRecording else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Video-\(Int(Date().timeIntervalSince1970))")
            .appendingPathExtension("mov")
        recordingURL = url
        movieOutput.startRecording(to: url, recordingDelegate: self)
        recordingStartedAt = Date()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.updateRecordingStatus()
        }
        updateButtons()
    }

    private func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
        recordingTimer?.invalidate()
        recordingTimer = nil
        updateButtons()
    }

    private func updateRecordingStatus() {
        guard let recordingStartedAt else { return }
        let elapsed = Int(Date().timeIntervalSince(recordingStartedAt))
        statusLabel.text = "REC \(elapsed / 60):\(String(format: "%02d", elapsed % 60))"
    }

    @objc private func zoomButtonTapped(_ sender: UIButton) {
        let factor = CGFloat(sender.tag) / 10
        setZoomFactor(factor)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let device = videoDeviceInput?.device else { return }
        if gesture.state == .changed {
            let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 8)
            setZoomFactor(min(max(currentZoomFactor * gesture.scale, 1), maxZoom))
            gesture.scale = 1
        }
    }

    private func setZoomFactor(_ factor: CGFloat) {
        guard let device = videoDeviceInput?.device else { return }
        let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 8)
        let clamped = min(max(factor, 1), maxZoom)
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
            currentZoomFactor = clamped
            updateZoomButtons(selected: clamped)
        } catch {
            statusLabel.text = L.string("Zoom unavailable.")
        }
    }

    private func updateZoomButtons(selected factor: CGFloat) {
        for case let button as UIButton in zoomStack.arrangedSubviews {
            let value = CGFloat(button.tag) / 10
            button.backgroundColor = UIColor.black.withAlphaComponent(abs(value - factor) < 0.1 ? 0.75 : 0.42)
        }
    }

    @objc private func handleFocusTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: previewView)
        isFocusLocked = false
        focus(at: point, locked: false)
    }

    @objc private func handleFocusLock(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: previewView)
        isFocusLocked = true
        focus(at: point, locked: true)
    }

    private func focus(at point: CGPoint, locked: Bool) {
        guard let device = videoDeviceInput?.device else { return }
        let devicePoint = previewView.videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: point)
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
                device.focusMode = locked ? .locked : .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
                device.exposureMode = locked ? .locked : .continuousAutoExposure
            }
            device.unlockForConfiguration()
            showFocusRing(at: point, locked: locked)
            statusLabel.text = locked ? "AE/AF LOCK" : ""
        } catch {
            statusLabel.text = L.string("Focus unavailable.")
        }
    }

    private func showFocusRing(at point: CGPoint, locked: Bool) {
        focusRing.frame = CGRect(x: point.x - 42, y: point.y - 42, width: 84, height: 84)
        focusRing.layer.borderColor = (locked ? UIColor.systemOrange : UIColor.systemYellow).cgColor
        focusRing.transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
        focusRing.alpha = 1
        UIView.animate(withDuration: 0.22) {
            self.focusRing.transform = .identity
        } completion: { _ in
            guard !locked else { return }
            UIView.animate(withDuration: 0.35, delay: 0.55) {
                self.focusRing.alpha = 0
            }
        }
    }

    private func updateButtons() {
        let hasFlash = videoDeviceInput?.device.hasFlash == true
        flashButton.isHidden = !hasFlash || captureMode == .video
        switch flashMode {
        case .auto: flashButton.setImage(UIImage(systemName: "bolt.badge.automatic"), for: .normal)
        case .on: flashButton.setImage(UIImage(systemName: "bolt.fill"), for: .normal)
        case .off: flashButton.setImage(UIImage(systemName: "bolt.slash"), for: .normal)
        @unknown default: flashButton.setImage(UIImage(systemName: "bolt.badge.automatic"), for: .normal)
        }
        let liveSupported = photoOutput.isLivePhotoCaptureSupported
        liveButton.isHidden = !liveSupported
        liveButton.backgroundColor = UIColor.black.withAlphaComponent(captureMode == .live ? 0.75 : 0.34)
        maxButton.backgroundColor = UIColor.black.withAlphaComponent(useMaxDimensions ? 0.75 : 0.34)
        gridButton.backgroundColor = UIColor.black.withAlphaComponent(isGridVisible ? 0.75 : 0.34)
        timerButton.setTitle(timerDelay.title, for: .normal)
        timerButton.setImage(timerDelay == .off ? UIImage(systemName: "timer") : nil, for: .normal)
        filterControl.isHidden = captureMode == .video
        shutterButton.backgroundColor = movieOutput.isRecording ? .systemRed : .white
        shutterButton.layer.cornerRadius = movieOutput.isRecording ? 12 : 36
        shutterButton.isEnabled = true
        if captureMode != .video {
            statusLabel.text = isFocusLocked ? "AE/AF LOCK" : ""
        }
    }

    private func filteredImageData(from data: Data) -> Data? {
        guard cameraFilter != .original,
              let input = CIImage(data: data) else {
            return data
        }

        let output: CIImage?
        switch cameraFilter {
        case .original:
            output = input
        case .vivid:
            let filter = CIFilter.colorControls()
            filter.inputImage = input
            filter.saturation = 1.22
            filter.contrast = 1.08
            output = filter.outputImage
        case .warm:
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = input
            filter.neutral = CIVector(x: 6500, y: 0)
            filter.targetNeutral = CIVector(x: 5600, y: 0)
            output = filter.outputImage
        case .cool:
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = input
            filter.neutral = CIVector(x: 6500, y: 0)
            filter.targetNeutral = CIVector(x: 7800, y: 0)
            output = filter.outputImage
        case .mono:
            let filter = CIFilter.photoEffectMono()
            filter.inputImage = input
            output = filter.outputImage
        case .noir:
            let filter = CIFilter.photoEffectNoir()
            filter.inputImage = input
            output = filter.outputImage
        }

        guard let output,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let jpeg = ciContext.jpegRepresentation(of: output, colorSpace: colorSpace, options: [:]) else {
            return data
        }
        return jpeg
    }
}

extension VaultCameraViewController: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard error == nil,
              let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async {
                self.statusLabel.text = L.string("Unable to capture photo.")
                self.shutterButton.isEnabled = true
            }
            return
        }
        pendingPhotoData = filteredImageData(from: data)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        DispatchQueue.main.async {
            defer {
                self.pendingPhotoData = nil
                self.pendingLivePhotoURL = nil
                self.shutterButton.isEnabled = true
            }
            guard error == nil,
                  let data = self.pendingPhotoData else {
                self.statusLabel.text = L.string("Unable to capture photo.")
                return
            }
            if self.captureMode == .live,
               let liveURL = self.pendingLivePhotoURL,
               let movieData = try? Data(contentsOf: liveURL) {
                let package = LivePhotoPackage(
                    stillData: data,
                    pairedVideoData: movieData,
                    stillFilename: "Live-\(Int(Date().timeIntervalSince1970)).jpg",
                    pairedVideoFilename: liveURL.lastPathComponent
                )
                try? FileManager.default.removeItem(at: liveURL)
                self.onMedia?(.livePhoto(package, originalName: package.stillFilename))
                return
            }
            if let image = UIImage(data: data) {
                self.onMedia?(.photo(image))
            } else {
                self.statusLabel.text = L.string("Unable to capture photo.")
            }
        }
    }
}

extension VaultCameraViewController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
            self.recordingStartedAt = nil
            self.statusLabel.text = ""
            self.updateButtons()
            guard error == nil else {
                try? FileManager.default.removeItem(at: outputFileURL)
                self.statusLabel.text = L.string("Unable to record video.")
                return
            }
            self.onMedia?(.video(outputFileURL))
        }
    }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    var session: AVCaptureSession? {
        get { videoPreviewLayer.session }
        set { videoPreviewLayer.session = newValue }
    }
}

final class CameraGridOverlayView: UIView {
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.28).cgColor)
        context.setLineWidth(0.75)
        for index in 1...2 {
            let x = rect.width * CGFloat(index) / 3
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: rect.height))
            let y = rect.height * CGFloat(index) / 3
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: rect.width, y: y))
        }
        context.strokePath()
    }
}

struct AudioRecorderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var recorder = VaultAudioRecorder()
    @State private var didAttemptAutoStart = false
    @State private var autoStartTask: Task<Void, Never>?
    var autoStart = false
    let onRecording: (URL, @escaping (Bool) -> Void) -> Void

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 28) {
                HStack {
                    Button(L.string("Close")) { dismiss() }
                        .foregroundStyle(AppTheme.primary)
                    Spacer()
                }

                Spacer()

                VStack(spacing: 20) {
                    ZStack {
                        AudioLevelWaveView(level: recorder.normalizedPower, isActive: recorder.isRecording)
                            .frame(width: 230, height: 230)

                        Circle()
                            .fill(recorder.isRecording ? AppTheme.warning.opacity(0.14) : AppTheme.primary.opacity(0.12))
                            .frame(width: 128, height: 128)

                        Image(systemName: recorder.isRecording ? "waveform" : "mic.fill")
                            .font(.system(size: 54, weight: .semibold))
                            .foregroundStyle(recorder.isRecording ? AppTheme.warning : AppTheme.primary)
                    }

                    Text(recorder.isRecording ? L.string("Recording") : L.string("Ready to Record"))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(AppTheme.ink)

                    Text(recorder.formattedElapsedTime)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit())
                        .foregroundStyle(AppTheme.ink)

                    AudioLevelBar(level: recorder.normalizedPower, isActive: recorder.isRecording)
                        .frame(width: 210)

                    if let errorMessage = recorder.errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.warning)
                            .multilineTextAlignment(.center)
                    }
                }

                Spacer()

                HStack(spacing: 18) {
                    Button {
                        recorder.discard()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.primary)
                            .frame(width: 58, height: 58)
                            .background(AppTheme.primarySoft)
                            .clipShape(Circle())
                    }

                    Button {
                        if recorder.isRecording {
                            if let url = recorder.stop() {
                                onRecording(url) { success in
                                    recorder.finishSaving(success: success)
                                    if success {
                                        dismiss()
                                    }
                                }
                            }
                        } else {
                            recorder.start()
                        }
                    } label: {
                        Image(systemName: recorder.isSaving ? "hourglass" : (recorder.isRecording ? "stop.fill" : "mic.fill"))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 78, height: 78)
                            .background(recorder.isRecording || recorder.isSaving ? AppTheme.dangerFill : AppTheme.primaryFill)
                            .clipShape(Circle())
                    }
                    .disabled(recorder.isSaving)

                    Button {
                        recorder.discard()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppTheme.primary)
                            .frame(width: 58, height: 58)
                            .background(AppTheme.primarySoft)
                            .clipShape(Circle())
                    }
                    .disabled(recorder.isSaving || (!recorder.hasRecording && !recorder.isRecording))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
            }
            .padding(22)
        }
        .onDisappear {
            autoStartTask?.cancel()
            recorder.cancelActiveRecording()
        }
        .onAppear {
            scheduleAutoStartIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            scheduleAutoStartIfNeeded()
        }
        .task {
            scheduleAutoStartIfNeeded()
        }
    }

    private func scheduleAutoStartIfNeeded() {
        guard autoStart,
              scenePhase == .active,
              !didAttemptAutoStart,
              !recorder.isRecording,
              !recorder.hasRecording,
              !recorder.isSaving else {
            return
        }
        didAttemptAutoStart = true
        autoStartTask?.cancel()
        autoStartTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled,
                  !recorder.isRecording,
                  !recorder.hasRecording,
                  !recorder.isSaving else {
                return
            }
            recorder.start()
        }
    }
}

@MainActor
final class VaultAudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published var isRecording = false
    @Published var isSaving = false
    @Published var elapsedTime: TimeInterval = 0
    @Published var normalizedPower: CGFloat = 0
    @Published var errorMessage: String?
    @Published var hasRecording = false

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var recordingURL: URL?

    var formattedElapsedTime: String {
        let total = Int(elapsedTime.rounded(.down))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    func start() {
        errorMessage = nil
        requestRecordPermission { [weak self] granted in
            guard let self else { return }
            if granted {
                self.beginRecording()
            } else {
                self.errorMessage = L.string("Microphone permission is required to record audio.")
            }
        }
    }

    private func requestRecordPermission(completion: @escaping @MainActor (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor in completion(granted) }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                Task { @MainActor in completion(granted) }
            }
        }
    }

    func stop() -> URL? {
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        isSaving = recordingURL != nil
        RecordingLiveActivityController.shared.markSaving(elapsedTime: elapsedTime, level: normalizedPower)
        normalizedPower = 0
        hasRecording = recordingURL != nil
        try? AVAudioSession.sharedInstance().setActive(false)
        return recordingURL
    }

    func finishSaving(success: Bool) {
        isSaving = false
        if success {
            RecordingLiveActivityController.shared.endSaved(elapsedTime: elapsedTime)
        } else {
            RecordingLiveActivityController.shared.endFailed(elapsedTime: elapsedTime)
        }
    }

    func discard() {
        cancelActiveRecording()
        if isSaving {
            RecordingLiveActivityController.shared.endCancelled()
        }
        if let recordingURL {
            try? FileManager.default.removeItem(at: recordingURL)
        }
        recordingURL = nil
        elapsedTime = 0
        normalizedPower = 0
        isSaving = false
        hasRecording = false
        errorMessage = nil
    }

    func cancelActiveRecording() {
        guard isRecording else { return }
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        normalizedPower = 0
        try? AVAudioSession.sharedInstance().setActive(false)
        RecordingLiveActivityController.shared.endCancelled()
    }

    private func beginRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(Self.recordingFileName(for: Date()))
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder.delegate = self
            audioRecorder.isMeteringEnabled = true
            audioRecorder.record()

            recorder = audioRecorder
            recordingURL = url
            elapsedTime = 0
            normalizedPower = 0
            hasRecording = false
            isRecording = true
            RecordingLiveActivityController.shared.start()
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { _ in
                Task { @MainActor [weak self] in
                    self?.updateRecordingMeters()
                }
            }
        } catch {
            errorMessage = L.string("Unable to start audio recording.")
            isRecording = false
        }
    }

    private static func recordingFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "Recording-\(formatter.string(from: date)).m4a"
    }

    private func updateRecordingMeters() {
        guard let recorder else {
            elapsedTime = 0
            normalizedPower = 0
            return
        }
        recorder.updateMeters()
        elapsedTime = recorder.currentTime
        let averagePower = recorder.averagePower(forChannel: 0)
        let clampedPower = min(max(averagePower, -55), 0)
        normalizedPower = CGFloat(pow(10, clampedPower / 35))
        RecordingLiveActivityController.shared.update(elapsedTime: elapsedTime, level: normalizedPower)
    }
}

private struct AudioLevelWaveView: View {
    let level: CGFloat
    let isActive: Bool

    private var activeLevel: CGFloat {
        isActive ? max(level, 0.04) : 0
    }

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                let progress = CGFloat(index) / 3
                Circle()
                    .stroke(ringColor(for: progress), lineWidth: ringLineWidth(for: progress))
                    .scaleEffect(ringScale(for: progress))
                    .opacity(ringOpacity(for: progress))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
        .animation(.easeInOut(duration: 0.2), value: isActive)
    }

    private func ringColor(for progress: CGFloat) -> Color {
        AppTheme.warning.opacity(isActive ? Double(0.42 - progress * 0.18) : 0.12)
    }

    private func ringLineWidth(for progress: CGFloat) -> CGFloat {
        max(1.5, 6 - progress * 3)
    }

    private func ringScale(for progress: CGFloat) -> CGFloat {
        0.5 + progress * 0.22 + activeLevel * (0.42 + progress * 0.28)
    }

    private func ringOpacity(for progress: CGFloat) -> Double {
        isActive ? max(0.16, Double(activeLevel) + 0.18 - Double(progress) * 0.1) : 0.28
    }
}

private struct AudioLevelBar: View {
    let level: CGFloat
    let isActive: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<18, id: \.self) { index in
                let distance = abs(CGFloat(index) - 8.5) / 8.5
                let baseHeight = CGFloat(8) + (1 - distance) * 18
                let activeHeight = baseHeight + level * (42 - distance * 18)
                Capsule()
                    .fill(isActive ? AppTheme.warning : AppTheme.primary.opacity(0.35))
                    .frame(width: 6, height: isActive ? activeHeight : baseHeight)
            }
        }
        .frame(height: 58)
        .animation(.easeOut(duration: 0.08), value: level)
        .animation(.easeInOut(duration: 0.18), value: isActive)
    }
}

#if canImport(VisionKit)
struct DocumentScannerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImages: ([UIImage]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView

        init(parent: DocumentScannerView) {
            self.parent = parent
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.onImages(images)
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.dismiss()
        }
    }
}
#endif
