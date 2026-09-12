import BackgroundTasks
import Foundation
import UIKit

@MainActor
final class PhotoTransferBackground {
    static let shared = PhotoTransferBackground()
    static let identifierPrefix = "app.landlady.www.privacy.photo-transfer"
    private var requestIdentifier: String?
    private var assertion: UIBackgroundTaskIdentifier = .invalid
    private var expiration: (() -> Void)?
    private var active = false
    private var total = 1
    private var completed = 0
    #if !targetEnvironment(macCatalyst)
    private var continuedTask: BGTask?
    #endif


    func begin(total: Int, expiration: @escaping () -> Void) {
        finish(success: false)
        active = true
        self.total = max(total, 1)
        completed = 0
        self.expiration = expiration
        assertion = UIApplication.shared.beginBackgroundTask(withName: "Private photo transfer") {
            Task { @MainActor in
                #if !targetEnvironment(macCatalyst)
                if self.continuedTask != nil { self.endAssertion(); return }
                #endif
                self.expire()
            }
        }
        #if !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *), UIApplication.shared.applicationState == .active {
            let identifier = Self.identifierPrefix + "." + UUID().uuidString
            requestIdentifier = identifier
            let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
                Task { @MainActor in
                    guard let task = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
                    guard self.active, task.identifier == self.requestIdentifier else { task.setTaskCompleted(success: false); return }
                    self.continuedTask = task
                    task.progress.totalUnitCount = Int64(self.total)
                    task.progress.completedUnitCount = Int64(self.completed)
                    task.expirationHandler = { Task { @MainActor in
                        guard task.identifier == self.requestIdentifier else { return }
                        self.expire()
                    } }
                }
            }
            guard registered else { return }
            let request = BGContinuedProcessingTaskRequest(identifier: identifier,
                title: L.string("Saving to Mo Layer"), subtitle: L.string("Encrypted photo transfer"))
            request.strategy = .fail
            // If unavailable, the finite assertion and durable resume remain in effect.
            try? BGTaskScheduler.shared.submit(request)
        }
        #endif
    }

    func update(completed: Int, total: Int) {
        self.completed = completed
        self.total = max(1, total)
        #if !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *), let task = continuedTask as? BGContinuedProcessingTask {
            task.progress.totalUnitCount = Int64(self.total)
            task.progress.completedUnitCount = Int64(min(completed, self.total))
        }
        #endif
    }
    private func expire() {
        expiration?()
        finish(success: false)
    }
    func finish(success: Bool) {
        active = false
        expiration = nil
        #if !targetEnvironment(macCatalyst)
        continuedTask?.setTaskCompleted(success: success)
        continuedTask = nil
        if #available(iOS 26.0, *), let requestIdentifier { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: requestIdentifier) }
        requestIdentifier = nil
        #endif
        endAssertion()
    }
    private func endAssertion() {
        guard assertion != .invalid else { return }
        UIApplication.shared.endBackgroundTask(assertion)
        assertion = .invalid
    }
}
