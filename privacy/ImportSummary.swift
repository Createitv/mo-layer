import Foundation

struct ImportSummary: Identifiable, Equatable {
    let id = UUID()
    private(set) var importedByKind: [VaultItemKind: Int] = [:]
    private(set) var failedCount = 0

    var importedCount: Int {
        importedByKind.values.reduce(0, +)
    }

    var displayTitle: String {
        L.string("Import Complete")
    }

    var displayMessage: String {
        let importedText = orderedKindParts.joined(separator: ", ")
        if failedCount > 0 {
            return L.format("%@ imported. %d failed.", importedText, failedCount)
        }
        return L.format("%@ imported.", importedText)
    }

    mutating func record(_ kind: VaultItemKind) {
        importedByKind[kind, default: 0] += 1
    }

    mutating func recordFailure() {
        failedCount += 1
    }

    mutating func merge(_ other: ImportSummary) {
        for (kind, count) in other.importedByKind {
            importedByKind[kind, default: 0] += count
        }
        failedCount += other.failedCount
    }

    private var orderedKindParts: [String] {
        VaultItemKind.allCases.compactMap { kind in
            guard let count = importedByKind[kind], count > 0 else { return nil }
            return "\(count) \(kind.importSummaryName(count: count))"
        }
    }
}

private extension VaultItemKind {
    func importSummaryName(count: Int) -> String {
        switch self {
        case .image: L.string(count == 1 ? "Image" : "Images")
        case .livePhoto: L.string(count == 1 ? "Live Photo" : "Live Photos")
        case .video: L.string(count == 1 ? "Video" : "Videos")
        case .audio: L.string("Audio")
        case .document: L.string(count == 1 ? "Document" : "Documents")
        case .archive: L.string(count == 1 ? "Archive" : "Archives")
        case .link: L.string(count == 1 ? "Link" : "Links")
        case .other: L.string(count == 1 ? "File" : "Files")
        }
    }
}
