# Budget Calendar Native

Native macOS successor for Budget Calendar, targeting macOS 14 and later.

This repository is intentionally separate from the Electron application. It opens the same database used by the released Electron app:

`~/Library/Application Support/Budget Calendar/budget.sqlite`

The schema and `PRAGMA user_version` migration history are compatibility contracts. The native app uses GRDB.swift for typed access, preserves integer-cent amounts and local `YYYY-MM-DD` dates, and never silently creates a second data store under a different bundle identifier.

## Local development

```sh
swift test
swift run BudgetCalendarApp
```

Build an unsigned local `.app` for manual macOS testing:

```sh
./Scripts/build-development-app.sh
open "dist/Budget Calendar Native.app"
```

The script makes `dist/Budget Calendar Native.app` from the release executable. It deliberately does not sign, notarize, publish, or install the app. macOS 14 or later is required.

## Unsigned preview downloads and Gatekeeper

The preview release identifier is recorded in [`VERSION`](VERSION); the numeric macOS marketing version is in [`MARKETING_VERSION`](MARKETING_VERSION). Before opening a downloaded preview, verify that its GitHub Release tag matches the preview identifier and check the accompanying `.sha256` file.

macOS Gatekeeper will warn because the preview is not signed or notarized. To open an app you intentionally downloaded from this repository:

1. In Finder, Control-click **Budget Calendar Native.app** and choose **Open**.
2. Confirm **Open** in the next dialog. If macOS instead blocks it, open **System Settings → Privacy & Security** and choose **Open Anyway** for this specific app.
3. Do not disable Gatekeeper globally, remove quarantine attributes with Terminal commands, or bypass the warning for an app from an untrusted source.

The preview has no automatic updates. Delete the old app and download a later GitHub Release when you choose to update. Signing, notarization, and public-release automation are intentionally deferred.

See [RELEASE.md](RELEASE.md) for the pre-release checklist. Do not publish a download until its `swift test`, package build, and copied-database manual check have passed.

## Shared-data safety

Only one app should write the shared database at a time. The native persistence layer takes an advisory lock, enables SQLite foreign keys/WAL, runs an integrity check before migrations, validates the schema, and refuses unsupported future schema versions.

Before testing a build against real data:

1. Close the Electron app.
2. Use Settings → **Copy backup now**, or copy `budget.sqlite` together with any `-wal` and `-shm` sidecars.
3. Open the native app and verify the database path in Settings.

If startup reports a corrupt or unreadable database, use **Restore SQLite backup…**. The app stages and validates the selected backup before replacing the active data and preserves the old database (including WAL/SHM sidecars) beside it as `budget-before-restore-<timestamp>.sqlite`.

The bundle identifier is intentionally separate from Electron, but the app always uses the explicit shared database path above; it never derives a second database location from the bundle identifier.

## Verification

Run the native XCTest suite when the local Swift toolchain and macOS SDK versions match:

```sh
swift test
```

For source-only validation when an SDK/toolchain mismatch prevents package compilation:

```sh
swiftc -parse Sources/BudgetCalendarCore/*.swift
swiftc -parse Sources/BudgetCalendarApp/BudgetCalendarApp.swift
```

The Electron app remains the behavioral reference during the native port. Test migrations and UI flows against a copied database before any release packaging.
