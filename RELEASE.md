# Unsigned preview release checklist

This repository can publish an unsigned preview only after it builds and tests successfully on a matching macOS toolchain.

1. Confirm the working tree is clean and `swift test` passes.
2. Run `./Scripts/build-development-app.sh` and launch the generated app against a copied real database.
3. Verify Calendar, recurring edits, CSV import/export, backup/restore, paycheck assignment, and first-run setup.
4. Create a metadata-preserving ZIP without re-signing it:

   ```sh
   ditto -c -k --sequesterRsrc --keepParent "dist/Budget Calendar Native.app" "BudgetCalendarNative-v$(cat VERSION).zip"
   shasum -a 256 "BudgetCalendarNative-v$(cat VERSION).zip" > "BudgetCalendarNative-v$(cat VERSION).zip.sha256"
   ```
5. Create annotated tag `v$(cat VERSION)` and a **pre-release** GitHub Release containing the ZIP, its `.sha256` checksum, release notes, supported macOS version (14+), and the shared-database warning.
6. State clearly that the build is unsigned and follows the Gatekeeper instructions in the README. Do not claim notarization or automatic updates.

Do not publish a release if tests or the manual copied-database check fail. A normal public release requires Developer ID signing, notarization, and a repeatable CI build first.
