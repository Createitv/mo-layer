import AppIntents

struct QuickRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Recording"
    static var description = IntentDescription("Start a quick audio recording and save it to the encrypted vault.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        QuickRecordingRequestStore.requestQuickRecording()
        QuickActionRouter.shared.handleShortcut(type: QuickAction.recorder.rawValue)
        return .result()
    }
}

struct PrivacyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickRecordingIntent(),
            phrases: [
                "Start quick recording in \(.applicationName)",
                "Record audio in \(.applicationName)"
            ],
            shortTitle: "Quick Recording",
            systemImageName: "mic.fill"
        )
    }
}
