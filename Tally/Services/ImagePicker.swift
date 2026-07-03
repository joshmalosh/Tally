import SwiftUI
import PhotosUI
import AVFoundation
import UIKit

/// Custom camera capture — deliberately bypasses UIImagePickerController's built-in
/// "Retake / Use Photo" confirmation screen. A shutter press hands the photo straight
/// back to the caller (which shows its own edit/review screen), removing a full extra
/// step from "photo receipt" → "expense logged".
struct CameraPicker: View {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = ReceiptCameraController()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if camera.authorizationState == .authorized {
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
            } else if camera.authorizationState == .denied || camera.authorizationState == .restricted {
                permissionDeniedView
            }

            VStack {
                HStack {
                    closeButton
                    Spacer()
                }
                Spacer()
                if camera.authorizationState == .authorized {
                    shutterButton
                }
            }
        }
        .statusBarHidden()
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(14)
                .background(Circle().fill(Color.black.opacity(0.35)))
        }
        .padding(.leading, 16)
        .padding(.top, 8)
    }

    private var shutterButton: some View {
        Button {
            camera.capturePhoto { captured in
                image = captured
                dismiss()
            }
        } label: {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: 74, height: 74)
                Circle()
                    .fill(Color.white)
                    .frame(width: 60, height: 60)
            }
        }
        .padding(.bottom, 36)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.8))
            Text("Camera access is off")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
            Text("Enable camera access in Settings to take a photo of your receipt.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.top, 4)
        }
    }
}

private final class ReceiptCameraController: NSObject, ObservableObject {
    enum AuthState {
        case notDetermined, authorized, denied, restricted
    }

    @Published private(set) var authorizationState: AuthState = .notDetermined

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.asimplelife.tally.cameraSession")
    private let photoOutput = AVCapturePhotoOutput()
    private var isConfigured = false
    private var captureCompletion: ((UIImage?) -> Void)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            authorizationState = .authorized
            configureAndStartSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.authorizationState = .authorized
                        self.configureAndStartSession()
                    } else {
                        self.authorizationState = .denied
                    }
                }
            }
        case .restricted:
            authorizationState = .restricted
        case .denied:
            authorizationState = .denied
        @unknown default:
            authorizationState = .denied
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configureAndStartSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo

                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                   let input = try? AVCaptureDeviceInput(device: device),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                if self.session.canAddOutput(self.photoOutput) {
                    self.session.addOutput(self.photoOutput)
                }
                self.session.commitConfiguration()
                self.isConfigured = true
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    /// Receipts are almost always shot holding the phone upright, so the capture
    /// connection is locked to portrait rather than tracking device rotation —
    /// avoids sideways/upside-down photos without needing full orientation plumbing.
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        captureCompletion = completion
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if let connection = self.photoOutput.connection(with: .video), connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension ReceiptCameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        DispatchQueue.main.async { [weak self] in
            self?.captureCompletion?(image)
            self?.captureCompletion = nil
        }
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        if let connection = view.videoPreviewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
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
