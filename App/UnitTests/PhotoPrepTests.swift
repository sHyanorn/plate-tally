import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import PlateTally

@MainActor @Suite struct PhotoPrepTests {
    /// A flat picture of the given size in pixels, drawn at the given screen scale.
    private func picture(width: Int, height: Int, scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let size = CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale)
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    @Test func aLargePhotoGetsAThousandAndTwentyFourPixelsOnTheLongSide() throws {
        let photo = try PhotoPrep.photo(from: picture(width: 3000, height: 2000))
        #expect(photo.jpeg.width == 1024)
        #expect(photo.jpeg.height == 682)
    }

    @Test func aPortraitPhotoIsScaledOnItsHeight() throws {
        let photo = try PhotoPrep.photo(from: picture(width: 2000, height: 3000))
        #expect(photo.jpeg.width == 682)
        #expect(photo.jpeg.height == 1024)
    }

    @Test func aPhotoThatIsSmallEnoughIsNotEnlarged() throws {
        let photo = try PhotoPrep.photo(from: picture(width: 800, height: 600))
        #expect(photo.jpeg.width == 800)
        #expect(photo.jpeg.height == 600)
    }

    /// An image of 400 x 300 points at a scale of 3 has 1,200 x 900 pixels.
    @Test func pixelsCountAndPointsDoNot() throws {
        let photo = try PhotoPrep.photo(from: picture(width: 1200, height: 900, scale: 3))
        #expect(photo.jpeg.width == 1024)
        #expect(photo.jpeg.height == 768)
    }

    /// A phone held upright stores a landscape bitmap with the orientation `.right`. Here the stored bitmap is red
    /// on its left half and blue on its right: turned a quarter, the border runs across the photo; stretched
    /// into the box without turning, it would run down it.
    @Test func theOrientationTurnsThePixels() throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let stored = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 200), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 150, height: 200))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 150, y: 0, width: 150, height: 200))
        }
        let turned = UIImage(cgImage: try #require(stored.cgImage), scale: 1, orientation: .right)
        let pixels = try #require(try PhotoPrep.photo(from: turned).thumbnail.cgImage)
        #expect(pixels.width == 200 && pixels.height == 300)

        let context = try #require(
            CGContext(
                data: nil, width: 200, height: 300, bitsPerComponent: 8, bytesPerRow: 800,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(pixels, in: CGRect(x: 0, y: 0, width: 200, height: 300))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        func isRed(x: Int, y: Int) -> Bool { bytes[(y * 200 + x) * 4] > 128 }
        #expect(isRed(x: 20, y: 20) == isRed(x: 180, y: 20))
        #expect(isRed(x: 20, y: 280) == isRed(x: 180, y: 280))
        #expect(isRed(x: 100, y: 20) != isRed(x: 100, y: 280))
    }

    /// The picture carries Exif with a time, a position and a device, as one from a camera does.
    @Test func theSentBytesCarryNoExifOfThePicture() throws {
        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        let metadata: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:11:23 12:30:00"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 33.87, kCGImagePropertyGPSLatitudeRef: "S"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "Probe"],
        ]
        CGImageDestinationAddImage(
            destination, try #require(picture(width: 640, height: 480).cgImage), metadata as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let input = data as Data
        #expect(input.range(of: Data("Exif".utf8)) != nil)

        let photo = try PhotoPrep.photo(from: try #require(UIImage(data: input)))
        #expect(photo.jpeg.bytes.range(of: Data("Exif".utf8)) == nil)
        #expect(photo.jpeg.bytes.range(of: Data("Probe".utf8)) == nil)
        #expect(photo.jpeg.bytes.starts(with: [0xFF, 0xD8]))
    }

    @Test func theThumbnailShowsTheSentPhoto() throws {
        let photo = try PhotoPrep.photo(from: picture(width: 3000, height: 2000))
        #expect(photo.thumbnail.size == CGSize(width: 1024, height: 682))
    }
}
