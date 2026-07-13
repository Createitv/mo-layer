import UIKit
import AVFoundation
import Photos
import PhotosUI
import UniformTypeIdentifiers

@objc(ShareViewController)
final class ShareViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private let appGroupIdentifier = "group.app.landlady.www.privacy"
    private let sharedInboxDirectoryName = "SharedImports"
    private let sharedImportManifestName = "pending-imports.json"
    private let batchId = UUID().uuidString
    private var stagedItems: [SharedImportManifestItem] = []
    private var selectedItemIds = Set<String>()
    private var thumbnailCache: [String: UIImage] = [:]

    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let saveButton = UIButton(type: .system)
    private let innerVaultButton = UIButton(type: .system)
    private let openAppButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeCollectionLayout())
    private var didRequestHostOpen = false
    private var openFallbackWorkItem: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        stageSharedItems()
    }

    private func configureView() {
        view.backgroundColor = .systemBackground

        titleLabel.text = "保存到 墨层"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        statusLabel.text = "正在读取分享的文件..."
        statusLabel.font = .preferredFont(forTextStyle: .body)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.allowsMultipleSelection = true
        collectionView.register(SharedImportCell.self, forCellWithReuseIdentifier: SharedImportCell.reuseIdentifier)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.isHidden = true

        saveButton.configuration = primaryButtonConfiguration(title: "保存到普通目录", color: .systemTeal)
        saveButton.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        saveButton.isHidden = true

        innerVaultButton.configuration = primaryButtonConfiguration(title: "保存到墨层目录", color: .systemIndigo)
        innerVaultButton.addTarget(self, action: #selector(saveToInnerVaultTapped), for: .touchUpInside)
        innerVaultButton.isHidden = true

        openAppButton.setTitle("进入墨层 App", for: .normal)
        openAppButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        openAppButton.addTarget(self, action: #selector(openAppTapped), for: .touchUpInside)
        openAppButton.isHidden = true

        cancelButton.setTitle("取消", for: .normal)
        cancelButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancelButton.isHidden = true

        let stack = UIStackView(arrangedSubviews: [titleLabel, statusLabel, collectionView, saveButton, innerVaultButton, openAppButton, cancelButton])
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -28),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            collectionView.heightAnchor.constraint(equalToConstant: 260)
        ])
    }

    private func makeCollectionLayout() -> UICollectionViewFlowLayout {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 10
        return layout
    }

    private func primaryButtonConfiguration(title: String, color: UIColor) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.baseBackgroundColor = color
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
        return configuration
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
            if UTType(typeIdentifier)?.conforms(to: .fileURL) == true {
                provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { [weak self] item, _ in
                    defer { group.leave() }
                    guard let self,
                          let url = self.fileURL(from: item),
                          let manifestItem = self.copySharedFile(
                            from: url,
                            suggestedName: provider.suggestedName,
                            typeIdentifier: UTType(filenameExtension: url.pathExtension)?.identifier ?? typeIdentifier,
                            to: directory
                          ) else {
                        return
                    }
                    lock.lock()
                    staged.append(manifestItem)
                    lock.unlock()
                }
            } else {
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
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            self.stagedItems = staged.sorted { $0.createdAt < $1.createdAt }
            if self.stagedItems.isEmpty {
                self.showUnsupportedState()
                return
            }
            self.selectedItemIds = Set(self.stagedItems.map(\.id))
            self.showReadyState()
        }
    }

    private func preferredFileTypeIdentifier(from provider: NSItemProvider) -> String? {
        let identifiers = provider.registeredTypeIdentifiers
        let types = identifiers.compactMap { UTType($0) }
        if types.allSatisfy({ type in
            (type.conforms(to: .url) && !type.conforms(to: .fileURL)) || type.conforms(to: .text)
        }) {
            return nil
        }

        let preferredTypes: [UTType] = [
            .image,
            .movie,
            .audio,
            .pdf,
            .archive,
            .fileURL,
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
            return (!type.conforms(to: .url) || type.conforms(to: .fileURL)) && !type.conforms(to: .text)
        }
    }

    private func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL, url.isFileURL {
            return url
        }
        if let data = item as? Data,
           let url = URL(dataRepresentation: data, relativeTo: nil),
           url.isFileURL {
            return url
        }
        return nil
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
                batchId: batchId,
                originalName: originalName,
                storedFileName: storedFileName,
                typeIdentifier: type.identifier,
                mimeType: type.preferredMIMEType ?? "application/octet-stream",
                byteSize: Int64(values?.fileSize ?? 0),
                createdAt: Date(),
                destinationRawValue: nil
            )
        } catch {
            return nil
        }
    }

    private func fileURL(for item: SharedImportManifestItem) -> URL? {
        sharedInboxDirectory()?.appendingPathComponent(item.storedFileName)
    }

    private func thumbnail(for item: SharedImportManifestItem) -> UIImage {
        if let cached = thumbnailCache[item.id] {
            return cached
        }

        let type = UTType(item.typeIdentifier) ?? .data
        let image: UIImage
        if type.conforms(to: .image), let url = fileURL(for: item), let loadedImage = imageThumbnail(from: url) {
            image = loadedImage
        } else if type.conforms(to: .movie), let url = fileURL(for: item), let videoImage = videoThumbnail(from: url) {
            image = videoImage
        } else {
            image = placeholderThumbnail(for: type)
        }

        thumbnailCache[item.id] = image
        return image
    }

    private func imageThumbnail(from url: URL) -> UIImage? {
        if let image = UIImage(contentsOfFile: url.path) {
            return image
        }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return UIImage(data: data)
    }

    private func videoThumbnail(from url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 360)
        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private func placeholderThumbnail(for type: UTType) -> UIImage {
        let symbolName: String
        if type.conforms(to: .audio) {
            symbolName = "waveform"
        } else if type.conforms(to: .pdf) {
            symbolName = "doc.richtext"
        } else {
            symbolName = "doc"
        }
        return UIImage(systemName: symbolName) ?? UIImage()
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
                batchId: batchId,
                originalName: originalName,
                storedFileName: storedFileName,
                typeIdentifier: "app.landlady.www.privacy.live-photo",
                mimeType: "application/vnd.apple.live-photo",
                byteSize: Int64(data.count),
                createdAt: Date(),
                destinationRawValue: nil
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
        updateSelectionStatus()
        collectionView.isHidden = false
        view.layoutIfNeeded()
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.reloadData()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.collectionView.collectionViewLayout.invalidateLayout()
            self.collectionView.reloadData()
            self.selectVisibleItems()
        }
        saveButton.isHidden = false
        innerVaultButton.isHidden = false
        openAppButton.isHidden = false
        cancelButton.isHidden = false
    }

    private func showUnsupportedState() {
        statusLabel.text = "没有可保存的文件。当前只支持文件、图片、视频、音频和文档。"
        collectionView.isHidden = true
        saveButton.isHidden = true
        innerVaultButton.isHidden = true
        openAppButton.isHidden = true
        cancelButton.isHidden = false
    }

    private func updateSelectionStatus() {
        statusLabel.text = "已接收 \(stagedItems.count) 个文件，已选择 \(selectedItemIds.count) 个。请选择保存位置，打开 App 后确认即可保存。"
        let hasSelection = !selectedItemIds.isEmpty
        saveButton.isEnabled = hasSelection
        innerVaultButton.isEnabled = hasSelection
    }

    private func selectVisibleItems() {
        for (index, item) in stagedItems.enumerated() where selectedItemIds.contains(item.id) {
            collectionView.selectItem(at: IndexPath(item: index, section: 0), animated: false, scrollPosition: [])
        }
    }

    private func sharedInboxDirectory() -> URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return nil
        }
        let directory = base.appendingPathComponent(sharedInboxDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeManifest(directory: URL, destination: SharedImportDestination) {
        let selectedItems = stagedItems.filter { selectedItemIds.contains($0.id) }.map { item in
            var updatedItem = item
            updatedItem.destinationRawValue = destination.rawValue
            return updatedItem
        }
        let skippedItems = stagedItems.filter { !selectedItemIds.contains($0.id) }
        for item in skippedItems {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(item.storedFileName))
        }
        stagedItems = selectedItems
        let selectedIds = Set(selectedItems.map(\.id))
        var existingItems = readManifest(directory: directory)?.items.filter { !selectedIds.contains($0.id) } ?? []
        existingItems.append(contentsOf: selectedItems)
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
        guard !selectedItemIds.isEmpty else { return }
        openHostAppAfterStaging(destination: .regular)
    }

    @objc private func saveToInnerVaultTapped() {
        guard !selectedItemIds.isEmpty else { return }
        openHostAppAfterStaging(destination: .innerVault)
    }

    @objc private func openAppTapped() {
        guard let url = URL(string: "molayer://open-app") else {
            complete()
            return
        }
        didRequestHostOpen = true
        statusLabel.text = "正在打开 墨层..."
        runOpenFallback(message: "如果没有自动打开，请从桌面进入墨层 App。")
        openHostApp(url) { [weak self] didOpen in
            self?.openFallbackWorkItem?.cancel()
            self?.openFallbackWorkItem = nil
            if didOpen {
                self?.complete()
            }
        }
    }

    private func openHostAppAfterStaging(destination: SharedImportDestination) {
        guard !didRequestHostOpen else { return }
        guard let directory = sharedInboxDirectory() else {
            showUnsupportedState()
            return
        }
        writeManifest(directory: directory, destination: destination)
        guard let url = URL(string: "molayer://shared-imports?batch=\(batchId)&destination=\(destination.rawValue)") else {
            complete()
            return
        }

        didRequestHostOpen = true
        saveButton.isHidden = true
        innerVaultButton.isHidden = true
        openAppButton.isHidden = true
        statusLabel.text = "已选择\(destination.displayName)，正在打开 墨层..."
        runOpenFallback(message: "已接收 \(stagedItems.count) 个文件。如果没有自动打开，请重新选择保存位置。")
        openHostApp(url) { [weak self] didOpen in
            guard let self else { return }
            self.openFallbackWorkItem?.cancel()
            self.openFallbackWorkItem = nil
            if didOpen {
                self.complete()
            } else {
                self.didRequestHostOpen = false
                self.statusLabel.text = "已接收 \(self.stagedItems.count) 个文件。如果没有自动打开，请重新选择保存位置。"
                self.saveButton.isHidden = false
                self.innerVaultButton.isHidden = false
                self.openAppButton.isHidden = false
                self.cancelButton.isHidden = false
            }
        }
    }

    private func runOpenFallback(message: String) {
        openFallbackWorkItem?.cancel()
        let fallback = DispatchWorkItem { [weak self] in
            guard let self, self.didRequestHostOpen else { return }
            self.didRequestHostOpen = false
            self.statusLabel.text = message
            self.saveButton.isHidden = false
            self.innerVaultButton.isHidden = false
            self.openAppButton.isHidden = false
            self.cancelButton.isHidden = false
        }
        openFallbackWorkItem = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: fallback)
    }

    private func openHostApp(_ url: URL, completion: @escaping (Bool) -> Void) {
        if openURLThroughResponderChain(url, completion: completion) {
            return
        }
        extensionContext?.open(url) { [weak self] didOpen in
            guard let self else {
                completion(didOpen)
                return
            }
            if didOpen {
                completion(true)
            } else {
                if !self.openURLThroughResponderChain(url, completion: completion) {
                    completion(false)
                }
            }
        }
    }

    private func openURLThroughResponderChain(_ url: URL, completion: @escaping (Bool) -> Void) -> Bool {
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self
        while let currentResponder = responder {
            if let application = currentResponder as? UIApplication {
                if #available(iOS 18.0, *) {
                    application.open(url, options: [:], completionHandler: completion)
                    return true
                }
                if application.responds(to: selector) {
                    _ = application.perform(selector, with: url)
                    completion(true)
                    return true
                }
            } else if currentResponder.responds(to: selector) {
                _ = currentResponder.perform(selector, with: url)
                completion(true)
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

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        stagedItems.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: SharedImportCell.reuseIdentifier,
            for: indexPath
        ) as? SharedImportCell else {
            return UICollectionViewCell()
        }
        let item = stagedItems[indexPath.item]
        cell.configure(
            image: thumbnail(for: item),
            title: item.originalName,
            isSelected: selectedItemIds.contains(item.id)
        )
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        selectedItemIds.insert(stagedItems[indexPath.item].id)
        updateSelectionStatus()
        if let cell = collectionView.cellForItem(at: indexPath) as? SharedImportCell {
            cell.setChecked(true)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        selectedItemIds.remove(stagedItems[indexPath.item].id)
        updateSelectionStatus()
        if let cell = collectionView.cellForItem(at: indexPath) as? SharedImportCell {
            cell.setChecked(false)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        let columns: CGFloat = view.bounds.width > 430 ? 4 : 3
        let spacing = (columns - 1) * 8
        let availableWidth = max(collectionView.bounds.width, view.bounds.width - 48, 280)
        let width = max(72, floor((availableWidth - spacing) / columns))
        return CGSize(width: width, height: width + 26)
    }
}

private final class SharedImportCell: UICollectionViewCell {
    static let reuseIdentifier = "SharedImportCell"

    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let checkmarkView = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 8
        contentView.layer.masksToBounds = true

        imageView.contentMode = .scaleAspectFill
        imageView.tintColor = .secondaryLabel
        imageView.backgroundColor = .secondarySystemBackground
        imageView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .preferredFont(forTextStyle: .caption2)
        titleLabel.textColor = .secondaryLabel
        titleLabel.textAlignment = .center
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        checkmarkView.tintColor = .systemBlue
        checkmarkView.backgroundColor = .systemBackground
        checkmarkView.layer.cornerRadius = 10
        checkmarkView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(imageView)
        contentView.addSubview(titleLabel)
        contentView.addSubview(checkmarkView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),
            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 4),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
            checkmarkView.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 6),
            checkmarkView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -6),
            checkmarkView.widthAnchor.constraint(equalToConstant: 20),
            checkmarkView.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        titleLabel.text = nil
        setChecked(false)
    }

    func configure(image: UIImage, title: String, isSelected: Bool) {
        imageView.image = image
        titleLabel.text = title
        setChecked(isSelected)
    }

    func setChecked(_ checked: Bool) {
        checkmarkView.isHidden = !checked
        imageView.alpha = checked ? 1.0 : 0.45
    }
}

private struct SharedImportManifest: Codable {
    var items: [SharedImportManifestItem]
}

private struct SharedImportManifestItem: Codable {
    var id: String
    var batchId: String?
    var originalName: String
    var storedFileName: String
    var typeIdentifier: String
    var mimeType: String
    var byteSize: Int64
    var createdAt: Date
    var destinationRawValue: String?
}

private enum SharedImportDestination: String {
    case regular
    case innerVault

    var displayName: String {
        switch self {
        case .regular:
            "普通目录"
        case .innerVault:
            "墨层目录"
        }
    }
}

private struct ExtensionLivePhotoPackage: Codable {
    var stillData: Data
    var pairedVideoData: Data
    var stillFilename: String
    var pairedVideoFilename: String
}
