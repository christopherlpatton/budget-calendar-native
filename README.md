# Budget Calendar Native

Native macOS successor for Budget Calendar, targeting macOS 14 and later.

This repository is intentionally separate from the Electron application. It opens the same database used by the released Electron app:

`~/Library/Application Support/Budget Calendar/budget.sqlite`

The schema and `PRAGMA user_version` migration history are compatibility contracts. The native app uses GRDB.swift for typed access, preserves integer-cent amounts and local `YYYY-MM-DD` dates, and never silently creates a second data store under a different bundle identifier.

## Development

```sh
swift test
swift run BudgetCalendarApp
```

Only one app should write the shared database at a time. The native persistence layer takes an advisory lock and validates the schema before opening. Always work against a copied database when testing migrations.

The first implementation milestone contains the persistence/domain foundation and test fixtures. UI features are being added behind the same service protocols so the Electron app remains the behavioral reference.
