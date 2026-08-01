## Purpose

Two SwiftUI capture surfaces for getting a receipt image: a custom camera view (`CameraPicker`) and a photo-library picker (`PhotosPicker`) that supports multi-select.

## Public surface

- `struct CameraPicker: View` (`Tally/Services/ImagePicker.swift:10`) — `@Binding var image: UIImage?`. Full-screen custom camera UI; a shutter tap hands the captured photo straight back (no built-in retake/confirm screen).
- `struct PhotosPicker: UIViewControllerRepresentable` (`:221`) — `@Binding var image: UIImage?`, `var onCancel: (() -> Void)?`, `var onMultipleImages: (([UIImage]) -> Void)? = nil`. Wraps `PHPickerViewController` with unlimited selection; routes >1 selected photo to `onMultipleImages` if provided, else falls back to single-image behaviour.

## Depends on

`AVFoundation` (`AVCaptureSession`/`AVCapturePhotoOutput` for the custom camera), `PhotosUI` (`PHPickerViewController`), `SwiftUI`, `UIKit`.

## Used by

- `Tally/Views/AddExpense/AddExpenseView.swift` — only call site for both `CameraPicker(...)` and `PhotosPicker(...)`.

## Gotchas

- `CameraPicker` deliberately bypasses `UIImagePickerController`'s "Retake / Use Photo" confirmation to save a step — comment at `:6-9`.
- Capture connection is hard-locked to `.portrait` orientation (`:171-173`) since receipts are shot holding the phone upright; not adaptive to device rotation.
- Camera permission states (`notDetermined`/`authorized`/`denied`/`restricted`) are tracked in a private `ReceiptCameraController`; denied/restricted shows an in-view "Open Settings" prompt rather than a system alert.
- `PhotosPicker`'s multi-image path loads items concurrently via `DispatchGroup` + `NSLock`, and re-sorts by original index before calling `onMultipleImages` — order is preserved despite concurrent loads.
