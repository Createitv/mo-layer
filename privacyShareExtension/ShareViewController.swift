import UIKit
import Photos
import PhotosUI
import UniformTypeIdentifiers

@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private let appGroupIdentifier = "group.app.landlady.www.privacy"
    private let sharedInboxDirectoryName = "SharedImports"
    private let sharedImportManifestName = "pending-imports.json"
    private var stagedItems: [SharedImportManifestItem] = []

    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let fileListLabel = UILabel()
    private let saveButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private var didRequestHostOpen = false

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        stageSharedItems()
    }

    private func configureView() {
        view.backgroundColor = .systemBackground

        titleLabel.text = "保存到 Palimpsest"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        statusLabel.text = "正在读取分享的文件..."
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        fileListLabel.font = .preferredFont(forTextStyle: .footnote)
        fileListLabel.textColor = .secondaryLabel
        fileListLabel.numberOfLines = 6
        fileListLabel.textAlignment = .center

        var saveConfiguration = UIButton.Configuration.filled()
        saveConfiguration.title = "保存到保险箱"
        saveConfiguration.baseBackgroundColor = .systemTeal
        saveConfiguration.baseForegroundColor = .white
        saveConfiguration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        saveButton.configuration = saveConfiguration
        saveButton.layer.cornerRadius = 10
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        saveButton.isHidden = true

        cancelButton.setTitle("取消", for: .normal)
        cancelButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.isHidden = true

        let stack = UIStackView(arrangedSubviews: [titleLabel, statusLabel, fileListLabel, saveButton, cancelButton])
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func stageSharedItems() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem],
              let directory = sharedInboxDirectory() else {
            showUnsupportedState()
            return
        }

        let providers = items.flatMap { $0.attachments ?? [] }
        guard !providers.isEmpty else {
            showUnsupportedState()
            return
        }

        let group = DispatchGroup()
        var staged: [SharedImportManifestItem] = []
        let lock = NSLock()

        for provider in providers {
            if provider.canLoadObject(ofClass: PHLivePhoto.self) {
                group.enter()
                provider.loadObject(ofClass: PHLivePhoto.self) { [weak self] object, _ in
                    defer { group.leave() }
                    guard let self, let livePhoto = object as? PHLivePhoto else { return }
                    guard let item = self.copySharedLivePhoto(livePhoto, to: directory) else { return }
                    lock.lock()
                    staged.append(item)
                    lock.unlock()
                }
                continue
            }

            guard let typeIdentifier = preferredFileTypeIdentifier(from: provider) else {
                continue
            }
            group.enter()
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, _ in
                defer { group.leave() }
                guard let self, let url else { return }
                guard let item = self.copySharedFile(
                    from: url,
                    suggestedName: provider.suggestedName,
                    typeIdentifier: typeIdentifier,
                    to: directory
                ) else {
                    return
                }
                lock.lock()
                staged.append(item)
                lock.unlock()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.stagedItems = staged.sorted { $0.createdAt < $1.createdAt }
            if self.stagedItems.isEmpty {
                self.showUnsupportedState()
                return
            }
            self.writeManifest(directory: directory)
            self.showReadyState()
            self.openHostAppAfterStaging()
        }
    }

    private func preferredFileTypeIdentifier(from provider: NSItemProvider) -> String? {
        let identifiers = provider.registeredTypeIdentifiers
        let types = identifiers.compactMap { UTType($0) }
        if types.allSatisfy({ $0.conforms(to: .url) || $0.conforms(to: .text) }) {
            return nil
        }

        let preferredTypes: [UTType] = [
            .image,
            .movie,
            .audio,
            .pdf,
            .archive,
            .content,
            .data,
            .item
        ]

        for preferredType in preferredTypes {
            if let identifier = identifiers.first(where: { UTType($0)?.conforms(to: preferredType) == true }) {
                return identifier
            }
        }
        return identifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return !type.conforms(to: .url) && !type.conforms(to: .text)
        }
    }

    private func copySharedFile(
        from source: URL,
        suggestedName: String?,
        typeIdentifier: String,
        to directory: URL
    ) -> SharedImportManifestItem? {
        let originalName = cleanFileName(suggestedName ?? source.lastPathComponent)
        let storedFileName = "\(UUID().uuidString)-\(originalName)"
        let destination = directory.appendingPathComponent(storedFileName)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
            let values = try? destination.resourceValues(forKeys: [.fileSizeKey])
            let type = UTType(typeIdentifier) ?? UTType(filenameExtension: destination.pathExtension) ?? .data
            return SharedImportManifestItem(
                id: UUID().uuidString,
                originalName: originalName,
                storedFileName: storedFileName,
                typeIdentifier: type.identifier,
                mimeType: type.preferredMIMEType ?? "application/octet-stream",
                byteSize: Int64(values?.fileSize ?? 0),
                createdAt: Date()
            )
        } catch {
            return nil
        }
    }

    private func copySharedLivePhoto(_ livePhoto: PHLivePhoto, to directory: URL) -> SharedImportManifestItem? {
        let resources = PHAssetResource.assetResources(for: livePhoto)
        guard let photoResource = resources.first(where: { $0.type == .photo || $0.type == .fullSizePhoto }),
              let pairedVideoResource = resources.first(where: { $0.type == .pairedVideo }),
              let stillData = resourceData(for: photoResource),
              let pairedVideoData = resourceData(for: pairedVideoResource) else {
            return nil
        }

        let originalName = cleanFileName(photoResource.originalFilename)
        let storedFileName = "\(UUID().uuidString)-\(originalName).livephoto"
        let destination = directory.appendingPathComponent(storedFileName)
        let package = ExtensionLivePhotoPackage(
            stillData: stillData,
            pairedVideoData: pairedVideoData,
            stillFilename: photoResource.originalFilename,
            pairedVideoFilename: pairedVideoResource.originalFilename
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary

        do {
            let data = try encoder.encode(package)
            try? FileManager.default.removeItem(at: destination)
            try data.write(to: destination, options: .atomic)
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: destination.path)
            return SharedImportManifestItem(
                id: UUID().uuidString,
                originalName: originalName,
                storedFileName: storedFileName,
                typeIdentifier: "app.landlady.www.privacy.live-photo",
                mimeType: "application/vnd.apple.live-photo",
                byteSize: Int64(data.count),
                createdAt: Date()
            )
        } catch {
            return nil
        }
    }

    private func resourceData(for resource: PHAssetResource) -> Data? {
        let fileExtension = (resource.originalFilename as NSString).pathExtension
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension.isEmpty ? "dat" : fileExtension)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        let semaphore = DispatchSemaphore(value: 0)
        var outputData: Data?
        PHAssetResourceManager.default().writeData(for: resource, toFile: temporaryURL, options: options) { _ in
            outputData = try? Data(contentsOf: temporaryURL)
            try? FileManager.default.removeItem(at: temporaryURL)
            semaphore.signal()
        }
        semaphore.wait()
        return outputData
    }

    private func cleanFileName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "\(UUID().uuidString).dat" }
        let invalidCharacters = CharacterSet(charactersIn: "/:")
        return trimmed
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
    }

    private func showReadyState() {
        statusLabel.text = "已接收 \(stagedItems.count) 个文件，正在打开 App..."
        fileListLabel.text = stagedItems
            .prefix(5)
            .map { "• \($0.originalName)" }
            .joined(separator: "\n")
        saveButton.configuration?.title = "打开 App 保存"
        saveButton.isHidden = true
        cancelButton.isHidden = false
    }

    private func showUnsupportedState() {
        statusLabel.text = "没有可保存的文件。当前只支持文件、图片、视频、音频和文档。"
        fileListLabel.text = nil
        saveButton.isHidden = true
        cancelButton.isHidden = false
    }

    private func sharedInboxDirectory() -> URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return nil
        }
        let directory = base.appendingPathComponent(sharedInboxDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeManifest(directory: URL) {
        var existingItems = readManifest(directory: directory)?.items ?? []
        existingItems.append(contentsOf: stagedItems)
        let manifest = SharedImportManifest(items: existingItems)
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        let url = directory.appendingPathComponent(sharedImportManifestName)
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
    }

    private func readManifest(directory: URL) -> SharedImportManifest? {
        let url = directory.appendingPathComponent(sharedImportManifestName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SharedImportManifest.self, from: data)
    }

    private func removeStagedItems() {
        guard let directory = sharedInboxDirectory() else { return }
        for item in stagedItems {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(item.storedFileName))
        }
        let stagedIds = Set(stagedItems.map(\.id))
        let remainingItems = readManifest(directory: directory)?.items.filter { !stagedIds.contains($0.id) } ?? []
        let manifestURL = directory.appendingPathComponent(sharedImportManifestName)
        guard !remainingItems.isEmpty else {
            try? FileManager.default.removeItem(at: manifestURL)
            return
        }
        let manifest = SharedImportManifest(items: remainingItems)
        if let data = try? JSONEncoder().encode(manifest) {
            try? data.write(to: manifestURL, options: .atomic)
        }
    }

    @objc private func saveTapped() {
        openHostAppAfterStaging()
    }

    private func openHostAppAfterStaging() {
        guard !didRequestHostOpen else { return }
        guard let url = URL(string: "privacy://shared-imports") else {
            complete()
            return
        }

        didRequestHostOpen = true
        statusLabel.text = "已接收 \(stagedItems.count) 个文件，正在打开 Palimpsest..."
        openHostApp(url) { [weak self] didOpen in
            guard let self else { return }
            if didOpen {
                self.complete()
            } else {
                self.didRequestHostOpen = false
                self.statusLabel.text = "已接收 \(self.stagedItems.count) 个文件。如果没有自动打开，请点下方按钮进入 App 保存。"
                self.saveButton.isHidden = false
                self.cancelButton.isHidden = false
            }
        }
    }

    private func openHostApp(_ url: URL, completion: @escaping (Bool) -> Void) {
        extensionContext?.open(url) { [weak self] didOpen in
            guard let self else {
                completion(didOpen)
                return
            }
            if didOpen {
                completion(true)
            } else {
                completion(self.openURLThroughResponderChain(url))
            }
        }
    }

    private func openURLThroughResponderChain(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self
        while let currentResponder = responder {
            if currentResponder.responds(to: selector) {
                _ = currentResponder.perform(selector, with: url)
                return true
            }
            responder = currentResponder.next
        }
        return false
    }

    @objc private func cancelTapped() {
        removeStagedItems()
        complete()
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

private struct SharedImportManifest: Codable {
    var items: [SharedImportManifestItem]
}

private struct SharedImportManifestItem: Codable {
    var id: String
    var originalName: String
    var storedFileName: String
    var typeIdentifier: String
    var mimeType: String
    var byteSize: Int64
    var createdAt: Date
}

private struct ExtensionLivePhotoPackage: Codable {
    var stillData: Data
    var pairedVideoData: Data
    var stillFilename: String
    var pairedVideoFilename: String
}
