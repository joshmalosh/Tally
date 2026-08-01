## Purpose

Stub file. A comment at the top says the API service is archived — all data storage now goes through SwiftData + CloudKit — and the file is kept only so the Xcode project file doesn't need editing. `Tally/Services/APIService.swift:1`.

## Public surface

- `struct APIError: LocalizedError` (`Tally/Services/APIService.swift:8`) — `code: String`, `message: String`, `errorDescription` returns `message`.

## Depends on

Nothing beyond `Foundation`.

## Used by

No call sites found elsewhere in `Tally/` — `APIError` is unreferenced outside this file.

## Gotchas

- Explicitly archived/dead code per the file's own header comment; safe to delete when the project is cleaned up.
