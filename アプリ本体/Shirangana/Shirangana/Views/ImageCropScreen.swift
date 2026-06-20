import SwiftUI
import UIKit

struct ImageCropScreen: View {
    let imageData: Data
    let cancel: () -> Void
    let confirm: (Data) -> Void

    var body: some View {
        if let image = UIImage(data: imageData)?.normalized {
            ImageCropEditor(image: image, cancel: cancel, confirm: confirm)
        } else {
            Text("画像を読み込めませんでした。")
                .font(PixelTheme.font(size: 16))
        }
    }
}

private struct ImageCropEditor: View {
    let image: UIImage
    let cancel: () -> Void
    let confirm: (Data) -> Void

    @State private var interaction = CropInteractionState()
    @State private var isVertical = false
    @State private var selectionWidth: CGFloat = 250
    @State private var selectionHeight: CGFloat = 180

    private var selectionSize: CGSize {
        CGSize(width: selectionWidth, height: selectionHeight)
    }

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 3) {
                Text("STEP 2")
                    .font(PixelTheme.font(size: 10))
                    .tracking(2)
                    .foregroundStyle(PixelTheme.blue)
                Text("よみたい漢字をつかまえよう")
                    .font(PixelTheme.font(size: 18))
                Text("2本指で拡大・1本指で移動")
                    .font(PixelTheme.font(size: 11, weight: .medium))
                    .foregroundStyle(PixelTheme.red)

                HStack(spacing: 8) {
                    WritingDirectionButton(
                        title: "横書き",
                        isSelected: !isVertical
                    ) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            isVertical = false
                            selectionWidth = 250
                            selectionHeight = 180
                        }
                    }
                    WritingDirectionButton(
                        title: "縦書き",
                        isSelected: isVertical
                    ) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            isVertical = true
                            selectionWidth = 180
                            selectionHeight = 250
                        }
                    }
                }
                .padding(.top, 6)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .pixelPanel(fill: PixelTheme.paper, shadowSize: 3)

            GeometryReader { proxy in
                ZStack {
                    PixelTheme.ink

                    CropScrollView(
                        image: image,
                        interaction: interaction
                    )

                    RetroScanlines()
                        .allowsHitTesting(false)

                    Color.black.opacity(0.48)
                        .mask {
                            Rectangle()
                                .overlay {
                                    Rectangle()
                                        .frame(
                                            width: selectionSize.width,
                                            height: selectionSize.height
                                        )
                                        .blendMode(.destinationOut)
                                }
                                .compositingGroup()
                        }
                        .allowsHitTesting(false)

                    CropFocusFrame()
                        .frame(
                            width: selectionSize.width,
                            height: selectionSize.height
                        )
                        .allowsHitTesting(false)

                }
                .clipped()
                .overlay {
                    Rectangle()
                        .stroke(PixelTheme.ink, lineWidth: 5)
                        .allowsHitTesting(false)
                }
                .safeAreaInset(edge: .bottom) {
                    Text("黄色い枠の中だけを読み取ります")
                    .font(PixelTheme.font(size: 9))
                    .foregroundStyle(PixelTheme.paper)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(PixelTheme.ink.opacity(0.88))
                }
            }

            VStack(spacing: 5) {
                CropDimensionControl(
                    title: "横幅",
                    value: $selectionWidth,
                    range: 55...300
                )
                CropDimensionControl(
                    title: "高さ",
                    value: $selectionHeight,
                    range: 55...300
                )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .pixelPanel(fill: PixelTheme.paper, shadowSize: 2)

            HStack(spacing: 14) {
                Button("撮り直す", action: cancel)
                    .buttonStyle(PixelSecondaryButtonStyle())

                Button("ここを読む", action: confirmCrop)
                    .buttonStyle(PrimaryButtonStyle())
            }
            .frame(height: 62)
        }
        .padding(20)
    }

    private func confirmCrop() {
        guard let data = interaction.cropData(selectionSize: selectionSize) else {
            return
        }
        confirm(data)
    }
}

private final class CropInteractionState {
    weak var scrollView: CropImageScrollView?

    func cropData(selectionSize: CGSize) -> Data? {
        scrollView?.cropData(selectionSize: selectionSize)
    }
}

private struct CropScrollView: UIViewRepresentable {
    let image: UIImage
    let interaction: CropInteractionState

    func makeUIView(context: Context) -> CropImageScrollView {
        let view = CropImageScrollView(image: image)
        interaction.scrollView = view
        return view
    }

    func updateUIView(_ view: CropImageScrollView, context: Context) {}
}

private final class CropImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView: UIImageView
    private let sourceImage: UIImage
    private var didSetInitialZoom = false

    init(image: UIImage) {
        sourceImage = image
        imageView = UIImageView(image: image)
        super.init(frame: .zero)
        clipsToBounds = true
        delegate = self
        bouncesZoom = true
        decelerationRate = .fast
        delaysContentTouches = false
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        imageView.frame = CGRect(origin: .zero, size: image.size)
        addSubview(imageView)
        contentSize = image.size

        let reset = UITapGestureRecognizer(target: self, action: #selector(resetZoom))
        reset.numberOfTapsRequired = 2
        addGestureRecognizer(reset)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }

        let fitScale = min(
            bounds.width / sourceImage.size.width,
            bounds.height / sourceImage.size.height
        )
        let fillScale = max(
            bounds.width / sourceImage.size.width,
            bounds.height / sourceImage.size.height
        )
        minimumZoomScale = fitScale
        maximumZoomScale = fitScale * 10

        if !didSetInitialZoom {
            zoomScale = min(fillScale, maximumZoomScale)
            contentOffset = CGPoint(
                x: max((contentSize.width - bounds.width) / 2, 0),
                y: max((contentSize.height - bounds.height) / 2, 0)
            )
            didSetInitialZoom = true
        }
        centerImage()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImage()
    }

    func cropData(selectionSize: CGSize) -> Data? {
        guard let source = sourceImage.cgImage else { return nil }

        let selection = CGRect(
            x: bounds.midX - selectionSize.width / 2,
            y: bounds.midY - selectionSize.height / 2,
            width: selectionSize.width,
            height: selectionSize.height
        )
        let imageRect = imageView.convert(selection, from: self)
        let xRatio = CGFloat(source.width) / sourceImage.size.width
        let yRatio = CGFloat(source.height) / sourceImage.size.height
        let crop = CGRect(
            x: imageRect.minX * xRatio,
            y: imageRect.minY * yRatio,
            width: imageRect.width * xRatio,
            height: imageRect.height * yRatio
        ).intersection(
            CGRect(x: 0, y: 0, width: source.width, height: source.height)
        ).integral

        guard crop.width > 16,
              crop.height > 16,
              let cropped = source.cropping(to: crop) else {
            return nil
        }
        return UIImage(cgImage: cropped).jpegData(compressionQuality: 0.95)
    }

    @objc private func resetZoom() {
        setZoomScale(minimumZoomScale, animated: true)
    }

    private func centerImage() {
        let horizontal = max((bounds.width - contentSize.width) / 2, 0)
        let vertical = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(
            top: vertical,
            left: horizontal,
            bottom: vertical,
            right: horizontal
        )
    }
}

private struct CropSizeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 24, weight: .black, design: .monospaced))
            .foregroundStyle(PixelTheme.paper)
            .frame(width: 38, height: 32)
            .background(configuration.isPressed ? PixelTheme.red : PixelTheme.blue)
            .overlay {
                Rectangle().stroke(PixelTheme.ink, lineWidth: 2)
            }
    }
}

private struct CropDimensionControl: View {
    let title: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>

    var body: some View {
        HStack(spacing: 7) {
            Text(title)
                .font(PixelTheme.font(size: 10))
                .frame(width: 38, alignment: .leading)

            Button("−") {
                value = max(range.lowerBound, value - 10)
            }
            .buttonStyle(CropSizeButtonStyle())

            Slider(value: $value, in: range, step: 5)
                .tint(PixelTheme.red)

            Button("＋") {
                value = min(range.upperBound, value + 10)
            }
            .buttonStyle(CropSizeButtonStyle())
        }
    }
}

private struct WritingDirectionButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(PixelTheme.font(size: 11))
                .foregroundStyle(isSelected ? PixelTheme.paper : PixelTheme.ink)
                .padding(.horizontal, 15)
                .frame(height: 30)
                .background(isSelected ? PixelTheme.blue : PixelTheme.background)
                .overlay {
                    Rectangle()
                        .stroke(PixelTheme.ink, lineWidth: 2)
                }
        }
    }
}

private struct CropFocusFrame: View {
    var body: some View {
        ZStack {
            Rectangle()
                .stroke(PixelTheme.paper.opacity(0.45), lineWidth: 2)
            CropPixelCorners()
                .stroke(
                    PixelTheme.gold,
                    style: StrokeStyle(lineWidth: 7, lineCap: .square)
                )
        }
    }
}

private struct CropPixelCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(rect.width, rect.height) * 0.25
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))

        return path
    }
}

private struct PixelSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PixelTheme.font(size: 15))
            .foregroundStyle(PixelTheme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .pixelPanel(
                fill: PixelTheme.paper,
                shadowSize: configuration.isPressed ? 2 : 5
            )
            .offset(y: configuration.isPressed ? 3 : 0)
    }
}

private extension UIImage {
    var normalized: UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
