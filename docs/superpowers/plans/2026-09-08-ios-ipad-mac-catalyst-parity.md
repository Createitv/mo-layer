# iPhone, iPad, and Mac Catalyst Feature Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Mo Layer's core vault workflows behaviorally consistent across iPhone, iPad, and Mac Catalyst, with explicit platform-equivalent routes for unavailable system capabilities.

**Architecture:** Keep one shared SwiftUI application, model, encryption, membership, and CloudKit stack. Add a pure-value platform routing contract that views consume, then adapt import, progress, commands, playback, permissions, and layout at the system-integration boundary without duplicating business logic.

**Tech Stack:** Swift 5, SwiftUI, SwiftData, UIKit for iOS/Catalyst bridges, PhotosUI, VisionKit, AVFoundation, ActivityKit, UserNotifications, RevenueCat, CloudKit, Swift Testing, XCUITest, Xcode 26.4.

**Spec:** `docs/superpowers/specs/2026-09-08-ios-ipad-mac-catalyst-parity-design.md`

## Global Constraints

- Use the existing Mac Catalyst target; do not create a native AppKit/macOS target.
- Keep encryption format, CloudKit schema/container, free limit, membership pricing, and Mo Layer authorization unchanged.
- Preserve all pre-existing uncommitted work and stage only task-owned hunks.
- Hardware-specific functionality must expose a working equivalent route or an explanatory action; never leave a dead disabled control.
- New user-facing copy must be present in all eight existing localization bundles.
- Every modal membership or platform-alternative flow must have an explicit close or cancel path.
- Verify iPhone Simulator, iPad Pro Simulator, and Mac Catalyst independently; a generic build is not runtime parity evidence.
- Do not append `Co-Authored-By` trailers to commits.

---

### Task 1: Define the testable platform feature-routing contract

**Files:**
- Modify: `privacy/PlatformCapabilities.swift`
- Test: `privacyTests/privacyTests.swift`

**Interfaces:**
- Consumes: `UIDevice.current.userInterfaceIdiom`, `UIImagePickerController.isSourceTypeAvailable(.camera)`, and the existing Catalyst compile condition.
- Produces: `MoLayerPlatform`, `PlatformFeatureRoutes`, `MediaCaptureRoute`, `DocumentScanRoute`, `BackgroundProgressRoute`, `ShortcutEntryRoute`, `OfferCodeRoute`, `VideoBrightnessRoute`, and `PlatformCapabilities.routes`.

- [ ] **Step 1: Write failing routing tests**

Add tests covering all platforms and hardware states:

```swift
@Test func macUsesDesktopEquivalentRoutes() {
    let routes = PlatformFeatureRoutes.resolve(
        platform: .macCatalyst,
        cameraAvailable: false,
        documentScannerAvailable: false
    )
    #expect(routes.mediaCapture == .importMedia)
    #expect(routes.documentScan == .importMedia)
    #expect(routes.backgroundProgress == .inAppAndNotification)
    #expect(routes.shortcutEntry == .commands)
    #expect(routes.offerCode == .appStoreInstructions)
    #expect(routes.videoBrightness == .playerEffect)
}

@Test func iPhoneAndIPadKeepNativeMobileRoutesWhenAvailable() {
    for platform in [MoLayerPlatform.iPhone, .iPad] {
        let routes = PlatformFeatureRoutes.resolve(
            platform: platform,
            cameraAvailable: true,
            documentScannerAvailable: true
        )
        #expect(routes.mediaCapture == .nativeCamera)
        #expect(routes.documentScan == .visionKit)
        #expect(routes.backgroundProgress == .liveActivity)
        #expect(routes.shortcutEntry == .homeScreen)
        #expect(routes.offerCode == .systemSheet)
        #expect(routes.videoBrightness == .systemDisplay)
    }
}
```

- [ ] **Step 2: Run the focused tests and confirm RED**

Run:

```bash
xcodebuild -project privacy.xcodeproj -scheme privacy \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/molayer-platform-parity-dd \
  build-for-testing \
  -only-testing:privacyTests/privacyTests/macUsesDesktopEquivalentRoutes \
  -only-testing:privacyTests/privacyTests/iPhoneAndIPadKeepNativeMobileRoutesWhenAvailable \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```

Expected: compilation fails because the routing types do not exist.

- [ ] **Step 3: Implement the pure routing types**

Add Equatable enums and an immutable route bundle:

```swift
enum MoLayerPlatform: Equatable {
    case iPhone
    case iPad
    case macCatalyst
}

enum MediaCaptureRoute: Equatable { case nativeCamera, importMedia }
enum DocumentScanRoute: Equatable { case visionKit, importMedia }
enum BackgroundProgressRoute: Equatable { case liveActivity, inAppAndNotification }
enum ShortcutEntryRoute: Equatable { case homeScreen, commands }
enum OfferCodeRoute: Equatable { case systemSheet, appStoreInstructions }
enum VideoBrightnessRoute: Equatable { case systemDisplay, playerEffect }

struct PlatformFeatureRoutes: Equatable {
    let mediaCapture: MediaCaptureRoute
    let documentScan: DocumentScanRoute
    let backgroundProgress: BackgroundProgressRoute
    let shortcutEntry: ShortcutEntryRoute
    let offerCode: OfferCodeRoute
    let videoBrightness: VideoBrightnessRoute

    static func resolve(
        platform: MoLayerPlatform,
        cameraAvailable: Bool,
        documentScannerAvailable: Bool
    ) -> Self {
        if platform == .macCatalyst {
            return .init(
                mediaCapture: .importMedia,
                documentScan: .importMedia,
                backgroundProgress: .inAppAndNotification,
                shortcutEntry: .commands,
                offerCode: .appStoreInstructions,
                videoBrightness: .playerEffect
            )
        }
        return .init(
            mediaCapture: cameraAvailable ? .nativeCamera : .importMedia,
            documentScan: documentScannerAvailable ? .visionKit : .importMedia,
            backgroundProgress: .liveActivity,
            shortcutEntry: .homeScreen,
            offerCode: .systemSheet,
            videoBrightness: .systemDisplay
        )
    }
}
```

Expose `MoLayerPlatform.current` and compute `PlatformCapabilities.routes` from the real device environment. Keep existing compatibility properties as thin computed projections until all call sites migrate.

- [ ] **Step 4: Run the focused tests and confirm GREEN**

Run the Step 2 command. Expected: `TEST BUILD SUCCEEDED` with no routing errors.

- [ ] **Step 5: Commit only the routing contract and tests**

```bash
git add -p privacy/PlatformCapabilities.swift privacyTests/privacyTests.swift
git commit -m 'Add cross-platform feature routing contract'
```

---

### Task 2: Replace unavailable Mac import controls with working equivalents

**Files:**
- Modify: `privacy/FeatureViews.swift`
- Test: `privacyTests/privacyTests.swift`

**Interfaces:**
- Consumes: `PlatformCapabilities.routes.documentScan`, `VaultFreeImportPolicy`, and `VaultImportQueue.importFiles(urls:context:vaultStore:sync:folderId:syncAfterImportCompletion:completion:)`.
- Produces: `ImportAlternativeAction`, `ImportAlternativePolicy.actions(for:)`, `ImportHubView.handleFileURLs(_:)`, and desktop URL drop routing.

- [ ] **Step 1: Write failing alternative-action tests**

```swift
@Test func documentScanAlternativeOffersPhotosAndFilesOnMac() {
    #expect(ImportAlternativePolicy.actions(for: .importMedia) == [.photos, .files])
    #expect(ImportAlternativePolicy.actions(for: .visionKit) == [.scanner])
}
```

- [ ] **Step 2: Run the test and confirm RED**

Use the Task 1 build-for-testing command with only the new test. Expected: missing `ImportAlternativePolicy`.

- [ ] **Step 3: Implement explicit import alternatives and shared URL handling**

Add the pure policy:

```swift
enum ImportAlternativeAction: Equatable { case scanner, photos, files }

enum ImportAlternativePolicy {
    static func actions(for route: DocumentScanRoute) -> [ImportAlternativeAction] {
        route == .visionKit ? [.scanner] : [.photos, .files]
    }
}
```

In `ImportHubView`, replace the permanently disabled Mac scan button with an enabled button that opens a `confirmationDialog` containing Photos and Files actions. Route both the file picker result and URL drops through:

```swift
private func handleFileURLs(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    guard canImportVaultItems(count: urls.count) else {
        showMembership = true
        return
    }
    vaultStore.setWriteAccess(true)
    importQueue.importFiles(
        urls: urls,
        context: modelContext,
        vaultStore: vaultStore,
        sync: sync,
        folderId: destinationFolderId,
        syncAfterImportCompletion: subscription.canImportAndSync,
        completion: handleImported
    )
}
```

Attach `.dropDestination(for: URL.self)` to the import content. Accept drops only when the route is desktop-compatible and the free-limit check passes. Do not duplicate security-scoped access; `ImportService.importFiles` already starts and stops it around each URL read.

```swift
.dropDestination(for: URL.self) { urls, _ in
    guard PlatformCapabilities.currentPlatform == .macCatalyst,
          !urls.isEmpty else { return false }
    handleFileURLs(urls)
    return true
}
```

- [ ] **Step 4: Run import policy and existing import tests**

Run the new policy test plus the existing fingerprint, filename, duplicate, progress, and free-limit tests. Expected: all selected tests pass.

- [ ] **Step 5: Build iPad and Mac Catalyst**

```bash
xcodebuild -project privacy.xcodeproj -scheme privacy \
  -destination 'platform=iOS Simulator,id=2325D5B9-8766-40B2-9972-E3597D14829B' \
  -derivedDataPath /tmp/molayer-platform-parity-dd build CODE_SIGNING_ALLOWED=NO

xcodebuild -project privacy.xcodeproj -scheme privacy \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath /tmp/molayer-platform-parity-mac-dd build \
  CODE_SIGNING_ALLOWED=NO ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES
```

Expected: both builds succeed and the scan alternative compiles on both platforms.

- [ ] **Step 6: Commit only import-equivalence changes**

```bash
git add -p privacy/FeatureViews.swift privacyTests/privacyTests.swift
git commit -m 'Add Mac equivalents for media and scan import'
```

---

### Task 3: Add Mac command equivalents and durable progress notification routing

**Files:**
- Modify: `privacy/QuickActionRouter.swift`
- Modify: `privacy/privacyApp.swift`
- Modify: `privacy/PhotoTransferCoordinator.swift`
- Create: `privacy/PlatformProgressNotifier.swift`
- Test: `privacyTests/privacyTests.swift`

**Interfaces:**
- Consumes: `QuickActionRouter.shared`, `PlatformCapabilities.routes.shortcutEntry`, `PlatformCapabilities.routes.backgroundProgress`, and photo-transfer completion state.
- Produces: `MoLayerCommands`, `PlatformProgressNotificationEvent`, `PlatformProgressNotificationPolicy.event(completed:total:failedCount:)`, and `PlatformProgressNotifier.post(_:)`.

- [ ] **Step 1: Write failing command and notification policy tests**

```swift
@Test func completedDesktopTransferProducesACompletionNotification() {
    #expect(PlatformProgressNotificationPolicy.event(
        completed: 4,
        total: 4,
        failedCount: 0
    ) == .completed(count: 4))
    #expect(PlatformProgressNotificationPolicy.event(
        completed: 3,
        total: 4,
        failedCount: 1
    ) == .needsAttention(completed: 3, total: 4))
}
```

- [ ] **Step 2: Run the focused test and confirm RED**

Expected: missing notification policy types.

- [ ] **Step 3: Implement Mac commands using existing quick-action routes**

Define a `Commands` implementation under the Catalyst compile condition:

```swift
#if targetEnvironment(macCatalyst)
struct MoLayerCommands: Commands {
    var body: some Commands {
        CommandMenu(L.string("Mo Layer")) {
            Button(L.string("Import")) {
                QuickActionRouter.shared.pendingAction = .importHub
            }
            .keyboardShortcut("i", modifiers: .command)

            Button(L.string("Record Audio")) {
                QuickActionRouter.shared.pendingAction = .recorder
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
        }
    }
}
#endif
```

Attach `.commands { MoLayerCommands() }` to the app scene only for Catalyst. iPhone/iPad continue using `UIApplicationShortcutItem`; both routes terminate in `QuickActionRouter`.

- [ ] **Step 4: Implement desktop completion notifications**

Create a pure event policy and a `UNUserNotificationCenter` adapter. Request notification authorization only after a desktop transfer begins, post only terminal completion/attention notifications, and keep `PhotoTransferStatusView` as the always-available in-app progress UI. Call the adapter from the photo-transfer terminal path only when `backgroundProgress == .inAppAndNotification`.

```swift
enum PlatformProgressNotificationEvent: Equatable {
    case completed(count: Int)
    case needsAttention(completed: Int, total: Int)
}

enum PlatformProgressNotificationPolicy {
    static func event(completed: Int, total: Int, failedCount: Int) -> PlatformProgressNotificationEvent {
        failedCount == 0 && completed == total
            ? .completed(count: completed)
            : .needsAttention(completed: completed, total: total)
    }
}

@MainActor
final class PlatformProgressNotifier {
    static let shared = PlatformProgressNotifier()
    private let center = UNUserNotificationCenter.current()

    func prepareIfNeeded() async {
        guard PlatformCapabilities.routes.backgroundProgress == .inAppAndNotification else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func post(_ event: PlatformProgressNotificationEvent) async {
        guard PlatformCapabilities.routes.backgroundProgress == .inAppAndNotification else { return }
        let content = UNMutableNotificationContent()
        switch event {
        case .completed(let count):
            content.title = L.string("Import complete")
            content.body = L.format("Saved in Mo Layer: %d", count)
        case .needsAttention(let completed, let total):
            content.title = L.string("Import needs attention")
            content.body = L.format("%d of %d saved in Mo Layer", completed, total)
        }
        try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
```

- [ ] **Step 5: Run focused policy tests and three-platform builds**

Run the new test, then the iPad and Catalyst build commands from Task 2 and the generic iOS Simulator build. Expected: all succeed.

- [ ] **Step 6: Commit commands and progress-equivalence changes**

```bash
git add -p privacy/QuickActionRouter.swift privacy/privacyApp.swift privacy/PhotoTransferCoordinator.swift privacy/PlatformProgressNotifier.swift privacyTests/privacyTests.swift
git commit -m 'Add Mac commands and transfer notifications'
```

---

### Task 4: Make video brightness behavior platform-safe

**Files:**
- Modify: `privacy/MainViews.swift`
- Test: `privacyTests/privacyTests.swift`

**Interfaces:**
- Consumes: `PlatformCapabilities.routes.videoBrightness` and existing `VideoPlayerGesturePolicy`.
- Produces: `VideoBrightnessPolicy.initialValue(route:systemBrightness:)`, `VideoBrightnessPolicy.playerEffect(value:route:)`, and platform-safe brightness application.

- [ ] **Step 1: Write failing brightness policy tests**

```swift
@Test func desktopBrightnessAdjustsOnlyThePlayerEffect() {
    #expect(VideoBrightnessPolicy.initialValue(route: .playerEffect, systemBrightness: 0.8) == 0.5)
    #expect(VideoBrightnessPolicy.playerEffect(value: 0.75, route: .playerEffect) == 0.25)
    #expect(VideoBrightnessPolicy.playerEffect(value: 0.75, route: .systemDisplay) == 0)
}
```

- [ ] **Step 2: Run the focused test and confirm RED**

Expected: missing `VideoBrightnessPolicy`.

- [ ] **Step 3: Implement and wire the pure brightness policy**

```swift
enum VideoBrightnessPolicy {
    static func initialValue(route: VideoBrightnessRoute, systemBrightness: Double) -> Double {
        route == .playerEffect ? 0.5 : systemBrightness
    }

    static func playerEffect(value: Double, route: VideoBrightnessRoute) -> Double {
        route == .playerEffect ? min(max(value - 0.5, -0.5), 0.5) : 0
    }
}
```

Apply `.brightness(...)` to `PlayerLayerView`. In `setBrightness`, write `UIScreen.main.brightness` only for `.systemDisplay`; for `.playerEffect`, update local state only. Also avoid changing `UIApplication.shared.isIdleTimerDisabled` on Catalyst because desktop sleep policy must remain system-controlled.

- [ ] **Step 4: Run video gesture, playback, and brightness tests**

Run the new test and all existing tests whose names contain `video`, `fullscreen`, or `playback`. Expected: pass.

- [ ] **Step 5: Build iPhone, iPad, and Mac Catalyst**

Use the platform build commands from Task 2. Expected: all succeed.

- [ ] **Step 6: Commit only playback parity changes**

```bash
git add -p privacy/MainViews.swift privacyTests/privacyTests.swift
git commit -m 'Adapt video brightness behavior for Mac'
```

---

### Task 5: Make adaptive layout and modal behavior explicit

**Files:**
- Modify: `privacy/MainViews.swift`
- Modify: `privacy/ContentView.swift`
- Modify: `privacy/DetailAndMembershipViews.swift`
- Modify: `privacy/FeatureViews.swift`
- Test: `privacyTests/privacyTests.swift`

**Interfaces:**
- Consumes: `MoLayerPlatform`, horizontal size class, the existing `NavigationSplitView`, and `MembershipPresentationContext`.
- Produces: `VaultAdaptiveLayoutMode`, `VaultAdaptiveLayoutPolicy.mode(platform:horizontalSizeClass:)`, preserved selection across layout changes, and explicit dismiss controls for every full-screen membership presentation.

- [ ] **Step 1: Write failing adaptive-layout tests**

```swift
@Test func adaptiveLayoutUsesStackOnlyForCompactMobileWidth() {
    #expect(VaultAdaptiveLayoutPolicy.mode(platform: .iPhone, horizontalSizeClass: .compact) == .stack)
    #expect(VaultAdaptiveLayoutPolicy.mode(platform: .iPad, horizontalSizeClass: .regular) == .split)
    #expect(VaultAdaptiveLayoutPolicy.mode(platform: .iPad, horizontalSizeClass: .compact) == .stack)
    #expect(VaultAdaptiveLayoutPolicy.mode(platform: .macCatalyst, horizontalSizeClass: nil) == .desktop)
}
```

- [ ] **Step 2: Run the focused test and confirm RED**

Expected: missing adaptive-layout policy types.

- [ ] **Step 3: Replace implicit layout booleans with the tested policy**

Define:

```swift
enum VaultAdaptiveLayoutMode: Equatable { case stack, split, desktop }

enum VaultAdaptiveLayoutPolicy {
    static func mode(
        platform: MoLayerPlatform,
        horizontalSizeClass: UserInterfaceSizeClass?
    ) -> VaultAdaptiveLayoutMode {
        if platform == .macCatalyst { return .desktop }
        return horizontalSizeClass == .regular ? .split : .stack
    }
}
```

Use a single `layoutMode` in `VaultHomeView` to select `scrollContent`, `splitHomeContent`, or `desktopHomeContent`. When size class changes, retain `selectedCategory`, current media selection, Mo Layer state, and import state. Keep toolbar access to Mo Layer so triple-tap is never the sole iPad/Mac entry.

- [ ] **Step 4: Complete modal dismissal coverage**

Pass `presentationContext: .modal` at every `MembershipView` full-screen-cover call site and retain `.navigation` for pushed settings destinations. Verify the regression test `modalMembershipPresentationProvidesDismissControl` passes.

- [ ] **Step 5: Run layout and membership tests, then build all platforms**

Expected: focused tests and all three builds pass.

- [ ] **Step 6: Commit layout and modal parity changes**

```bash
git add -p privacy/MainViews.swift privacy/ContentView.swift privacy/DetailAndMembershipViews.swift privacy/FeatureViews.swift privacyTests/privacyTests.swift
git commit -m 'Unify adaptive layout and modal navigation'
```

---

### Task 6: Add Mac offer-code guidance and platform-neutral permission copy

**Files:**
- Modify: `privacy/SubscriptionManager.swift`
- Modify: `privacy/DetailAndMembershipViews.swift`
- Modify: `privacy/FeatureViews.swift`
- Modify: `privacy/de.lproj/Localizable.strings`
- Modify: `privacy/en.lproj/Localizable.strings`
- Modify: `privacy/es.lproj/Localizable.strings`
- Modify: `privacy/fr.lproj/Localizable.strings`
- Modify: `privacy/ja.lproj/Localizable.strings`
- Modify: `privacy/ko.lproj/Localizable.strings`
- Modify: `privacy/zh-Hans.lproj/Localizable.strings`
- Modify: `privacy/zh-Hant.lproj/Localizable.strings`
- Test: `privacyTests/privacyTests.swift`

**Interfaces:**
- Consumes: `PlatformCapabilities.routes.offerCode`, `RestorePurchaseFeedback`, and `UIApplication.openSettingsURLString`.
- Produces: `OfferCodePresentationPolicy`, a Mac App Store instruction alert, and platform-neutral permission strings.

- [ ] **Step 1: Write failing offer-code presentation tests**

```swift
@Test func offerCodePresentationExplainsTheMacAppStorePath() {
    #expect(OfferCodePresentationPolicy.action(for: .systemSheet) == .openSystemSheet)
    #expect(OfferCodePresentationPolicy.action(for: .appStoreInstructions) == .showInstructions)
}
```

- [ ] **Step 2: Run the focused test and confirm RED**

Expected: missing offer-code presentation policy.

- [ ] **Step 3: Implement route-aware redemption UI**

For `.systemSheet`, keep `Purchases.shared.presentCodeRedemptionSheet()` and entitlement refresh. For `.appStoreInstructions`, display a closable alert explaining: open App Store, choose the account name, choose “Redeem Gift Card or Code”, complete redemption, return to Mo Layer, then tap Restore Purchases. Do not report this as a failed redemption.

```swift
enum OfferCodePresentationAction: Equatable {
    case openSystemSheet
    case showInstructions
}

enum OfferCodePresentationPolicy {
    static func action(for route: OfferCodeRoute) -> OfferCodePresentationAction {
        route == .systemSheet ? .openSystemSheet : .showInstructions
    }
}
```

`MembershipView.redeemOfferCode()` switches on this action. `.showInstructions` sets `showOfferCodeInstructions = true`; `.openSystemSheet` calls the existing async subscription method. Add this alert to the membership page:

```swift
.alert(L.string("Redeem Code"), isPresented: $showOfferCodeInstructions) {
    Button(L.string("OK"), role: .cancel) {}
} message: {
    Text(L.string("Open the App Store, select your account, choose Redeem Gift Card or Code, then return to Mo Layer and tap Restore Purchases."))
}
```

- [ ] **Step 4: Replace device-specific settings copy**

Add localized keys for “Open System Settings”, the generic permission explanation, the Mac import alternative, and the App Store redemption steps in all eight bundles. Update `UserPermissionsView` and the import/paywall UI to use the generic strings.

- [ ] **Step 5: Validate localization coverage and focused tests**

Run a shell check that every new English key occurs exactly once in each localization file, then run the offer-code and membership tests. Expected: eight-bundle coverage and passing tests.

- [ ] **Step 6: Build all three platforms and commit**

```bash
git add -p privacy/SubscriptionManager.swift privacy/DetailAndMembershipViews.swift privacy/FeatureViews.swift privacy/*.lproj/Localizable.strings privacyTests/privacyTests.swift
git commit -m 'Add Mac redemption guidance and neutral permissions copy'
```

---

### Task 7: Add platform smoke coverage and perform the release audit

**Files:**
- Modify: `privacyUITests/privacyUITests.swift`
- Modify: `privacyTests/privacyTests.swift`
- Modify: `docs/implementation/2026-09-08-platform-parity-verification.md`

**Interfaces:**
- Consumes: all route policies and production flows from Tasks 1–6.
- Produces: a platform parity test matrix and a verification report that separates build, automated execution, local runtime smoke, CloudKit configuration, and real cross-device delivery evidence.

- [ ] **Step 1: Add deterministic launch arguments for smoke tests**

Extend existing UI-test launch setup without bypassing encryption or production authorization. Add smoke tests that assert the root flow can launch, the import hub can open and close, the membership paywall can open and close, and a visible Mo Layer toolbar entry exists on regular-width iPad and Catalyst.

Do not add a production authentication bypass. Use a launch-only smoke that accepts either the onboarding, lock, or vault root as a valid secured start state, then add interaction tests only on test hosts whose persisted secure setup already reaches the vault:

```swift
@MainActor
func testSecuredRootLaunches() throws {
    let app = XCUIApplication()
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
    XCTAssertTrue(
        app.otherElements["vault.root"].exists ||
        app.buttons["onboarding.continue"].exists ||
        app.secureTextFields.firstMatch.exists
    )
}
```

Define test-only accessibility identifiers in the production views for the root, import, membership-close, and Mo Layer controls. The identifiers expose no data and do not alter authorization.

- [ ] **Step 2: Run the complete unit-test bundle on iPhone Simulator**

```bash
xcodebuild -project privacy.xcodeproj -scheme privacy \
  -destination 'platform=iOS Simulator,id=38EEDBF7-0D38-4496-A62C-1D5CA5D8CCD2' \
  -derivedDataPath /tmp/molayer-platform-parity-dd test \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES
```

Expected: all unit tests pass. Record exact passed/failed counts.

- [ ] **Step 3: Run iPad unit and UI smoke tests**

Use simulator `2325D5B9-8766-40B2-9972-E3597D14829B`. Run portrait and landscape smoke flows, then resize or use a compact configuration to exercise stack fallback. Record which interactions executed rather than treating build-for-testing as UI evidence.

- [ ] **Step 4: Run Mac Catalyst tests and launch smoke**

```bash
xcodebuild -project privacy.xcodeproj -scheme privacy \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath /tmp/molayer-platform-parity-mac-dd test \
  CODE_SIGNING_ALLOWED=NO ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES
```

Launch the built app locally and verify window resizing, import alternatives, URL drop, menu commands, paywall close, and player-local brightness. Record any test-host limitation separately from build success.

- [ ] **Step 5: Audit Release settings and diffs**

Run unsigned Release builds for generic iOS and Mac Catalyst. Confirm iOS-only extensions remain platform-filtered, Mac sandbox entitlements remain present, no secrets are in diffs, and only task-owned hunks are staged.

- [ ] **Step 6: Write the evidence report and run final verification**

The report must list each spec completion criterion with one of: proven, contradicted, or unverified. It must not label CloudKit cross-device propagation, purchase delivery, or physical-camera behavior as proven unless those flows actually execute on signed real devices/accounts.

- [ ] **Step 7: Commit smoke coverage and verification evidence**

```bash
git add -p privacyUITests/privacyUITests.swift privacyTests/privacyTests.swift docs/implementation/2026-09-08-platform-parity-verification.md
git commit -m 'Verify iPhone iPad and Mac feature parity'
```
