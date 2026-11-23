import Core
import Estimation
import UIKit

/// The photo that goes to the model, and a copy of those bytes for the screen.
struct Photo: Identifiable {
    let id = UUID()
    let jpeg: JPEGImage
    let thumbnail: UIImage
}

struct PhotoError: PlateError {
    let what: String
    let expected: String
    let saw: String
}

/// Turns a camera or library picture into the JPEG of R2 and R3.
@MainActor
enum PhotoPrep {
    /// Not measured against the evaluation, which sent PNG.
    private static let quality: CGFloat = 0.8

    static func photo(from image: UIImage) throws(Problem) -> Photo {
        // The size is in points, so the screen scale of the picture turns it into pixels.
        let width = image.size.width * image.scale
        let height = image.size.height * image.scale
        let longSide = max(width, height)
        guard longSide >= 1 else {
            throw Problem(
                PhotoError(
                    what: "the photo has no pixels", expected: "an image of at least 1 px",
                    saw: "\(Int(width)) x \(Int(height)) px"))
        }
        // Multiply first, then divide, so the long side comes out as exactly 1024. A photo that is
        // small enough is not enlarged (R2).
        let target = min(longSide, CGFloat(JPEGImage.maxLongSide))
        let size = CGSize(
            width: max(1, (width * target / longSide).rounded(.down)),
            height: max(1, (height * target / longSide).rounded(.down)))

        // A scale of 1 makes one point one pixel. The default is the screen scale, which would triple the size.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        // Drawing applies the orientation of the picture, so the pixels come out upright.
        let data = UIGraphicsImageRenderer(size: size, format: format).jpegData(withCompressionQuality: quality) { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        // The check removes every segment that could hold a location, a time or a device (R3).
        let jpeg: JPEGImage
        do throws(JPEGError) {
            jpeg = try JPEGImage(encoded: data)
        } catch {
            throw Problem(error)
        }
        guard let thumbnail = UIImage(data: jpeg.bytes) else {
            throw Problem(
                PhotoError(
                    what: "the encoded photo cannot be shown", expected: "JPEG bytes that decode",
                    saw: "\(jpeg.bytes.count) bytes"))
        }
        return Photo(jpeg: jpeg, thumbnail: thumbnail)
    }
}
