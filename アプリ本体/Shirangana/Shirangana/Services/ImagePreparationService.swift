import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ImagePreparationService: Sendable {
    enum PreparationError: LocalizedError {
        case invalidImage
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                "撮影した画像を読み込めませんでした。"
            case .encodingFailed:
                "撮影した画像を準備できませんでした。"
            }
        }
    }

    func prepareForCropping(_ data: Data) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                throw PreparationError.invalidImage
            }

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2400,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
            ) else {
                throw PreparationError.invalidImage
            }

            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(
                output,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            ) else {
                throw PreparationError.encodingFailed
            }
            CGImageDestinationAddImage(
                destination,
                image,
                [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary
            )
            guard CGImageDestinationFinalize(destination) else {
                throw PreparationError.encodingFailed
            }
            return output as Data
        }.value
    }
}
