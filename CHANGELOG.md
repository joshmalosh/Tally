# Changelog

All notable changes to the Tally iOS app will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Changelog system for tracking Tally iOS changes

### Changed
- Export flow: pass selected expenses via `.sheet(item:)` with `ExportWithSelectionItem` — fixes selection not reaching `GlobalExportSheet`
- App bar / FAB: always show app bar (with Export icon) during multi-select; add-entry FAB only when not selecting
- Bulk import: unified regex `^(.*?)\s*:?\s*\$?([\d,]+\.?\d*)\s*$` finds last numeric token on any line (with or without colon)

### Fixed
- Export sheet showing "All Time" and wrong count when 2 expenses selected — selection now passed reliably
- Bulk import parsing lines like `Mouse/Keyboard 88.99999999` (no colon) — was splitting on decimal, now extracts description + amount correctly

### Security
- (Nothing yet)

---

## [0.1.0] - 2026-03-21

### Added
- Initial Tally iOS app structure
- SwiftUI + SwiftData + CloudKit architecture
- Expense capture, tagging, and export (CSV, PDF)
- Receipt upload and OCR auto-fill (Pro)
- iCloud sync for user data
- Free tier: unlimited expenses, 1 CSV export/month, banner ads
- Pro subscription ($4.99/mo): unlimited exports, no ads, OCR, advanced filters
- Design system: light mode, warm neutral (#F6F5F3), forest green (#346049)
- Domain logic: ExpenseCalculations, ExpenseTypes, TagColors
- Views: Home, AddExpense, ExpenseDetail, Export, Settings, Onboarding

### Changed
- (Initial release)

### Fixed
- (Initial release)

### Security
- User data stored entirely in user's iCloud — no proprietary backend

[Unreleased]: https://github.com/joshmalosh/Tally/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/joshmalosh/Tally/releases/tag/v0.1.0
