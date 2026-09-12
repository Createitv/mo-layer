import Foundation
import Photos

/// PhotoKit can deliver a degraded preview, a final result, and late callbacks
/// after cancellation. Exactly one of the terminal paths may resume the task.
final class LivePhotoRequestCompletion: @unchecked Sendable {
    nonisolated private let lock = NSLock()
    nonisolated(unsafe) private var continuation: CheckedContinuation<PHLivePhoto?, Never>?
    nonisolated(unsafe) private var requestID: PHLivePhotoRequestID?
    nonisolated(unsafe) private var finished = false
    nonisolated(unsafe) private var cancelled = false

    nonisolated init() {}

    nonisolated func install(_ continuation: CheckedContinuation<PHLivePhoto?, Never>) {
        let alreadyFinished = lock.withLock {
            if finished { return true }
            self.continuation = continuation
            return false
        }
        if alreadyFinished { continuation.resume(returning: nil) }
    }

    nonisolated func register(_ requestID: PHLivePhotoRequestID) {
        let shouldCancel = lock.withLock {
            self.requestID = requestID
            return cancelled
        }
        if shouldCancel { PHLivePhoto.cancelRequest(withRequestID: requestID) }
    }

    @discardableResult
    nonisolated func receive(_ photo: PHLivePhoto?, info: [AnyHashable: Any]) -> Bool {
        let cancelled = (info[PHLivePhotoInfoCancelledKey] as? NSNumber)?.boolValue == true
        let failed = info[PHLivePhotoInfoErrorKey] != nil
        let degraded = (info[PHLivePhotoInfoIsDegradedKey] as? NSNumber)?.boolValue == true
        guard cancelled || failed || !degraded else { return false }
        return finish(with: cancelled || failed ? nil : photo)
    }

    nonisolated func cancel() {
        let id = lock.withLock { cancelled = true; return requestID }
        finish(with: nil)
        if let id { PHLivePhoto.cancelRequest(withRequestID: id) }
    }

    @discardableResult
    nonisolated private func finish(with photo: PHLivePhoto?) -> Bool {
        let result: (Bool, CheckedContinuation<PHLivePhoto?, Never>?) = lock.withLock {
            guard !finished else { return (false, nil) }
            finished = true
            let pending = continuation
            continuation = nil
            return (true, pending)
        }
        result.1?.resume(returning: photo)
        return result.0
    }
}
