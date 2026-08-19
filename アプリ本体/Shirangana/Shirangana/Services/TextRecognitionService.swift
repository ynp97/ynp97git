import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import Foundation
@preconcurrency import Vision

struct TextRecognitionService: Sendable {
    private static let maximumOCRVariants = 10
    private static let maximumCandidatesPerVariant = 5

    private static let customWords = [
        "漢字",
        "問題項目",
        "一部",
        "部分",
        "一部分",
        "場合",
        "形",
        "値",
        "御国",
        "御言葉",
        "御心",
        "御霊",
        "聖霊",
        "福音",
        "救い",
        "恵み",
        "赦し",
        "悔い改め",
        "復活",
        "契約",
        "旧約聖書",
        "異邦人",
        "神殿",
        "十字架",
        "受動分詞",
        "強意語",
        "本文",
        "引照個所",
        "引照箇所",
        "差別表現",
        "差別表現以外",
        "池田亮司",
        "池田",
        "重大",
        "出身地",
        "高群逸枝",
        "学級",
        "新聞",
        "学級新聞",
        "身長",
        "身体",
        "体",
    ]

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
        let diagnostic = await recognizeDiagnostics(in: imageData)
        let allCandidates = diagnostic.allOCRCandidates
        guard !allCandidates.isEmpty else {
            throw RecognitionError.noTextFound
        }
        return allCandidates
    }

    func recognizeDiagnostics(in imageData: Data) async -> RecognitionDiagnostic {
        let variants = await imageVariants(from: imageData)
        var diagnosedVariants: [RecognitionVariantDiagnostic] = []
        diagnosedVariants.reserveCapacity(variants.count)
        var combinedCandidates: [String] = []

        for variant in variants {
            guard !Task.isCancelled else { break }
            let candidates = (try? await recognizeSingleImage(variant.data)) ?? []
            for candidate in candidates where !combinedCandidates.contains(candidate) {
                combinedCandidates.append(candidate)
            }
            diagnosedVariants.append(
                RecognitionVariantDiagnostic(
                    name: variant.name,
                    imageData: variant.data,
                    candidates: candidates
                )
            )
            if diagnosedVariants.count >= 3,
               Self.hasUsefulJapaneseCandidate(combinedCandidates) {
                break
            }
        }

        return RecognitionDiagnostic(
            variants: diagnosedVariants,
            dictionaryCandidates: []
        )
    }

    private func recognizeSingleImage(_ imageData: Data) async throws -> [String] {
        var combinedCandidates: [String] = []

        let attempts: [(VNRequestTextRecognitionLevel, [String]?, Bool, CGFloat?)] = [
            (.accurate, ["ja-JP"], false, nil),
        ]

        for attempt in attempts {
            try Task.checkCancellation()
            let candidates = (try? await recognizeSingleImage(
                imageData,
                recognitionLevel: attempt.0,
                recognitionLanguages: attempt.1,
                automaticallyDetectsLanguage: attempt.2,
                minimumTextHeight: attempt.3
            )) ?? []
            for candidate in candidates where !combinedCandidates.contains(candidate) {
                combinedCandidates.append(candidate)
            }
            if Self.hasUsefulJapaneseCandidate(combinedCandidates) {
                break
            }
        }

        return Array(combinedCandidates.prefix(Self.maximumCandidatesPerVariant))
    }

    private static func hasUsefulJapaneseCandidate(_ candidates: [String]) -> Bool {
        candidates.contains { candidate in
            let scalars = Array(candidate.unicodeScalars)
            let ideographCount = scalars.filter(\.properties.isIdeographic).count
            let kanaCount = scalars.filter(Self.isKanaOrJapaneseMark).count
            let noiseCount = scalars.filter { scalar in
                !scalar.properties.isIdeographic
                    && !Self.isKanaOrJapaneseMark(scalar)
                    && !CharacterSet.whitespacesAndNewlines.contains(scalar)
            }.count
            guard noiseCount == 0 || noiseCount * 5 <= max(scalars.count, 1) else {
                return false
            }
            return ideographCount >= 3
                || (ideographCount >= 1 && kanaCount >= 1)
        }
    }

    private static func isKanaOrJapaneseMark(_ scalar: UnicodeScalar) -> Bool {
        (0x3040...0x30FF).contains(Int(scalar.value))
            || scalar.value == 0x3005
            || scalar.value == 0x3006
            || scalar.value == 0x3007
    }

    private func recognizeSingleImage(
        _ imageData: Data,
        recognitionLevel: VNRequestTextRecognitionLevel,
        recognitionLanguages: [String]?,
        automaticallyDetectsLanguage: Bool,
        minimumTextHeight: CGFloat?
    ) async throws -> [String] {
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

                continuation.resume(
                    returning: Array(uniqueCandidates.prefix(Self.maximumCandidatesPerVariant))
                )
            }

            request.recognitionLevel = recognitionLevel
            request.customWords = Self.customWords
            if let recognitionLanguages {
                request.recognitionLanguages = recognitionLanguages
            }
            if #available(iOS 16.0, *) {
                request.automaticallyDetectsLanguage = automaticallyDetectsLanguage
            }
            // The crop contains an isolated word, so sentence correction can turn
            // logos and proper nouns into unrelated common words.
            request.usesLanguageCorrection = false
            if let minimumTextHeight {
                request.minimumTextHeight = Float(minimumTextHeight)
            }

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

    private func imageVariants(from data: Data) async -> [(name: String, data: Data)] {
        await Task.detached(priority: .userInitiated) {
            guard let input = CIImage(data: data) else {
                return [(name: "枠内画像", data: data)]
            }
            let longestSide = max(input.extent.width, input.extent.height)
            let scale = min(max(1200 / longestSide, 1), 3)
            let enlarged = input.transformed(
                by: CGAffineTransform(scaleX: scale, y: scale)
            )
            let context = CIContext(options: [.cacheIntermediates: false])
            let baseData = context.jpegRepresentation(
                of: enlarged,
                colorSpace: CGColorSpaceCreateDeviceRGB(),
                options: [
                    kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.9
                ]
            ) ?? data
            var variants: [(name: String, data: Data)] = [
                (name: "枠内画像", data: baseData)
            ]

            func appendVariant(_ name: String, _ data: Data?) {
                guard let data,
                      variants.count < Self.maximumOCRVariants,
                      !variants.contains(where: { $0.name == name || $0.data == data }) else {
                    return
                }
                variants.append((name: name, data: data))
            }

            // Dictionary columns and reference books often put a solid or dotted
            // rule beside vertical text. Those long strokes can become the
            // strongest "character" in Vision. Try the centered text column
            // without the outer edges before spending the OCR budget on heavier
            // corrections.
            let ruleAvoiding = sideTrimmedImage(from: enlarged)
            if let ruleAvoiding {
                appendVariant(
                    "左右の罫線を避ける",
                    paddedJPEG(from: ruleAvoiding, context: context)
                )
                appendVariant(
                    "罫線回避・縦文字再配置",
                    verticalInkRunReflowJPEG(
                        from: ruleAvoiding,
                        context: context,
                        prefersMainColumn: true
                    )
                )
            }

            let tight = tightInkImage(from: enlarged, context: context)
                .map { scaledForOCR($0, targetLongestSide: 1200, maxScale: 4) }

            if let tight {
                appendVariant("文字だけ拡大", paddedJPEG(from: tight, context: context))
            }

            // Keep contrast variants near the front. With the old ordering, the
            // 10-variant cap was often consumed by vertical reflow variants before
            // weak printed characters ever reached this correction step.
            let contrast = CIFilter.colorControls()
            contrast.inputImage = enlarged
            contrast.saturation = 0
            contrast.contrast = 2.1
            contrast.brightness = 0.08

            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = contrast.outputImage
            sharpen.sharpness = 0.7

            if let output = sharpen.outputImage {
                appendVariant(
                    "高コントラスト",
                    context.jpegRepresentation(
                        of: output,
                        colorSpace: CGColorSpaceCreateDeviceGray(),
                        options: [
                            kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.96
                        ]
                    )
                )

                if let tightOutput = tightInkImage(from: output, context: context)
                    .map({ scaledForOCR($0, targetLongestSide: 1200, maxScale: 4) }) {
                    appendVariant("文字だけ強調", paddedJPEG(from: tightOutput, context: context))
                }
            }

            appendVariant(
                "主文字縦自動",
                verticalInkRunReflowJPEG(
                    from: enlarged,
                    context: context,
                    prefersMainColumn: true
                )
            )
            appendVariant("縦文字自動分割", verticalInkRunReflowJPEG(from: enlarged, context: context))
            if let tight {
                appendVariant(
                    "文字だけ主縦自動",
                    verticalInkRunReflowJPEG(
                        from: tight,
                        context: context,
                        prefersMainColumn: true
                    )
                )
                appendVariant("文字だけ縦自動", verticalInkRunReflowJPEG(from: tight, context: context))
            }

            let verticalCounts = Self.verticalCharacterCounts(for: enlarged.extent)
            for characterCount in verticalCounts where variants.count < Self.maximumOCRVariants {
                appendVariant(
                    "縦書き\(characterCount)分割",
                    verticalReflowJPEG(
                        from: enlarged,
                        characterCount: characterCount,
                        context: context
                    )
                )
            }
            appendVariant("余白つき拡大", paddedJPEG(from: enlarged, context: context))

            return variants
        }.value
    }

    private static func verticalCharacterCounts(for extent: CGRect) -> [Int] {
        guard extent.width > 0 else { return [] }
        let ratio = extent.height / extent.width
        if ratio >= 4.5 {
            return [3, 4, 5, 6, 8, 10]
        }
        if ratio >= 2.4 {
            return [2, 3, 4, 5, 6, 8]
        }
        if ratio >= 1.1 {
            return [2, 3, 4, 5]
        }
        if ratio >= 0.55 {
            return [2, 3, 4]
        }
        return []
    }

    private func scaledForOCR(
        _ image: CIImage,
        targetLongestSide: CGFloat,
        maxScale: CGFloat
    ) -> CIImage {
        let longestSide = max(image.extent.width, image.extent.height)
        guard longestSide > 0 else { return image }
        let scale = min(max(targetLongestSide / longestSide, 1), maxScale)
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    private func sideTrimmedImage(from image: CIImage) -> CIImage? {
        let extent = image.extent.integral
        guard extent.width > 40, extent.height > 40 else { return nil }

        // Keep the center 70%. The photographed word is placed in the center of
        // Shirangana's selection frame, while book rules usually sit near either
        // side. Do not apply this to wide horizontal crops.
        guard extent.height / extent.width >= 1.15 else { return nil }
        let inset = extent.width * 0.15
        let crop = extent.insetBy(dx: inset, dy: 0)
        guard crop.width > 20 else { return nil }
        return image.cropped(to: crop)
    }

    private func tightInkImage(from image: CIImage, context: CIContext) -> CIImage? {
        let extent = image.extent.integral
        guard extent.width > 12,
              extent.height > 12,
              let cgImage = context.createCGImage(image, from: extent) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 12, height > 12 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let bytesPerRow = width * 4
        guard let bitmap = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        bitmap.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        func luminance(at x: Int, _ y: Int) -> CGFloat {
            let offset = y * bytesPerRow + x * 4
            let red = CGFloat(pixels[offset])
            let green = CGFloat(pixels[offset + 1])
            let blue = CGFloat(pixels[offset + 2])
            return red * 0.299 + green * 0.587 + blue * 0.114
        }

        let borderStep = max(1, min(width, height) / 80)
        var borderTotal: CGFloat = 0
        var borderCount: CGFloat = 0
        for x in stride(from: 0, to: width, by: borderStep) {
            borderTotal += luminance(at: x, 0)
            borderTotal += luminance(at: x, height - 1)
            borderCount += 2
        }
        for y in stride(from: 0, to: height, by: borderStep) {
            borderTotal += luminance(at: 0, y)
            borderTotal += luminance(at: width - 1, y)
            borderCount += 2
        }

        let borderAverage = borderCount > 0 ? borderTotal / borderCount : 210
        let darkThreshold = max(55, min(165, borderAverage - 28))
        var inkXs: [Int] = []
        var inkYs: [Int] = []
        inkXs.reserveCapacity(width * height / 12)
        inkYs.reserveCapacity(width * height / 12)

        for y in 0..<height {
            for x in 0..<width where luminance(at: x, y) < darkThreshold {
                inkXs.append(x)
                inkYs.append(y)
            }
        }

        guard inkXs.count > 24 else { return nil }
        inkXs.sort()
        inkYs.sort()

        let trim = min(inkXs.count / 100, max(0, inkXs.count - 1))
        let lowerIndex = trim
        let upperIndex = max(lowerIndex, inkXs.count - trim - 1)
        let minX = inkXs[lowerIndex]
        let maxX = inkXs[upperIndex]
        let minY = inkYs[lowerIndex]
        let maxY = inkYs[upperIndex]
        let inkWidth = maxX - minX + 1
        let inkHeight = maxY - minY + 1
        guard inkWidth > 6, inkHeight > 6 else { return nil }

        let originalArea = width * height
        let inkBoxArea = inkWidth * inkHeight
        guard CGFloat(inkBoxArea) < CGFloat(originalArea) * 0.88 else {
            return nil
        }

        let padding = max(8, Int(CGFloat(max(inkWidth, inkHeight)) * 0.28))
        let cropMinX = max(0, minX - padding)
        let cropMaxX = min(width - 1, maxX + padding)
        let cropMinY = max(0, minY - padding)
        let cropMaxY = min(height - 1, maxY + padding)
        let cropRect = CGRect(
            x: cropMinX,
            y: cropMinY,
            width: cropMaxX - cropMinX + 1,
            height: cropMaxY - cropMinY + 1
        )

        guard let scannedImage = bitmap.makeImage(),
              let cropped = scannedImage.cropping(to: cropRect) else {
            return nil
        }
        return CIImage(cgImage: cropped)
    }

    private func verticalInkRunReflowJPEG(
        from image: CIImage,
        context: CIContext,
        prefersMainColumn: Bool = false
    ) -> Data? {
        let extent = image.extent.integral
        guard extent.width > 18,
              extent.height > 18,
              let cgImage = context.createCGImage(image, from: extent) else {
            return nil
        }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 18, height > 18 else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let bytesPerRow = width * 4
        guard let bitmap = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        bitmap.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        func luminance(at x: Int, _ y: Int) -> CGFloat {
            let offset = y * bytesPerRow + x * 4
            let red = CGFloat(pixels[offset])
            let green = CGFloat(pixels[offset + 1])
            let blue = CGFloat(pixels[offset + 2])
            return red * 0.299 + green * 0.587 + blue * 0.114
        }

        let borderStep = max(1, min(width, height) / 80)
        var borderTotal: CGFloat = 0
        var borderCount: CGFloat = 0
        for x in stride(from: 0, to: width, by: borderStep) {
            borderTotal += luminance(at: x, 0)
            borderTotal += luminance(at: x, height - 1)
            borderCount += 2
        }
        for y in stride(from: 0, to: height, by: borderStep) {
            borderTotal += luminance(at: 0, y)
            borderTotal += luminance(at: width - 1, y)
            borderCount += 2
        }
        let borderAverage = borderCount > 0 ? borderTotal / borderCount : 210
        let darkThreshold = max(50, min(170, borderAverage - 24))

        var columnCounts = [Int](repeating: 0, count: width)
        var totalInkCount = 0
        for y in 0..<height {
            for x in 0..<width where luminance(at: x, y) < darkThreshold {
                columnCounts[x] += 1
                totalInkCount += 1
            }
        }
        guard totalInkCount > 30 else { return nil }

        let columnRuns = runs(
            in: columnCounts,
            threshold: max(2, Int(CGFloat(height) * 0.012)),
            mergeGap: prefersMainColumn ? max(4, width / 18) : max(2, width / 35)
        )
        guard let targetColumnRun = columnRuns.max(by: { lhs, rhs in
            let lhsScore = columnRunScore(
                lhs,
                counts: columnCounts,
                imageWidth: width,
                imageHeight: height,
                prefersMainColumn: prefersMainColumn
            )
            let rhsScore = columnRunScore(
                rhs,
                counts: columnCounts,
                imageWidth: width,
                imageHeight: height,
                prefersMainColumn: prefersMainColumn
            )
            return lhsScore < rhsScore
        }) else {
            return nil
        }

        let columnPadding = max(6, (targetColumnRun.upperBound - targetColumnRun.lowerBound) / 2)
        let minX = max(0, targetColumnRun.lowerBound - columnPadding)
        let maxX = min(width - 1, targetColumnRun.upperBound + columnPadding)
        let targetWidth = maxX - minX + 1
        guard targetWidth > 10 else { return nil }

        var targetRowCounts = [Int](repeating: 0, count: height)
        for y in 0..<height {
            var count = 0
            for x in minX...maxX where luminance(at: x, y) < darkThreshold {
                count += 1
            }
            targetRowCounts[y] = count
        }

        var rowRuns = runs(
            in: targetRowCounts,
            threshold: max(2, Int(CGFloat(targetWidth) * 0.035)),
            mergeGap: max(3, height / 95)
        )
        rowRuns = rowRuns.filter { run in
            let height = run.upperBound - run.lowerBound + 1
            return height >= 5
                && runInk(targetRowCounts, run) >= CGFloat(max(8, targetWidth / 4))
        }
        guard rowRuns.count >= 2, rowRuns.count <= 18 else { return nil }

        let rowPadding = max(4, height / 120)
        let segments = rowRuns.map { run -> CGRect in
            let yMin = max(0, run.lowerBound - rowPadding)
            let yMax = min(height - 1, run.upperBound + rowPadding)
            return CGRect(
                x: minX,
                y: yMin,
                width: targetWidth,
                height: yMax - yMin + 1
            )
        }

        guard let scannedImage = bitmap.makeImage() else { return nil }
        let maxSegmentHeight = segments.map(\.height).max() ?? 0
        guard maxSegmentHeight > 0 else { return nil }

        let scale = min(max(220 / maxSegmentHeight, 1), 4)
        let gap = Int(18 * scale)
        let padding = Int(24 * scale)
        let outputHeight = Int(ceil(maxSegmentHeight * scale)) + padding * 2
        let outputWidth = segments.reduce(padding * 2 + gap * max(0, segments.count - 1)) {
            $0 + Int(ceil($1.width * scale))
        }

        guard outputWidth > 0,
              outputHeight > 0,
              let output = CGContext(
                  data: nil,
                  width: outputWidth,
                  height: outputHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: outputWidth * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }
        output.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        output.fill(CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))

        var xOffset = padding
        for segment in segments {
            guard let cropped = scannedImage.cropping(to: segment) else { continue }
            let destinationWidth = Int(ceil(segment.width * scale))
            let destinationHeight = Int(ceil(segment.height * scale))
            let destinationY = padding + (outputHeight - padding * 2 - destinationHeight) / 2
            output.draw(
                cropped,
                in: CGRect(
                    x: xOffset,
                    y: destinationY,
                    width: destinationWidth,
                    height: destinationHeight
                )
            )
            xOffset += destinationWidth + gap
        }

        guard let reflowedImage = output.makeImage() else { return nil }
        return context.jpegRepresentation(
            of: CIImage(cgImage: reflowedImage),
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [
                kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.98
            ]
        )
    }

    private func runs(in counts: [Int], threshold: Int, mergeGap: Int) -> [ClosedRange<Int>] {
        var rawRuns: [ClosedRange<Int>] = []
        var start: Int?
        for (index, count) in counts.enumerated() {
            if count >= threshold {
                if start == nil {
                    start = index
                }
            } else if let currentStart = start {
                rawRuns.append(currentStart...(index - 1))
                start = nil
            }
        }
        if let start {
            rawRuns.append(start...(counts.count - 1))
        }

        var mergedRuns: [ClosedRange<Int>] = []
        for run in rawRuns {
            guard let last = mergedRuns.last else {
                mergedRuns.append(run)
                continue
            }
            if run.lowerBound - last.upperBound <= mergeGap {
                mergedRuns[mergedRuns.count - 1] = last.lowerBound...run.upperBound
            } else {
                mergedRuns.append(run)
            }
        }
        return mergedRuns
    }

    private func runInk(_ counts: [Int], _ run: ClosedRange<Int>) -> CGFloat {
        CGFloat(run.reduce(0) { $0 + counts[$1] })
    }

    private func centerPenalty(_ run: ClosedRange<Int>, size: Int) -> CGFloat {
        let center = CGFloat(run.lowerBound + run.upperBound) / 2
        let distance = abs(center - CGFloat(size) / 2)
        return distance * 0.55
    }

    private func columnRunScore(
        _ run: ClosedRange<Int>,
        counts: [Int],
        imageWidth: Int,
        imageHeight: Int,
        prefersMainColumn: Bool
    ) -> CGFloat {
        let width = run.upperBound - run.lowerBound + 1
        let ink = runInk(counts, run)
        let base = ink - centerPenalty(run, size: imageWidth)
        guard prefersMainColumn else { return base }

        let widthRatio = CGFloat(width) / CGFloat(max(imageWidth, 1))
        let narrowPenalty = widthRatio < 0.08 ? CGFloat(imageHeight) * 0.28 : 0
        let widthBonus = CGFloat(width) * CGFloat(imageHeight) * 0.035
        return base + widthBonus - narrowPenalty
    }

    private func paddedJPEG(from image: CIImage, context: CIContext) -> Data? {
        let padding = max(image.extent.width, image.extent.height) * 0.18
        let paddedExtent = CGRect(
            x: 0,
            y: 0,
            width: image.extent.width + padding * 2,
            height: image.extent.height + padding * 2
        )
        let background = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: paddedExtent)
        let translated = image.transformed(
            by: CGAffineTransform(
                translationX: padding - image.extent.minX,
                y: padding - image.extent.minY
            )
        )
        let composed = translated.composited(over: background)
        return context.jpegRepresentation(
            of: composed,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [
                kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.96
            ]
        )
    }

    private func verticalReflowJPEG(
        from image: CIImage,
        characterCount: Int,
        context: CIContext
    ) -> Data? {
        guard characterCount > 1 else { return nil }
        let sourceExtent = image.extent
        let sliceHeight = sourceExtent.height / CGFloat(characterCount)
        guard sliceHeight > 8, sourceExtent.width > 8 else { return nil }

        let padding = max(sourceExtent.width, sliceHeight) * 0.18
        let outputExtent = CGRect(
            x: 0,
            y: 0,
            width: sourceExtent.width * CGFloat(characterCount) + padding * 2,
            height: sliceHeight + padding * 2
        )

        var composed = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: outputExtent)

        for index in 0..<characterCount {
            // Japanese vertical text is read top-to-bottom. Core Image coordinates
            // grow upward, so the first slice starts at maxY.
            let sliceRect = CGRect(
                x: sourceExtent.minX,
                y: sourceExtent.maxY - sliceHeight * CGFloat(index + 1),
                width: sourceExtent.width,
                height: sliceHeight
            )
            let slice = image.cropped(to: sliceRect)
            let translated = slice.transformed(
                by: CGAffineTransform(
                    translationX: padding + sourceExtent.width * CGFloat(index) - sliceRect.minX,
                    y: padding - sliceRect.minY
                )
            )
            composed = translated.composited(over: composed)
        }

        return context.jpegRepresentation(
            of: composed,
            colorSpace: CGColorSpaceCreateDeviceRGB(),
            options: [
                kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.96
            ]
        )
    }
}
