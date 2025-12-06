import SwiftUI
import PhotosUI

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    var sourceType: UIImagePickerController.SourceType = .photoLibrary

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        picker.allowsEditing = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.image = editedImage
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.image = originalImage
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct PhotosPicker: View {
    @Binding var selectedImage: UIImage?
    @State private var showingImagePicker = false
    @State private var showingSourceOptions = false
    @State private var sourceType: UIImagePickerController.SourceType = .photoLibrary

    var body: some View {
        Button(action: {
            showingSourceOptions = true
        }) {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 2))
            } else {
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 120, height: 120)
                    VStack {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.gray)
                        Text("Add Photo")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .confirmationDialog("Choose Image Source", isPresented: $showingSourceOptions, titleVisibility: .visible) {
            Button("Photo Library") {
                sourceType = .photoLibrary
                showingImagePicker = true
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Camera") {
                    sourceType = .camera
                    showingImagePicker = true
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(image: $selectedImage, sourceType: sourceType)
        }
    }
}
