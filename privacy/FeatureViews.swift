import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
#if canImport(VisionKit)
import VisionKit
#endif

struct ImportHubView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var vaultStore: VaultStore
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var showCamera = false
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Encrypt Immediately After Import")
                                .font(.title3.bold())
                                .foregroundStyle(AppTheme.ink)
                            Text("Photos, videos, and files are encrypted on this device before optional iCloud sync. Delete originals from Photos when appropriate.")
                                .foregroundStyle(AppTheme.secondaryText)
                        }
                    }

                    PhotosPicker(selection: $pickerItems, matching: .any(of: [.images, .videos])) {
                        ActionRow(icon: "photo.on.rectangle", title: L.string("Import from Photos"), subtitle: L.string("Photos and videos"))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showFileImporter = true
                    } label: {
                        ActionRow(icon: "folder", title: L.string("Import from Files"), subtitle: L.string("PDFs, documents, and archives"))
                    }
                    .buttonStyle(.plain)

                    Button {
                        showCamera = true
                    } label: {
                        ActionRow(icon: "camera", title: L.string("Capture to Vault"), subtitle: L.string("Save directly to the encrypted vault"))
                    }
                    .buttonStyle(.plain)
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                    Button {
                        showScanner = true
                    } label: {
                        ActionRow(icon: "doc.viewfinder", title: L.string("Scan Document"), subtitle: L.string("IDs, contracts, and receipts as encrypted images"))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isDocumentScannerAvailable)
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle("Import")
            .onChange(of: pickerItems) { _, newItems in
                Task {
                    await ImportService.importPickerItems(newItems, context: modelContext, vaultStore: vaultStore, sync: sync)
                    pickerItems = []
                }
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    Task {
                        for url in urls {
                            await ImportService.importFile(url: url, context: modelContext, vaultStore: vaultStore, sync: sync)
                        }
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraCaptureView { image in
                    guard let data = image.jpegData(compressionQuality: 0.9) else { return }
                    Task {
                        await vaultStore.importData(
                            data,
                            originalName: "Camera-\(Date().timeIntervalSince1970).jpg",
                            mimeType: "image/jpeg",
                            source: "Camera",
                            kind: .image,
                            context: modelContext,
                            sync: sync
                        )
                    }
                }
            }
            .sheet(isPresented: $showScanner) { scannerSheet }
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
            Task {
                for (index, image) in images.enumerated() {
                    guard let data = image.jpegData(compressionQuality: 0.9) else { continue }
                    await vaultStore.importData(
                        data,
                        originalName: "Scan-\(Date().timeIntervalSince1970)-\(index + 1).jpg",
                        mimeType: "image/jpeg",
                        source: "Scanner",
                        kind: .image,
                        context: modelContext,
                        sync: sync
                    )
                }
            }
        }
        #else
        EmptyView()
        #endif
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
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var vaultStore: VaultStore
    @State private var isBackingUp = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    AppCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Security Status")
                                    .font(.title3.bold())
                                Spacer()
                                StatusPill(title: L.string("Encrypted"), systemImage: "lock.shield")
                            }
                            Text("Recovery Key")
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryText)
                            Text(VaultCryptoService.currentRecoveryKey())
                                .font(.system(.callout, design: .monospaced, weight: .semibold))
                                .textSelection(.enabled)
                                .foregroundStyle(AppTheme.ink)
                        }
                    }

                    SecurityRow(icon: "scribble.variable", title: L.string("Gesture Unlock"), detail: L.string("Verified from the on-device gesture template. Never uploaded to a server."), status: auth.isGestureUnlockEnabled ? L.string("Enabled") : L.string("Not Set"))
                    SecurityRow(icon: "icloud", title: L.string("CloudKit Encrypted Sync"), detail: sync.state.detail, status: sync.state.title)
                    SecurityRow(icon: "eye.slash", title: L.string("Background Shield"), detail: L.string("Locks and clears temporary files when the app leaves the foreground."), status: L.string("On"))
                    SecurityRow(icon: "rectangle.on.rectangle.slash", title: L.string("Screenshot/Recording Detection"), detail: L.string("Logs security events. iOS screenshots cannot be fully blocked."), status: L.string("On"))
                    SecurityRow(icon: "theatermasks", title: L.string("Decoy Vault"), detail: L.string("Reserved entry for a realistic decoy space."), status: L.string("Not Configured"))
                    SecurityRow(icon: "camera.viewfinder", title: L.string("Intrusion Capture"), detail: L.string("Camera permission is requested only after you enable it."), status: L.string("Off"))

                    AppCard {
                        LanguageSettingsContent()
                    }

                    Button {
                        Task { await sync.checkAccountStatus() }
                    } label: {
                        Label("Recheck iCloud", systemImage: "arrow.clockwise.icloud")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    Button {
                        Task {
                            isBackingUp = true
                            await vaultStore.backupAllFilesToCloud(context: modelContext, sync: sync)
                            isBackingUp = false
                        }
                    } label: {
                        Label(isBackingUp ? L.string("Backing Up All Files") : L.string("Back Up All Files to iCloud"), systemImage: "icloud.and.arrow.up")
                    }
                    .buttonStyle(AppButtonStyle())
                    .disabled(isBackingUp)
                }
                .padding()
            }
            .background(AppTheme.background)
            .navigationTitle("Security Center")
        }
    }
}

private struct LanguageSettingsContent: View {
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.english.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Language")
                .font(.headline)
                .foregroundStyle(AppTheme.ink)
            Picker("App Language", selection: $language) {
                ForEach(AppLanguage.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .pickerStyle(.menu)
            Text("Default follows your iPhone language and region. Choose a language here to override it inside the app.")
                .font(.caption)
                .foregroundStyle(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

struct CameraCaptureView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraCaptureView

        init(parent: CameraCaptureView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
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
