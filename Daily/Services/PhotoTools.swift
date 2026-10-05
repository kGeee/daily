import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// Shrinks photos before saving so the journal stays small. Works from image data with ImageIO,
/// so it's the same on iPhone and Mac (and respects the photo's orientation).
enum ImageTools {
    /// A CGImage no bigger than `maxDimension` on its long side, upright.
    static func cgImage(from data: Data, maxDimension: CGFloat? = nil) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        if let maxDimension { options[kCGImageSourceThumbnailMaxPixelSize] = Int(maxDimension) }
        if maxDimension == nil, let full = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            // Full size: still go through the thumbnail path so orientation is applied.
            options[kCGImageSourceThumbnailMaxPixelSize] = max(full.width, full.height)
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func jpeg(_ image: CGImage, quality: CGFloat) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    /// JPEG no bigger than 1600px on its long side.
    static func jpeg(fromData data: Data, maxDimension: CGFloat = 1600, quality: CGFloat = 0.75) -> Data? {
        cgImage(from: data, maxDimension: maxDimension).flatMap { jpeg($0, quality: quality) }
    }

    /// A smaller copy to send to the AI (plenty to read a plate, and cheaper).
    static func forAI(_ data: Data) -> Data? {
        jpeg(fromData: data, maxDimension: 1024, quality: 0.7)
    }

    #if canImport(UIKit)
    /// For camera shots, which arrive as a UIImage.
    static func jpeg(from image: UIImage, maxDimension: CGFloat = 1600, quality: CGFloat = 0.75) -> Data? {
        let size = image.size
        let longSide = max(size.width, size.height)
        guard longSide > 0 else { return nil }
        let scale = min(1, maxDimension / longSide)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
    #endif
}

#if canImport(UIKit)
/// The camera, wrapped for SwiftUI. Falls back to nothing on devices without one (the simulator).
struct CameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onImage: (UIImage) -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}
#else
/// No camera picker on the Mac; photos come from the library or a dropped file.
enum CameraPicker {
    static var isAvailable: Bool { false }
}
#endif

/// A photo from saved data, shrunk to a thumbnail once it's loaded.
struct PhotoThumbnail: View {
    let data: Data
    var maxPixel: CGFloat = 400

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Palette.card2)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(Palette.faint)
            }
        }
        .clipped()
        .task(id: data.count) {
            image = ImageTools.cgImage(from: data, maxDimension: maxPixel)
        }
    }
}

/// "Take a photo" / "From library" buttons that hand back a saved-size JPEG.
struct PhotoSourceButtons: View {
    var tint: Color = Palette.focus
    var compact = false
    let onPhoto: (Data) -> Void

    @State private var showCamera = false
    @State private var libraryItem: PhotosPickerItem?

    var body: some View {
        HStack(spacing: 10) {
            if CameraPicker.isAvailable {
                Button {
                    showCamera = true
                } label: {
                    label("Take a photo", symbol: "camera.fill", filled: true)
                }
                .buttonStyle(.plain)
            }
            PhotosPicker(selection: $libraryItem, matching: .images) {
                label(CameraPicker.isAvailable ? "From library" : "Add a photo", symbol: "photo.on.rectangle",
                      filled: !CameraPicker.isAvailable)
            }
            .buttonStyle(.plain)
        }
        #if canImport(UIKit)
        .fullScreenSheet(isPresented: $showCamera) {
            CameraPicker(isPresented: $showCamera) { image in
                if let data = ImageTools.jpeg(from: image) { onPhoto(data) }
            }
            .ignoresSafeArea()
        }
        #endif
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                if let raw = try? await item.loadTransferable(type: Data.self), let data = ImageTools.jpeg(fromData: raw) {
                    onPhoto(data)
                }
                libraryItem = nil
            }
        }
    }

    private func label(_ title: String, symbol: String, filled: Bool) -> some View {
        Label(title, systemImage: symbol)
            .font((compact ? Font.caption : Font.subheadline).weight(.bold))
            .foregroundStyle(filled ? Palette.onAccent : Palette.ink)
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 36 : 44)
            .background(filled ? tint : Palette.card2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
