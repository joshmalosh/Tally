import SwiftUI
import PhotosUI

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct PhotosPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var onCancel: (() -> Void)?
    /// Called instead of setting `image` when the user picks more than one photo.
    /// When nil, extra photos are discarded (backward-compatible behaviour).
    var onMultipleImages: (([UIImage]) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.selectionLimit = 0
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotosPicker

        init(_ parent: PhotosPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                parent.onCancel?()
                parent.dismiss()
                return
            }

            // Multiple photos selected and caller supports it → route to batch handler
            if results.count > 1, let multiHandler = parent.onMultipleImages {
                let lock = NSLock()
                var orderedImages = [Int: UIImage]()
                let group = DispatchGroup()

                for (index, result) in results.enumerated() {
                    guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else { continue }
                    group.enter()
                    result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                        if let uiImage = object as? UIImage {
                            lock.lock()
                            orderedImages[index] = uiImage
                            lock.unlock()
                        }
                        group.leave()
                    }
                }

                group.notify(queue: .main) {
                    let sorted = orderedImages.sorted { $0.key < $1.key }.map(\.value)
                    if !sorted.isEmpty { multiHandler(sorted) }
                    self.parent.dismiss()
                }
                return
            }

            // Single image (or multi not handled) — original behaviour
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else {
                parent.onCancel?()
                parent.dismiss()
                return
            }
            provider.loadObject(ofClass: UIImage.self) { image, _ in
                DispatchQueue.main.async {
                    self.parent.image = image as? UIImage
                    self.parent.dismiss()
                }
            }
        }
    }
}
