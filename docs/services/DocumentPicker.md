## Purpose

`UIViewControllerRepresentable` wrapper around `UIDocumentPickerViewController` for picking a receipt file (PDF or image) from Files.

## Public surface

- `struct DocumentPicker: UIViewControllerRepresentable` (`Tally/Services/DocumentPicker.swift:4`)
- `@Binding var selectedFileURL: URL?`, `@Binding var selectedImage: UIImage?` (`:5-6`) — outputs; PDFs set `selectedFileURL` only, images set both (image decoded eagerly) or fall back to `selectedFileURL` if decoding fails.

## Depends on

`UIKit`'s `UIDocumentPickerViewController`, `UniformTypeIdentifiers` (`.pdf, .image, .jpeg, .png, .heic`).

## Used by

- `Tally/Views/AddExpense/AddExpenseView.swift` (only call site found).

## Gotchas

- Single-selection only (`allowsMultipleSelection = false`); opens files as copies (`asCopy: true`).
- Cancel and pick both dismiss via `@Environment(\.dismiss)`.
