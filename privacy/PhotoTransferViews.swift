import Photos
import SwiftData
import SwiftUI
import UIKit

struct PhotoTransferStatusView: View {
    @ObservedObject var transfer: PhotoTransferCoordinator
    var body: some View {
        if let journal = transfer.journal {
            Button { transfer.showReview = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: transfer.isRunning ? "arrow.down.circle" : (journal.remainingCount > 0 ? "exclamationmark.circle" : "checkmark.circle"))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(transfer.isRunning ? transfer.phase : L.string(journal.remainingCount > 0 ? "Import needs attention" : "Import complete"))
                            .font(.subheadline.weight(.semibold))
                        Text(L.format("%d of %d saved in Mo Layer", journal.savedCount, journal.entries.count))
                            .font(.caption)
                        if transfer.isRunning { ProgressView(value: transfer.progress) }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .padding(12)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }
}

enum PhotoTransferReviewAction {
    case close
    case keepOriginals
    case deleteOriginals
}

enum PhotoTransferReviewOperation: Equatable {
    case dismissOnly
    case finishKeepingOriginals
    case deleteVerifiedOriginals
}

enum PhotoTransferReviewPolicy {
    static func operation(for action: PhotoTransferReviewAction, transferComplete: Bool) -> PhotoTransferReviewOperation {
        switch action {
        case .deleteOriginals:
            return .deleteVerifiedOriginals
        case .keepOriginals:
            return .finishKeepingOriginals
        case .close:
            return transferComplete ? .finishKeepingOriginals : .dismissOnly
        }
    }
}

struct PhotoTransferReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sync: CloudKitSyncService
    @EnvironmentObject private var subscription: SubscriptionManager
    @ObservedObject var transfer: PhotoTransferCoordinator

    var body: some View {
        NavigationStack {
            ScrollView {
              VStack(spacing: 24) {
                if let journal = transfer.journal {
                    if transfer.isRunning || transfer.isDeleting {
                        progressView(journal)
                    } else if journal.remainingCount > 0 {
                        incompleteView(journal)
                    } else {
                        completionView(journal)
                    }
                }
              }
              .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 24)
            .padding(.top, 44)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L.string("Photo transfer"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.string("Close")) { perform(.close) }
                        .disabled(transfer.isDeleting)
                }
            }
            .interactiveDismissDisabled(transfer.isDeleting)
        }
    }

    private func progressView(_ journal: PhotoTransferJournal) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: transfer.isDeleting ? nil : transfer.progress)
                .controlSize(.large)
            Text(transfer.phase)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(L.format("%d of %d saved in Mo Layer", journal.savedCount, journal.entries.count))
                .foregroundStyle(.secondary)
            if transfer.isRunning {
                Button(L.string("Pause transfer")) { transfer.pause() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func incompleteView(_ journal: PhotoTransferJournal) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text(L.format("Items remaining: %d", journal.remainingCount))
                .font(.title3.weight(.semibold))
            if let message = transfer.reviewMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(L.string("Continue transfer")) {
                transfer.resume(context: modelContext, sync: sync, subscription: subscription)
            }
            .buttonStyle(.borderedProminent)
            Button(L.string("Finish importing and keep originals")) { perform(.keepOriginals) }
                .buttonStyle(.bordered)
        }
    }

    private func completionView(_ journal: PhotoTransferJournal) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.green)
            Text(L.format("Saved in Mo Layer: %d", journal.savedCount))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            if journal.entries.contains(where: { $0.state == .savedKeepingOriginal }) {
                Text(L.string("Originals with edits or extra resources are kept in Photos."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if journal.deletionCount > 0 {
                Text(L.string("Delete the originals from Photos?"))
                    .foregroundStyle(.secondary)
                Button(L.format("Delete originals (%d)", journal.deletionCount), role: .destructive) {
                    perform(.deleteOriginals)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            Button(L.string("Keep originals")) { perform(.keepOriginals) }
                .buttonStyle(.bordered)

            if let message = transfer.reviewMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .multilineTextAlignment(.center)
    }

    private func perform(_ action: PhotoTransferReviewAction) {
        let complete = transfer.journal?.remainingCount == 0 && !transfer.isRunning
        switch PhotoTransferReviewPolicy.operation(for: action, transferComplete: complete) {
        case .dismissOnly:
            dismiss()
        case .finishKeepingOriginals:
            transfer.keepOriginalsAndFinish()
            if transfer.journal == nil { dismiss() }
        case .deleteVerifiedOriginals:
            Task {
                await transfer.deleteVerifiedOriginals(context: modelContext)
                if let journal = transfer.journal, journal.removedCount > 0, journal.deletionCount == 0 {
                    transfer.keepOriginalsAndFinish()
                    dismiss()
                }
            }
        }
    }
}
