import UIKit

extension UIImage {
    /// Downscales and JPEG-compresses the image for upload to a vision model.
    /// ~1024 px on the long edge is plenty for food recognition and keeps requests small.
    func preparedForUpload(maxDimension: CGFloat = 1024, maxBytes: Int = 900_000) -> Data? {
        let image = resized(toMaxDimension: maxDimension)
        var quality: CGFloat = 0.8
        var data = image.jpegData(compressionQuality: quality)
        while let current = data, current.count > maxBytes, quality > 0.3 {
            quality -= 0.15
            data = image.jpegData(compressionQuality: quality)
        }
        return data
    }

    /// Returns an orientation-normalised copy no larger than `maxDimension` on its long edge.
    func resized(toMaxDimension maxDimension: CGFloat) -> UIImage {
        let longEdge = max(size.width, size.height)
        guard longEdge > 0 else { return self }
        let scale = min(1, maxDimension / longEdge)
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
