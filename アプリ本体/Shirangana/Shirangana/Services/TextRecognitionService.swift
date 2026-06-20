import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
@preconcurrency import Vision

struct TextRecognitionService: Sendable {
    enum RecognitionError: LocalizedError {
        case invalidImage
        case noTextFound

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                "画像を読み取れませんでした。"
            case .noTextFound:
                "枠の中に漢字が見つかりませんでした。"
            }
        }
    }

    func recognizeTextCandidates(in imageData: Data) async throws -> [String] {
        let variants = await imageVariants(from: imageData)
        let allCandidates = await withTaskGroup(
            of: [String].self,
            returning: [String].self
        ) { group in
            for data in variants {
                group.addTask {
                    (try? await recognizeSingleImage(data)) ?? []
                }
            }

            var combined: [String] = []
            for await candidates in group {
                for candidate in candidates where !combined.contains(candidate) {
                    combined.append(candidate)
                }
            }
            return combined
        }

        guard !allCandidates.isEmpty else {
            throw RecognitionError.noTextFound
        }
        return allCandidates
    }

    private func recognizeSingleImage(_ imageData: Data) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                var candidates: [String] = []

                for rank in 0..<5 {
                    let combined = observations.compactMap { observation -> String? in
                        let choices = observation.topCandidates(5)
                        guard rank < choices.count else { return nil }
                        return choices[rank].string
                    }.joined()
                    if !combined.isEmpty {
                        candidates.append(combined)
                    }
                }

                for observation in observations {
                    candidates.append(
                        contentsOf: observation.topCandidates(5).map(\.string)
                    )
                }

                let uniqueCandidates = candidates.reduce(into: [String]()) {
                    if !$0.contains($1) { $0.append($1) }
                }

                continuation.resume(returning: uniqueCandidates)
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP"]
            // The crop contains an isolated word, so sentence correction can turn
            // logos and proper nouns into unrelated common words.
            request.usesLanguageCorrection = false
            request.minimumTextHeight = 0.012

            let handler = VNImageRequestHandler(data: imageData)
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func imageVariants(from data: Data) async -> [Data] {
        await Task.detached(priority: .userInitiated) {
            guard let input = CIImage(data: data) else { return [data] }
            let context = CIContext(options: [.cacheIntermediates: false])
            var variants = [data]
            let longestSide = max(input.extent.width, input.extent.height)
            let scale = min(max(1400 / longestSide, 1), 4)
            let enlarged = input.transformed(
                by: CGAffineTransform(scaleX: scale, y: scale)
            )

            let contrast = CIFilter.colorControls()
            contrast.inputImage = enlarged
            contrast.saturation = 0
            contrast.contrast = 2.1
            contrast.brightness = 0.08

            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = contrast.outputImage
            sharpen.sharpness = 0.7

            if let output = sharpen.outputImage,
               let jpeg = context.jpegRepresentation(
                   of: output,
                   colorSpace: CGColorSpaceCreateDeviceGray(),
                   options: [
                       kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.96
                   ]
               ) {
                variants.append(jpeg)
            }

            let grayscale = CIFilter.colorControls()
            grayscale.inputImage = enlarged
            grayscale.saturation = 0
            grayscale.contrast = 1.25

            let blurred = grayscale.outputImage?
                .clampedToExtent()
                .applyingFilter(
                    "CIGaussianBlur",
                    parameters: [kCIInputRadiusKey: 22]
                )
                .cropped(to: enlarged.extent)

            let normalized = grayscale.outputImage?.applyingFilter(
                "CIDivideBlendMode",
                parameters: [kCIInputBackgroundImageKey: blurred as Any]
            )

            let localContrast = CIFilter.colorControls()
            localContrast.inputImage = normalized
            localContrast.saturation = 0
            localContrast.contrast = 4.2
            localContrast.brightness = -0.05

            if let output = localContrast.outputImage,
               let jpeg = context.jpegRepresentation(
                   of: output,
                    colorSpace: CGColorSpaceCreateDeviceGray(),
                   options: [
                       kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.96
                   ]
            ) {
                variants.append(jpeg)
            }

            if let normalized,
               let threshold = CIFilter(
                   name: "CIColorThreshold",
                   parameters: [
                       kCIInputImageKey: normalized,
                       "inputThreshold": 0.72,
                   ]
               )?.outputImage,
               let jpeg = context.jpegRepresentation(
                   of: threshold,
                   colorSpace: CGColorSpaceCreateDeviceGray(),
                   options: [
                       kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 1.0
                   ]
               ) {
                variants.append(jpeg)
            }

            return variants
        }.value
    }
}
