# Video Player Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the video progress bar easy to see and drag, add left-side brightness and right-side volume vertical gestures, and remove the two persistent adjustment slider rows.

**Architecture:** Keep playback ownership in `ZoomableVideoPreview`, extract gesture classification and value calculation into a pure `VideoPlayerGesturePolicy`, and simplify `VideoPlayerControlsOverlay` to playback and seeking only. Give the seek slider a dedicated full-width 44-point interaction row so its width is independent of the transport buttons.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, UIKit, Swift Testing, Xcode `xcodebuild`.

## Global Constraints

- Preserve the existing `AVPlayerLayer`, buffered `AVPlayerItem`, audio-session, zoom, and media-pager behavior.
- Left-half vertical drags adjust `UIScreen.main.brightness`; right-half vertical drags adjust the current `AVPlayer.volume`.
- Upward drags increase values and downward drags decrease values.
- Brightness is clamped to `0.05...1`; volume is clamped to `0...1`.
- Zoomed video drags pan instead of adjusting brightness or volume.
- All edits must preserve unrelated dirty-worktree changes.

---

### Task 1: Gesture Policy

**Files:**
- Modify: `privacy/MainViews.swift` near `ZoomableVideoPreview`
- Test: `privacyTests/privacyTests.swift` near existing video-player tests

**Interfaces:**
- Produces: `VideoPlayerAdjustmentKind`, `VideoPlayerGesturePolicy.adjustment(startX:containerWidth:translation:scale:)`, and `VideoPlayerGesturePolicy.adjustedValue(startingValue:verticalTranslation:containerHeight:range:)`.
- Consumes: `CGFloat`, `CGSize`, and `ClosedRange<Double>`.

- [ ] **Step 1: Write failing gesture-policy tests**

Add Swift Testing cases that assert left-side brightness, right-side volume, horizontal rejection, movement-threshold rejection, zoomed-state rejection, upward increase, downward decrease, and range clamping:

```swift
@Test func videoPlayerGesturePolicyClassifiesVerticalScreenDrags() {
    #expect(VideoPlayerGesturePolicy.adjustment(startX: 40, containerWidth: 300, translation: CGSize(width: 3, height: -80), scale: 1) == .brightness)
    #expect(VideoPlayerGesturePolicy.adjustment(startX: 260, containerWidth: 300, translation: CGSize(width: 3, height: -80), scale: 1) == .volume)
    #expect(VideoPlayerGesturePolicy.adjustment(startX: 40, containerWidth: 300, translation: CGSize(width: 90, height: -30), scale: 1) == nil)
    #expect(VideoPlayerGesturePolicy.adjustment(startX: 40, containerWidth: 300, translation: CGSize(width: 1, height: -5), scale: 1) == nil)
    #expect(VideoPlayerGesturePolicy.adjustment(startX: 40, containerWidth: 300, translation: CGSize(width: 1, height: -80), scale: 2) == nil)
}

@Test func videoPlayerGesturePolicyAdjustsAndClampsValues() {
    #expect(VideoPlayerGesturePolicy.adjustedValue(startingValue: 0.5, verticalTranslation: -100, containerHeight: 400, range: 0...1) == 0.75)
    #expect(VideoPlayerGesturePolicy.adjustedValue(startingValue: 0.5, verticalTranslation: 100, containerHeight: 400, range: 0...1) == 0.25)
    #expect(VideoPlayerGesturePolicy.adjustedValue(startingValue: 0.9, verticalTranslation: -400, containerHeight: 400, range: 0...1) == 1)
    #expect(VideoPlayerGesturePolicy.adjustedValue(startingValue: 0.1, verticalTranslation: 400, containerHeight: 400, range: 0.05...1) == 0.05)
}
```

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
xcodebuild -project privacy.xcodeproj -scheme privacy -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/privacy-video-player-dd test -only-testing:privacyTests
```

Expected: compilation fails because `VideoPlayerGesturePolicy` and `VideoPlayerAdjustmentKind` do not exist.

- [ ] **Step 3: Implement the pure policy**

Add internal types with a 12-point movement threshold, vertical-dominance check, `scale <= 1.001` guard, start-position half selection, and height-normalized value calculation:

```swift
enum VideoPlayerAdjustmentKind: Equatable {
    case brightness
    case volume
}

enum VideoPlayerGesturePolicy {
    private static let minimumMovement: CGFloat = 12

    static func adjustment(
        startX: CGFloat,
        containerWidth: CGFloat,
        translation: CGSize,
        scale: CGFloat
    ) -> VideoPlayerAdjustmentKind? {
        guard scale <= 1.001,
              containerWidth > 0,
              abs(translation.height) >= minimumMovement,
              abs(translation.height) > abs(translation.width) else {
            return nil
        }
        return startX < containerWidth / 2 ? .brightness : .volume
    }

    static func adjustedValue(
        startingValue: Double,
        verticalTranslation: CGFloat,
        containerHeight: CGFloat,
        range: ClosedRange<Double>
    ) -> Double {
        let effectiveHeight = max(containerHeight, 1)
        let delta = -Double(verticalTranslation / effectiveHeight)
        return min(max(startingValue + delta, range.lowerBound), range.upperBound)
    }
}
```

- [ ] **Step 4: Run focused tests and verify GREEN**

Run the Step 2 command again. Expected: all `privacyTests` pass with zero failures.

### Task 2: Full-Screen Brightness and Volume Gestures

**Files:**
- Modify: `privacy/MainViews.swift` in `ZoomableVideoPreview`
- Test: `privacyTests/privacyTests.swift`

**Interfaces:**
- Consumes: Task 1's `VideoPlayerGesturePolicy`.
- Produces: screen-adjustment gesture state, `adjustmentGesture(containerSize:)`, and temporary `VideoPlayerAdjustmentIndicator` UI.

- [ ] **Step 1: Write failing source-structure assertions**

Extend the existing player test to require `adjustmentGesture(containerSize: proxy.size)`, `VideoPlayerAdjustmentIndicator`, and `VideoPlayerGesturePolicy.adjustedValue`, while asserting that zoom pan still uses `dragGesture(containerSize:)`.

- [ ] **Step 2: Run focused tests and verify RED**

Run the Task 1 focused test command. Expected: the new source assertions fail.

- [ ] **Step 3: Implement adjustment gesture state and feedback**

In `ZoomableVideoPreview`, store the active adjustment kind and the starting brightness or volume. Attach a simultaneous vertical drag gesture to the player surface when scale is `1x`. Update brightness or volume continuously with the pure policy, unmute when volume becomes positive, and show a centered icon-plus-percentage indicator. Schedule the indicator to disappear about 700 ms after gesture completion.

Use these state and gesture interfaces:

```swift
@State private var activeAdjustment: VideoPlayerAdjustmentKind?
@State private var adjustmentStartValue: Double?
@State private var adjustmentIndicator: VideoPlayerAdjustmentIndicatorState?
@State private var hideAdjustmentTask: Task<Void, Never>?

private func adjustmentGesture(containerSize: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0)
        .onChanged { value in
            guard let kind = activeAdjustment ?? VideoPlayerGesturePolicy.adjustment(
                startX: value.startLocation.x,
                containerWidth: containerSize.width,
                translation: value.translation,
                scale: displayScale
            ) else { return }
            if activeAdjustment == nil {
                activeAdjustment = kind
                adjustmentStartValue = kind == .brightness ? brightness : volume
            }
            guard let startingValue = adjustmentStartValue else { return }
            let range: ClosedRange<Double> = kind == .brightness ? 0.05...1 : 0...1
            let newValue = VideoPlayerGesturePolicy.adjustedValue(
                startingValue: startingValue,
                verticalTranslation: value.translation.height,
                containerHeight: containerSize.height,
                range: range
            )
            applyAdjustment(kind, value: newValue)
        }
        .onEnded { _ in finishAdjustment() }
}

private func applyAdjustment(_ kind: VideoPlayerAdjustmentKind, value: Double) {
    if kind == .brightness {
        setBrightness(value, schedulesControls: false)
    } else {
        setVolume(value, schedulesControls: false)
    }
    adjustmentIndicator = VideoPlayerAdjustmentIndicatorState(kind: kind, value: value)
}
```

Render `VideoPlayerAdjustmentIndicator(state:)` above the player and controls, with `sun.max.fill` for brightness, the appropriate speaker symbol for volume, and `Int((value * 100).rounded())` percent text.

- [ ] **Step 4: Preserve zoom-pan behavior**

Keep `dragGesture(containerSize:)` responsible only for panning when `displayScale > 1`; the new adjustment gesture returns no classification while zoomed.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run the Task 1 focused test command. Expected: all `privacyTests` pass with zero failures.

### Task 3: Full-Width Seek Bar and Compact Controls

**Files:**
- Modify: `privacy/MainViews.swift` in `VideoPlayerControlsOverlay`
- Test: `privacyTests/privacyTests.swift`

**Interfaces:**
- Consumes: existing `scrubEditingChanged`, `scrubChanged`, play/pause, jump, and mute closures.
- Produces: a full-width seek slider with at least a 44-point hit area; no volume or brightness slider bindings.

- [ ] **Step 1: Write failing overlay assertions**

Update the source test to require a dedicated `VideoPlayerProgressControl(` and `.frame(minHeight: 44)`, and to reject `volumeBinding`, `brightnessBinding`, `volumeChanged`, `brightnessChanged`, and `controlSlider(`.

- [ ] **Step 2: Run focused tests and verify RED**

Run the Task 1 focused test command. Expected: assertions fail because the old two slider rows and compressed inline progress slider still exist.

- [ ] **Step 3: Extract the progress control**

Create `VideoPlayerProgressControl` with elapsed time, a full-width `Slider`, duration, `.contentShape(Rectangle())`, and `.frame(minHeight: 44)`. Keep the existing duration-based range and scrubbing callbacks.

Use this exact public surface:

```swift
private struct VideoPlayerProgressControl: View {
    let displayedTime: Double
    let duration: Double
    @Binding var scrubTime: Double
    let scrubChanged: (Double) -> Void
    let scrubEditingChanged: (Bool) -> Void

    private var progressBinding: Binding<Double> {
        Binding(
            get: { displayedTime },
            set: {
                scrubTime = $0
                scrubChanged($0)
            }
        )
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(VideoPlayerTimeFormatter.text(for: displayedTime))
                .frame(width: 46, alignment: .trailing)
            Slider(
                value: progressBinding,
                in: 0...max(duration, 1),
                onEditingChanged: scrubEditingChanged
            )
            .tint(.white)
            .accessibilityLabel(L.string("Playback Position"))
            Text(VideoPlayerTimeFormatter.text(for: duration))
                .frame(width: 46, alignment: .leading)
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.white.opacity(0.86))
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 4: Simplify the overlay**

Place `VideoPlayerProgressControl` in its own row above a centered transport row. Remove volume and brightness bindings/callbacks and both `controlSlider` rows. Retain the mute button and all accessibility labels.

The overlay call becomes:

```swift
VideoPlayerProgressControl(
    displayedTime: displayedTime,
    duration: duration,
    scrubTime: $scrubTime,
    scrubChanged: scrubChanged,
    scrubEditingChanged: scrubEditingChanged
)
```

- [ ] **Step 5: Run focused tests and verify GREEN**

Run the Task 1 focused test command. Expected: all `privacyTests` pass with zero failures.

### Task 4: Final Verification

**Files:**
- Verify: `privacy/MainViews.swift`
- Verify: `privacyTests/privacyTests.swift`

**Interfaces:**
- Consumes: completed Tasks 1-3.
- Produces: fresh test and compile evidence.

- [ ] **Step 1: Run diff checks**

```bash
git diff --check -- privacy/MainViews.swift privacyTests/privacyTests.swift
git diff -- privacy/MainViews.swift privacyTests/privacyTests.swift
```

Expected: no whitespace errors; diff contains only scoped player/test changes plus preserved pre-existing edits.

- [ ] **Step 2: Run focused unit tests**

```bash
xcodebuild -project privacy.xcodeproj -scheme privacy -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/privacy-video-player-dd test -only-testing:privacyTests
```

Expected: `** TEST SUCCEEDED **` with zero failures.

- [ ] **Step 3: Run simulator compile verification**

```bash
xcodebuild -project privacy.xcodeproj -scheme privacy -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/privacy-video-player-build build
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Review requirements**

Confirm the progress slider is full width and draggable, left-side vertical drag controls brightness, right-side vertical drag controls volume, the old two slider rows are absent, zoom pan remains intact, and no unrelated files changed during implementation.
