import Foundation

// ARCHIVED: API service is no longer used.
// All data storage is handled by SwiftData + CloudKit (iCloud).
// This file is kept as a stub to avoid Xcode project file edits.
// Safe to delete when cleaning up the project file.

struct APIError: LocalizedError {
    let code: String
    let message: String
    var errorDescription: String? { message }
}
