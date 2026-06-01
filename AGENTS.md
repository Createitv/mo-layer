# Repository Guidelines

## Project Structure & Module Organization

This is a SwiftUI iOS app in `privacy.xcodeproj`. Main app code lives in `privacy/`, including vault state, import flows, CloudKit sync, localization, and UI views. Unit tests are in `privacyTests/`; UI tests are in `privacyUITests/`. The share extension is in `privacyShareExtension/`, and Live Activity widgets are in `privacyLiveActivity/`. Product docs and design references live in `docs/` and `design-image/`. CloudKit schema automation is under `tools/cloudkit/`.

## Build, Test, and Development Commands

Use Xcode or `xcodebuild` from the repository root.

```bash
xcodebuild -project privacy.xcodeproj -scheme privacy -destination 'generic/platform=iOS Simulator' build
xcodebuild -project privacy.xcodeproj -scheme privacy -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
bash tools/cloudkit/deploy-schema.sh development validate
bash tools/cloudkit/deploy-schema.sh production import
```

The first command compiles the app for simulator. The second runs unit and UI tests. The CloudKit commands validate or deploy the versioned schema in `tools/cloudkit/privacy-cloudkit.schema`.

## Coding Style & Naming Conventions

Follow existing Swift conventions: four-space indentation, `UpperCamelCase` for types, `lowerCamelCase` for properties/functions, and small focused SwiftUI views. Keep shared behavior in service/store types such as `VaultStore`, `ImportService`, and `CloudKitSyncService`. Use `L.string` / `L.format` for user-facing copy and update relevant `.lproj` files when adding visible text.

## Testing Guidelines

Tests use Swift Testing in `privacyTests/privacyTests.swift` and XCTest UI tests in `privacyUITests/`. Add focused tests for pure policies, formatting, sync descriptors, and import behavior. Prefer deterministic unit tests over simulator-only UI checks when possible. Name tests by behavior, for example `vaultImportProgressReportsSelectedImportedAndFailedCounts`.

## Commit & Pull Request Guidelines

Recent commits use concise, imperative summaries such as `Refine import and media preview flow`. Keep commits scoped and avoid unrelated formatting churn. Do not add `Co-Authored-By` trailers. Pull requests should include a brief behavior summary, test commands run, screenshots for UI changes, and CloudKit schema notes when sync fields or indexes change.

## Security & Configuration Tips

Do not commit secrets, tokens, private keys, exported user data, or real vault content. CloudKit production schema is not deployed by the iOS app at runtime; use `tools/cloudkit/deploy-schema.sh` before TestFlight/App Store releases when schema changes. Preserve encrypted-at-rest behavior and never log plaintext vault metadata or decrypted media paths beyond temporary debugging.

## CloudKit Schema Source of Truth

Keep CloudKit schema changes in `tools/cloudkit/privacy-cloudkit.schema`; do not rely on Dashboard-only edits. The app uses private database record types `VaultManifest`, `VaultFolder`, `VaultItem`, and `DecoyNote`, plus CloudKit's `Users` type. All app record types must keep `___recordID REFERENCE QUERYABLE` so `CKQuery` can read records without `recordName is not marked queryable` errors.

Current schema fields:

- `VaultManifest`: `vaultId`, `schemaVersion`, `encryptedVaultName`, `encryptedRootKeyPackage`, `updatedAt`.
- `VaultFolder`: `folderId`, `encryptedName`, `sortOrder`, `updatedAt`, `deletedAt`, `localRevision`.
- `VaultItem`: `itemId`, `type`, `encryptedMetadata`, `encryptedFileKey`, `byteSize`, `assetState`, `fileAsset`, `thumbAsset`, `favorite`, `createdAt`, `updatedAt`, `deletedAt`, `localRevision`, `importFingerprint`.
- `DecoyNote`: `noteId`, `encryptedPayload`, `isPinned`, `sortOrder`, `createdAt`, `updatedAt`, `deletedAt`, `localRevision`.
- `Users`: `roles`.

Before any TestFlight or App Store release with schema changes, run:

```bash
bash tools/cloudkit/deploy-schema.sh development import
bash tools/cloudkit/deploy-schema.sh production import
```
