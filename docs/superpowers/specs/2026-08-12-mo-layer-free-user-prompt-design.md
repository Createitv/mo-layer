# Mo Layer Free-User Prompt Design

## Goal

Explain Mo Layer before presenting the Pro paywall when a never-subscribed free user tries to enter it. Preserve access to existing files for former Pro users whose membership has expired.

## Entry behavior

- Active Pro users enter Mo Layer immediately.
- Former Pro users with expired access enter Mo Layer in the existing read-only mode.
- Never-subscribed free users remain in the regular vault and see a native alert instead of opening the membership screen immediately.

## Alert

The alert title is `Mo Layer`. Its message explains that Mo Layer is a deeper hidden directory inside the real vault, intended for files needing extra privacy, and that Pro enables entry plus hiding and restoring files between the regular vault and Mo Layer.

The alert has two actions:

- `Cancel` dismisses the alert and leaves the user in the regular vault.
- `Open Pro` dismisses the alert and opens the existing full-screen membership view.

All visible copy uses the existing localization system. Existing `Mo Layer`, `Cancel`, and `Open Pro` keys are reused, with one new explanatory message localized for every supported language.

## Implementation boundary

The decision is based on `MembershipAccessLevel`, not only `isPro`, so `.expiredReadOnly` continues to enter while `.lockedUntilPro` receives the explanation. The existing membership purchase flow is unchanged.

## Verification

- Unit coverage verifies the three membership states map to direct entry or explanation correctly.
- Source-structure coverage verifies the alert includes both required actions and that `Open Pro` transitions to the existing membership view.
- The iOS test target and simulator build must succeed.
