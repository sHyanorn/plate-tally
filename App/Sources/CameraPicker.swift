import Core
import SwiftUI
import UIKit

/// The system camera. The photo library has its own picker and needs no permission.
struct CameraPicker: UIViewControllerRepresentable {
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    let onImage: (UIImage) -> Void
    let onFailure: (Problem) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onFailure: onFailure, onCancel: onCancel)
    }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        let onFailure: (Problem) -> Void
        let onCancel: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onFailure: @escaping (Problem) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onFailure = onFailure
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else {
                onFailure(
                    Problem(
                        PhotoError(
                            what: "the camera gave no image", expected: "a photo under the key originalImage",
                            saw: "the keys \(info.keys.map(\.rawValue).sorted().joined(separator: ", "))")))
                return
            }
            onImage(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
