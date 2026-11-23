import Testing
import UIKit

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

    /// A phone held upright stores a landscape image with the orientation `.right`.
    @Test func theOrientationIsAppliedToThePixels() throws {
        let stored = try #require(picture(width: 300, height: 200).cgImage)
        let turned = UIImage(cgImage: stored, scale: 1, orientation: .right)
        #expect(turned.size == CGSize(width: 200, height: 300))
        let photo = try PhotoPrep.photo(from: turned)
        #expect(photo.jpeg.width == 200)
        #expect(photo.jpeg.height == 300)
    }

    @Test func theSentBytesCarryNoExifSegment() throws {
        let photo = try PhotoPrep.photo(from: picture(width: 640, height: 480))
        #expect(photo.jpeg.bytes.range(of: Data("Exif".utf8)) == nil)
        #expect(photo.jpeg.bytes.starts(with: [0xFF, 0xD8]))
    }

    @Test func theThumbnailShowsTheSentPhoto() throws {
        let photo = try PhotoPrep.photo(from: picture(width: 3000, height: 2000))
        #expect(photo.thumbnail.size == CGSize(width: 1024, height: 682))
    }
}
