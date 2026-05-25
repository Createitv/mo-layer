import UIKit
import UniformTypeIdentifiers

@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private let appGroupIdentifier = "group.app.landlady.www.privacy"
    private let sharedInboxDirectoryName = "SharedImports"
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        importSharedItems()
    }

    private func configureView() {
        view.backgroundColor = .systemBackground
        statusLabel.text = "正在导入到隐盾云盘..."
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func importSharedItems() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            complete()
            return
        }

        let providers = items.flatMap { $0.attachments ?? [] }
        guard !providers.isEmpty, let directory = sharedInboxDirectory() else {
            complete()
            return
        }

        let group = DispatchGroup()
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                    defer { group.leave() }
                    self?.saveURLItem(item, to: directory)
                }
            } else {
                let typeIdentifier = preferredTypeIdentifier(from: provider)
                group.enter()
                provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] url, _ in
                    defer { group.leave() }
                    guard let self, let url else { return }
                    self.copySharedFile(from: url, to: directory)
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.complete()
        }
    }

    private func preferredTypeIdentifier(from provider: NSItemProvider) -> String {
        let identifiers = provider.registeredTypeIdentifiers
        return identifiers.first { $0 != UTType.url.identifier } ?? UTType.item.identifier
    }

    private func saveURLItem(_ item: NSSecureCoding?, to directory: URL) {
        let url: URL?
        if let value = item as? URL {
            url = value
        } else if let value = item as? String {
            url = URL(string: value)
        } else {
            url = nil
        }
        guard let url else { return }

        let destination = directory.appendingPathComponent("\(UUID().uuidString).urlimport")
        try? url.absoluteString.write(to: destination, atomically: true, encoding: .utf8)
    }

    private func copySharedFile(from source: URL, to directory: URL) {
        let fileName = source.lastPathComponent.isEmpty ? "\(UUID().uuidString).dat" : source.lastPathComponent
        let destination = directory.appendingPathComponent("\(UUID().uuidString)-\(fileName)")
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.copyItem(at: source, to: destination)
    }

    private func sharedInboxDirectory() -> URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            return nil
        }
        let directory = base.appendingPathComponent(sharedInboxDirectoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func complete() {
        statusLabel.text = "已加入导入队列"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
