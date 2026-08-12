# Mo Layer Free-User Prompt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show an explanatory Mo Layer alert to never-subscribed free users before they choose whether to open the existing Pro paywall.

**Architecture:** Derive a small, testable `MoLayerEntryAction` from `MembershipAccessLevel`, preserving direct entry for active and expired Pro users. Add one presentation state to `VaultHomeView`; locked users set that state, and the alert's affirmative action opens the existing membership cover.

**Tech Stack:** SwiftUI, Swift Testing, project `L.string` localization.

## Global Constraints

- Active Pro and expired read-only users continue entering Mo Layer directly.
- Only `.lockedUntilPro` users receive the explanatory alert.
- `Cancel` leaves the user in the regular vault.
- `Open Pro` opens the existing `MembershipView` flow.
- Add no new dependency and change no purchase behavior.
- Preserve unrelated dirty-worktree changes.

---

### Task 1: Lock the entry policy with a regression test

**Files:**
- Modify: `privacy/SubscriptionManager.swift:12-38`
- Test: `privacyTests/privacyTests.swift`

**Interfaces:**
- Consumes: `MembershipAccessLevel`.
- Produces: `MoLayerEntryAction` and `MembershipAccessLevel.moLayerEntryAction` for the SwiftUI entry flow.

- [ ] **Step 1: Write the failing policy test**

Add a Swift Testing case with literal expected values:

```swift
@Test func moLayerEntryActionExplainsProOnlyToNeverSubscribedUsers() {
    #expect(MembershipAccessLevel.activePro.moLayerEntryAction == .enter)
    #expect(MembershipAccessLevel.expiredReadOnly.moLayerEntryAction == .enter)
    #expect(MembershipAccessLevel.lockedUntilPro.moLayerEntryAction == .explainPro)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
xcodebuild -project privacy.xcodeproj -scheme privacy -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:privacyTests/privacyTests/moLayerEntryActionExplainsProOnlyToNeverSubscribedUsers test
```

Expected: compilation fails because `moLayerEntryAction`, `.enter`, and `.explainPro` do not exist.

- [ ] **Step 3: Add the minimal policy implementation**

Add beside `MembershipAccessLevel`:

```swift
enum MoLayerEntryAction: Equatable {
    case enter
    case explainPro
}
```

Add to `MembershipAccessLevel`:

```swift
var moLayerEntryAction: MoLayerEntryAction {
    allowsVaultEntry ? .enter : .explainPro
}
```

- [ ] **Step 4: Run the policy test and existing membership tests**

Keep `membershipAccessSeparatesActiveExpiredAndLockedStates` and `moLayerEntryUsesVaultReadAccessInsteadOfWriteAccess` passing so expired users remain eligible for entry.

### Task 2: Implement the native explanation alert

**Files:**
- Modify: `privacy/MainViews.swift:735-745`
- Modify: `privacy/MainViews.swift:943-995`
- Modify: `privacy/MainViews.swift:1741-1745`
- Modify: `privacy/en.lproj/Localizable.strings`
- Modify: `privacy/zh-Hans.lproj/Localizable.strings`
- Modify: `privacy/zh-Hant.lproj/Localizable.strings`
- Modify: `privacy/ja.lproj/Localizable.strings`
- Modify: `privacy/de.lproj/Localizable.strings`
- Modify: `privacy/fr.lproj/Localizable.strings`
- Modify: `privacy/ko.lproj/Localizable.strings`
- Modify: `privacy/es.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `subscription.accessLevel.moLayerEntryAction`, existing `showMembership` full-screen cover, `L.string`.
- Produces: `@State private var showMoLayerProPrompt`, native alert transition to membership.

- [ ] **Step 1: Add the minimal presentation state and gate**

Add `showMoLayerProPrompt` beside `showMembership`. In `enterInnerVault()`, branch on the tested policy:

```swift
guard subscription.accessLevel.moLayerEntryAction == .enter else {
    showMoLayerProPrompt = true
    return
}
```

- [ ] **Step 2: Add the alert**

Attach a native SwiftUI alert to `VaultHomeView`:

```swift
.alert(L.string("Mo Layer"), isPresented: $showMoLayerProPrompt) {
    Button(L.string("Cancel"), role: .cancel) {}
    Button(L.string("Open Pro")) {
        showMembership = true
    }
} message: {
    Text(L.string("Mo Layer is a Pro feature. It is a deeper hidden directory inside the real vault for files that need extra privacy. With Pro, you can hide files in Mo Layer and restore them to the regular vault at any time."))
}
```

- [ ] **Step 3: Localize the message**

Add the exact English localization key above to every supported `.lproj` file, with a natural translation for that locale. Reuse existing `Mo Layer`, `Cancel`, and `Open Pro` keys.

- [ ] **Step 4: Run focused tests to verify green**

Run the Task 1 command plus the existing membership-state and read-access tests. Expected: all selected tests pass.

### Task 3: Verify integration and build

**Files:**
- Verify only; no expected source changes.

**Interfaces:**
- Consumes: completed alert and localization changes.
- Produces: current test/build evidence.

- [ ] **Step 1: Validate localization syntax and diff hygiene**

Run `plutil -lint` for all eight modified `Localizable.strings` files and `git diff --check` for the scoped files.

- [ ] **Step 2: Run the iOS test target**

Run:

```bash
xcodebuild -project privacy.xcodeproj -scheme privacy -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Expected: `TEST SUCCEEDED` with zero failures.

- [ ] **Step 3: Run a clean simulator build**

Run:

```bash
xcodebuild -project privacy.xcodeproj -scheme privacy -destination 'generic/platform=iOS Simulator' build
```

Expected: `BUILD SUCCEEDED`.
