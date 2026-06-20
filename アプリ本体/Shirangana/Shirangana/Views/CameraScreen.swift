import SwiftUI
import UIKit

struct CameraScreen: View {
    private enum Phase {
        case camera
        case crop(Data)
        case processing
        case result(ReadingResult)
        case failure(String)
    }

    @StateObject private var camera = CameraService()
    @State private var phase: Phase = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo-crop") {
            return .crop(Self.demoCropImageData())
        }
        if ProcessInfo.processInfo.arguments.contains("--demo-result") {
            return .result(
                ReadingResult(
                    expression: "人気",
                    readings: ["にんき", "ひとけ"],
                    meanings: ["広く受け入れられ、もてはやされること"]
                )
            )
        }
        #endif
        return .camera
    }()
    @State private var isShowingAbout = false
    @State private var isShutterAnimating = false
    private let recognizer = TextRecognitionService()
    private let dictionary = ReadingDictionary()
    private let imagePreparation = ImagePreparationService()

    var body: some View {
        ZStack {
            PixelTheme.background
                .ignoresSafeArea()

            switch phase {
            case .camera:
                cameraView
            case .crop(let imageData):
                ImageCropScreen(
                    imageData: imageData,
                    cancel: reset,
                    confirm: recognize
                )
            case .processing:
                processingView
            case .result(let result):
                ResultScreen(result: result, retry: reset)
            case .failure(let message):
                failureView(message)
            }

            VStack {
                HStack {
                    Spacer()
                    Text("BUILD \(buildNumber)")
                        .font(.system(size: 22, weight: .black, design: .monospaced))
                        .foregroundStyle(PixelTheme.paper)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(PixelTheme.red)
                        .overlay {
                            Rectangle().stroke(PixelTheme.ink, lineWidth: 3)
                        }
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .allowsHitTesting(false)
        }
        .task {
            if case .camera = phase {
                await startCamera()
            }
        }
    }

    private var cameraView: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                HStack(spacing: 9) {
                    Text("シ")
                        .font(PixelTheme.font(size: 20))
                        .foregroundStyle(PixelTheme.paper)
                        .frame(width: 42, height: 42)
                        .background(PixelTheme.red)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("シランガナ：")
                            .font(PixelTheme.font(size: 17))
                        Text("よみがなキャッチャー")
                            .font(PixelTheme.font(size: 12))
                            .foregroundStyle(PixelTheme.red)
                    }
                }
                .padding(.trailing, 8)
                .pixelPanel(fill: PixelTheme.paper, shadowSize: 3)

                Spacer()

                Button {
                    isShowingAbout = true
                } label: {
                    Text("i")
                        .font(PixelTheme.font(size: 20))
                        .foregroundStyle(PixelTheme.paper)
                        .frame(width: 44, height: 44)
                        .pixelPanel(fill: PixelTheme.blue, shadowSize: 3)
                }
                .accessibilityLabel("このアプリについて")
            }

            ZStack {
                #if targetEnvironment(simulator)
                LinearGradient(
                    colors: [
                        Color(red: 0.15, green: 0.18, blue: 0.25),
                        PixelTheme.ink,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .overlay {
                    Text("カメラプレビュー")
                        .font(PixelTheme.font(size: 11))
                        .foregroundStyle(PixelTheme.paper.opacity(0.55))
                }
                #else
                CameraPreview(session: camera.session)
                #endif
                RetroScanlines()

                VStack {
                    Text("まず文章を撮影しよう")
                        .font(PixelTheme.font(size: 13))
                        .foregroundStyle(PixelTheme.paper)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .pixelPanel(fill: PixelTheme.ink, stroke: PixelTheme.paper, shadowSize: 0)

                    Spacer()

                    FocusFrame()
                        .frame(width: 250, height: 180)

                    Spacer()

                    ShutterButton(action: animateShutterAndCapture)
                        .disabled(isShutterAnimating)
                    .accessibilityLabel("撮影して読みを調べる")
                }
                .padding(.vertical, 24)
            }
            .background {
                Rectangle()
                    .fill(PixelTheme.ink)
                    .shadow(color: PixelTheme.shadow, radius: 0, x: 7, y: 7)
            }
            .overlay {
                Rectangle()
                    .stroke(PixelTheme.ink, lineWidth: 5)
            }

            Label("画像は保存されず、端末内だけで処理されます", systemImage: "lock.fill")
                .font(PixelTheme.font(size: 10, weight: .medium))
                .foregroundStyle(PixelTheme.ink.opacity(0.75))
        }
        .padding(20)
        .sheet(isPresented: $isShowingAbout) {
            AboutScreen()
        }
    }

    private var processingView: some View {
        VStack(spacing: 22) {
            Text("•••")
                .font(PixelTheme.font(size: 34))
                .foregroundStyle(PixelTheme.red)
            Text("ヨミヲ シラベテイマス")
                .font(PixelTheme.font(size: 17))
        }
        .padding(28)
        .pixelPanel()
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 22) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 54))
                .foregroundStyle(PixelTheme.red)
            Text(message)
                .font(PixelTheme.font(size: 17))
                .multilineTextAlignment(.center)
            Button(camera.permissionIsDenied ? "設定を開く" : "もう一度") {
                if camera.permissionIsDenied,
                   let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                } else {
                    reset()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(28)
        .pixelPanel()
    }

    private func capture() {
        Task {
            do {
                let originalImageData = try await camera.capture()
                camera.stop()
                let preparedImageData = try await imagePreparation.prepareForCropping(
                    originalImageData
                )
                phase = .crop(preparedImageData)
            } catch {
                phase = .failure(error.localizedDescription)
            }
        }
    }

    private func recognize(_ croppedImageData: Data) {
        phase = .processing
        Task {
            do {
                let candidates = try await recognizer.recognizeTextCandidates(
                    in: croppedImageData
                )
                guard let result = try await dictionary.findBestReading(
                    in: candidates
                ) else {
                    phase = .failure(
                        "読みが見つかりませんでした。\n読みたい漢字だけを黄色い枠に入れてください。"
                    )
                    return
                }
                phase = .result(result)
            } catch {
                phase = .failure(error.localizedDescription)
            }
        }
    }

    private func animateShutterAndCapture() {
        guard !isShutterAnimating else { return }
        isShutterAnimating = true
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

        Task {
            try? await Task.sleep(for: .milliseconds(420))
            capture()
            isShutterAnimating = false
        }
    }

    private func reset() {
        phase = .camera
        Task {
            await startCamera()
        }
    }

    private func startCamera() async {
        do {
            try await camera.start()
        } catch {
            phase = .failure(error.localizedDescription)
        }
    }

    private var buildNumber: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "?"
    }

    #if DEBUG
    private static func demoCropImageData() -> Data {
        let size = CGSize(width: 1200, height: 1600)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.jpegData(withCompressionQuality: 0.95) { context in
            UIColor(red: 0.96, green: 0.93, blue: 0.82, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 26
            let text = """
            新しい本を読んでいると、
            突然むずかしい漢字に出会う。

            今日の言葉は「杜撰」です。
            読みたい漢字を拡大して、
            黄色い枠の中へ入れよう。
            """
            (text as NSString).draw(
                in: CGRect(x: 100, y: 180, width: 1000, height: 1100),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 64, weight: .semibold),
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: paragraph,
                ]
            )
        }
    }
    #endif
}

private struct ShutterButton: View {
    let action: () -> Void
    @State private var isGlowing = false
    @State private var burst = false

    var body: some View {
        Button {
            burst = true
            action()
            Task {
                try? await Task.sleep(for: .milliseconds(30))
                withAnimation(.easeOut(duration: 0.38)) {
                    burst = false
                }
            }
        } label: {
            ZStack {
                PixelBurst(isActive: burst)

                Circle()
                    .fill(PixelTheme.gold.opacity(isGlowing ? 0.65 : 0.18))
                    .frame(width: isGlowing ? 146 : 126, height: isGlowing ? 146 : 126)

                ZStack {
                    Circle()
                        .fill(PixelTheme.red)
                    Circle()
                        .stroke(PixelTheme.paper, lineWidth: 7)
                        .padding(10)
                    Text("A")
                        .font(PixelTheme.font(size: 43))
                        .foregroundStyle(PixelTheme.paper)
                }
                .frame(width: 118, height: 118)
                .overlay {
                    Circle()
                        .stroke(PixelTheme.ink, lineWidth: 5)
                }
            }
            .frame(width: 164, height: 164)
        }
        .buttonStyle(SquishyShutterButtonStyle())
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isGlowing = true
            }
        }
    }
}

private struct SquishyShutterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                x: configuration.isPressed ? 1.08 : 1,
                y: configuration.isPressed ? 0.78 : 1,
                anchor: .bottom
            )
            .offset(y: configuration.isPressed ? 14 : 0)
            .background {
                Ellipse()
                    .fill(PixelTheme.ink)
                    .frame(
                        width: configuration.isPressed ? 126 : 118,
                        height: configuration.isPressed ? 32 : 118
                    )
                    .offset(y: configuration.isPressed ? 55 : 10)
                    .opacity(configuration.isPressed ? 0.45 : 1)
            }
            .animation(
                .spring(response: 0.28, dampingFraction: 0.38, blendDuration: 0.08),
                value: configuration.isPressed
            )
    }
}

private struct PixelBurst: View {
    let isActive: Bool
    private let particles: [(CGFloat, CGFloat, Color)] = [
        (-58, -48, PixelTheme.gold),
        (0, -68, PixelTheme.paper),
        (58, -48, PixelTheme.blue),
        (-72, 4, PixelTheme.paper),
        (72, 4, PixelTheme.gold),
        (-54, 58, PixelTheme.blue),
        (0, 74, PixelTheme.gold),
        (54, 58, PixelTheme.paper),
    ]

    var body: some View {
        ZStack {
            ForEach(Array(particles.enumerated()), id: \.offset) { _, particle in
                Rectangle()
                    .fill(particle.2)
                    .frame(width: 12, height: 12)
                    .offset(
                        x: isActive ? particle.0 * 0.25 : particle.0,
                        y: isActive ? particle.1 * 0.25 : particle.1
                    )
                    .opacity(isActive ? 1 : 0)
                    .scaleEffect(isActive ? 1 : 0.4)
            }
        }
    }
}

private struct FocusFrame: View {
    var body: some View {
        ZStack {
            Rectangle()
                .stroke(PixelTheme.paper.opacity(0.35), lineWidth: 2)
            PixelCorners()
                .stroke(PixelTheme.gold, style: StrokeStyle(lineWidth: 7, lineCap: .square))
        }
    }
}

private struct PixelCorners: Shape {
    func path(in rect: CGRect) -> Path {
        let length: CGFloat = 42
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

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PixelTheme.font(size: 17))
            .foregroundStyle(PixelTheme.paper)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .pixelPanel(
                fill: configuration.isPressed ? PixelTheme.red.opacity(0.8) : PixelTheme.red,
                shadowSize: configuration.isPressed ? 2 : 5
            )
            .offset(
                x: configuration.isPressed ? 3 : 0,
                y: configuration.isPressed ? 3 : 0
            )
    }
}
