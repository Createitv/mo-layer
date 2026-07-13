import Foundation

struct ImportSummary: Identifiable, Equatable {
    let id = UUID()
    private(set) var importedByKind: [VaultItemKind: Int] = [:]
    private(set) var failedCount = 0
    private(set) var skippedDuplicateCount = 0

    var importedCount: Int {
        importedByKind.values.reduce(0, +)
    }

    var hasReportableResult: Bool {
        importedCount > 0 || failedCount > 0 || skippedDuplicateCount > 0
    }

    var displayTitle: String {
        L.string("Import Complete")
    }

    var displayMessage: String {
        let importedText = orderedKindParts.joined(separator: ", ")
        if importedCount == 0, skippedDuplicateCount > 0, failedCount == 0 {
            return L.format("No new items imported. %d duplicate(s) skipped.", skippedDuplicateCount)
        }
        if skippedDuplicateCount > 0, failedCount > 0 {
            return L.format("%@ imported. %d duplicate(s) skipped. %d failed.", importedText, skippedDuplicateCount, failedCount)
        }
        if skippedDuplicateCount > 0 {
            return L.format("%@ imported. %d duplicate(s) skipped.", importedText, skippedDuplicateCount)
        }
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

    mutating func recordSkippedDuplicate() {
        skippedDuplicateCount += 1
    }

    mutating func record(_ result: VaultImportResult, kind: VaultItemKind) {
        switch result {
        case .imported:
            record(kind)
        case .skippedDuplicate:
            recordSkippedDuplicate()
        case .failed:
            recordFailure()
        }
    }

    mutating func merge(_ other: ImportSummary) {
        for (kind, count) in other.importedByKind {
            importedByKind[kind, default: 0] += count
        }
        failedCount += other.failedCount
        skippedDuplicateCount += other.skippedDuplicateCount
    }

    private var orderedKindParts: [String] {
        VaultItemKind.allCases.compactMap { kind in
            guard let count = importedByKind[kind], count > 0 else { return nil }
            return "\(count) \(kind.importSummaryName(count: count))"
        }
    }
}

struct VaultImportProgress: Equatable {
    var totalCount: Int
    private(set) var importedCount = 0
    private(set) var failedCount = 0
    private(set) var skippedDuplicateCount = 0
    private(set) var isActive = true
    private(set) var currentItem: VaultImportProgressItem?

    var completedCount: Int {
        importedCount + failedCount + skippedDuplicateCount
    }

    var currentItemProgress: Double {
        currentItem?.progress ?? (isActive ? 0 : 1)
    }

    var overallProgress: Double {
        guard totalCount > 0 else { return 0 }
        let inFlightProgress = isActive ? currentItemProgress : 0
        return min(max((Double(completedCount) + inFlightProgress) / Double(totalCount), 0), 1)
    }

    var isReadyForAutoDismissal: Bool {
        !isActive && completedCount >= totalCount
    }

    var statusText: String {
        if skippedDuplicateCount > 0, failedCount > 0 {
            return L.format("Selected %d files, imported %d, skipped %d duplicates, %d failed", totalCount, importedCount, skippedDuplicateCount, failedCount)
        }
        if skippedDuplicateCount > 0 {
            return L.format("Selected %d files, imported %d, skipped %d duplicates", totalCount, importedCount, skippedDuplicateCount)
        }
        if failedCount > 0 {
            return L.format("Selected %d files, imported %d, %d failed", totalCount, importedCount, failedCount)
        }
        return L.format("Selected %d files, imported %d", totalCount, importedCount)
    }

    mutating func updateCurrentItem(_ item: VaultImportProgressItem) {
        currentItem = item
    }

    mutating func recordImported() {
        importedCount += 1
        currentItem = currentItem?.completed()
    }

    mutating func recordFailure() {
        failedCount += 1
        currentItem = currentItem?.completed()
    }

    mutating func recordSkippedDuplicate() {
        skippedDuplicateCount += 1
        currentItem = currentItem?.completed()
    }

    mutating func record(_ result: VaultImportResult) {
        switch result {
        case .imported:
            recordImported()
        case .skippedDuplicate:
            recordSkippedDuplicate()
        case .failed:
            recordFailure()
        }
    }

    mutating func finish() {
        isActive = false
        currentItem = nil
    }
}

struct VaultImportProgressItem: Equatable {
    var displayName: String
    var kind: VaultItemKind
    var phaseText: String
    var progress: Double
    var thumbnailData: Data?

    var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    func updating(phaseText: String, progress: Double, thumbnailData: Data? = nil) -> VaultImportProgressItem {
        VaultImportProgressItem(
            displayName: displayName,
            kind: kind,
            phaseText: phaseText,
            progress: min(max(progress, 0), 1),
            thumbnailData: thumbnailData ?? self.thumbnailData
        )
    }

    func completed() -> VaultImportProgressItem {
        updating(phaseText: L.string("Finishing current file"), progress: 1)
    }
}

enum VaultImportProgressEvent {
    case currentItem(VaultImportProgressItem)
    case completed(VaultImportResult)
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
