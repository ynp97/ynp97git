import ImageIO
import SwiftUI
import UIKit

struct CameraScreen: View {
    private enum Phase {
        case camera
        case crop(Data)
        case processing
        case result(ReadingResult)
        case failure(String, RecognitionDiagnostic?)
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
    @State private var isCapturing = false
    @State private var isCaptureFlashVisible = false
    @State private var zoomAtGestureStart: CGFloat = 1
    @State private var focusTapPoint: CGPoint?
    @State private var focusTapID = UUID()
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
                ResultScreen(result: result, retry: reset, chooseCandidate: showCandidate)
            case .failure(let message, let diagnostic):
                failureView(message, diagnostic: diagnostic)
            }

            #if DEBUG
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
            #endif
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

            GeometryReader { proxy in
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
                    if isCaptureFlashVisible {
                        Color.white
                            .opacity(0.82)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }

                    if let focusTapPoint {
                        FocusTapIndicator()
                            .position(focusTapPoint)
                            .allowsHitTesting(false)
                    }

                    VStack {
                        HStack(spacing: 8) {
                            Text("まず文章を撮影しよう")
                                .font(PixelTheme.font(size: 13))
                                .foregroundStyle(PixelTheme.paper)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .pixelPanel(fill: PixelTheme.ink, stroke: PixelTheme.paper, shadowSize: 0)

                            Text(String(format: "%.1fx", camera.zoomFactor))
                                .font(PixelTheme.font(size: 12))
                                .foregroundStyle(PixelTheme.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .pixelPanel(fill: PixelTheme.gold, shadowSize: 0)
                        }

                        Text("ピンチでズーム・文字をタップでピント")
                            .font(PixelTheme.font(size: 9, weight: .medium))
                            .foregroundStyle(PixelTheme.paper)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(PixelTheme.ink.opacity(0.75))

                        Spacer()

                        FocusFrame()
                            .frame(width: 250, height: 180)
                            .allowsHitTesting(false)

                        Spacer()

                        ShutterButton(action: animateShutterAndCapture)
                            .disabled(isCapturing)
                            .opacity(isCapturing ? 0.76 : 1)
                        .accessibilityLabel("撮影して読みを調べる")
                    }
                    .padding(.vertical, 24)
                }
                .contentShape(Rectangle())
                .gesture(
                    MagnificationGesture()
                        .onChanged { scale in
                            camera.setZoomFactor(zoomAtGestureStart * scale)
                        }
                        .onEnded { _ in
                            zoomAtGestureStart = camera.zoomFactor
                        }
                )
                .simultaneousGesture(
                    SpatialTapGesture()
                        .onEnded { value in
                            focus(at: value.location, in: proxy.size)
                        }
                )
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

    private func failureView(_ message: String, diagnostic: RecognitionDiagnostic?) -> some View {
        VStack(spacing: 12) {
            Button(camera.permissionIsDenied ? "設定を開く" : "もう一度") {
                if camera.permissionIsDenied,
                   let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                } else {
                    reset()
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 20)
            .padding(.top, 20)

            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 54))
                        .foregroundStyle(PixelTheme.red)
                    Text(message)
                        .font(PixelTheme.font(size: 17))
                        .multilineTextAlignment(.center)
                    if let diagnostic {
                        CandidateSelectionPanel(diagnostic: diagnostic, choose: showCandidate)
                        #if DEBUG
                        DiagnosticPanel(diagnostic: diagnostic)
                        #endif
                    }
                }
                .padding(28)
                .pixelPanel()
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    private func capture() {
        Task {
            defer { isCapturing = false }
            do {
                let originalImageData = try await camera.capture()
                camera.stop()
                let preparedImageData = try await imagePreparation.prepareForCropping(
                    originalImageData
                )
                phase = .crop(preparedImageData)
            } catch {
                phase = .failure(error.localizedDescription, nil)
            }
        }
    }

    private func recognize(_ croppedImageData: Data) {
        phase = .processing
        Task {
            do {
                var diagnostic = await recognizer.recognizeDiagnostics(
                    in: croppedImageData
                )
                let candidates = diagnostic.allOCRCandidates
                diagnostic.dictionaryCandidates = try await dictionary.inspectCandidates(
                    in: candidates
                )
                guard !candidates.isEmpty else {
                    phase = .failure(
                        "文字を見つけられませんでした。\n黄色い枠の中央に入れて、もう一度撮ってください。",
                        diagnostic
                    )
                    return
                }
                guard let result = try await dictionary.findBestReading(
                    in: candidates
                ) else {
                    phase = .failure(
                        failureMessage(
                            release: "読みが見つかりませんでした。\n黄色い枠を文字に合わせて、もう一度撮ってください。",
                            debug: "読みが見つかりませんでした。\n下の診断でOCR候補と辞書照合を確認してください。"
                        ),
                        diagnostic
                    )
                    return
                }
                if shouldRejectSingleCharacterVerticalResult(
                    result,
                    imageData: croppedImageData
                ) {
                    phase = .failure(
                        failureMessage(
                            release: "文字の一部だけを読み取ったようです。\n黄色い枠を文字に合わせて、もう一度撮ってください。",
                            debug: "縦書きの一部だけを拾っています。\n下の診断でOCR候補を確認してください。"
                        ),
                        diagnostic
                    )
                    return
                }
                if shouldRejectShortPartialVerticalResult(
                    result,
                    candidates: candidates,
                    imageData: croppedImageData
                ) {
                    phase = .failure(
                        failureMessage(
                            release: "文字の一部だけを読み取ったようです。\n黄色い枠を文字に合わせて、もう一度撮ってください。",
                            debug: "縦書きの一部だけを答えにしそうです。\n下の診断でOCR候補を確認してください。"
                        ),
                        diagnostic
                    )
                    return
                }
                phase = .result(
                    ReadingResult(
                        expression: result.expression,
                        readings: result.readings,
                        meanings: result.meanings,
                        diagnostic: diagnostic
                    )
                )
            } catch {
                phase = .failure(error.localizedDescription, nil)
            }
        }
    }

    private func showCandidate(_ candidate: DictionaryCandidateDiagnostic) {
        guard let expression = candidate.matchedExpression else { return }
        phase = .result(
            ReadingResult(
                expression: expression,
                readings: candidate.readings,
                meanings: candidate.meanings,
                diagnostic: nil
            )
        )
    }

    private func shouldRejectSingleCharacterVerticalResult(
        _ result: ReadingResult,
        imageData: Data
    ) -> Bool {
        guard result.expression.count == 1,
              let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source,
                  0,
                  nil
              ) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              width > 0 else {
            return false
        }
        return isProbablyVerticalCrop(width: width, height: height)
    }

    private func shouldRejectShortPartialVerticalResult(
        _ result: ReadingResult,
        candidates: [String],
        imageData: Data
    ) -> Bool {
        let expression = result.expression
        let resultIdeographs = ideographCount(in: expression)
        guard expression.count <= 2,
              resultIdeographs == expression.count,
              let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(
                  source,
                  0,
                  nil
              ) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
              isProbablyVerticalCrop(width: width, height: height) else {
            return false
        }

        return candidates.contains { candidate in
            let normalized = candidate
                .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized != expression,
                  normalized.contains(expression) else {
                return false
            }
            let candidateIdeographs = ideographCount(in: normalized)
            return candidateIdeographs >= max(4, resultIdeographs + 2)
        }
    }

    private func isProbablyVerticalCrop(width: CGFloat, height: CGFloat) -> Bool {
        width > 0 && height / width >= 1.55
    }

    private func ideographCount(in text: String) -> Int {
        text.unicodeScalars.filter(\.properties.isIdeographic).count
    }

    private func animateShutterAndCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        triggerShutterFeedback()
        capture()
    }

    private func triggerShutterFeedback() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 1)
        withAnimation(.linear(duration: 0.02)) {
            isCaptureFlashVisible = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(95))
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.12)) {
                    isCaptureFlashVisible = false
                }
            }
        }
    }

    private func reset() {
        phase = .camera
        zoomAtGestureStart = camera.zoomFactor
        Task {
            await startCamera()
        }
    }

    private func focus(at point: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let normalized = CGPoint(
            x: point.x / size.width,
            y: point.y / size.height
        )
        camera.focus(at: normalized)
        let id = UUID()
        focusTapID = id
        withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
            focusTapPoint = point
        }
        Task {
            try? await Task.sleep(for: .milliseconds(850))
            guard focusTapID == id else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.22)) {
                    focusTapPoint = nil
                }
            }
        }
    }

    private func startCamera() async {
        do {
            try await camera.start()
        } catch {
            phase = .failure(error.localizedDescription, nil)
        }
    }

    private func failureMessage(release: String, debug: String) -> String {
        #if DEBUG
        debug
        #else
        release
        #endif
    }

    #if DEBUG
    private var buildNumber: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "?"
    }
    #endif

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
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .offset(y: configuration.isPressed ? 5 : 0)
            .background {
                Ellipse()
                    .fill(PixelTheme.ink)
                    .frame(
                        width: configuration.isPressed ? 124 : 118,
                        height: configuration.isPressed ? 44 : 118
                    )
                    .offset(y: configuration.isPressed ? 48 : 10)
                    .opacity(configuration.isPressed ? 0.45 : 1)
            }
            .animation(
                .spring(response: 0.1, dampingFraction: 0.72, blendDuration: 0.02),
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

private struct FocusTapIndicator: View {
    var body: some View {
        ZStack {
            Rectangle()
                .stroke(PixelTheme.gold, lineWidth: 3)
                .frame(width: 76, height: 76)
            Rectangle()
                .fill(PixelTheme.gold)
                .frame(width: 8, height: 8)
        }
        .shadow(color: PixelTheme.ink.opacity(0.7), radius: 0, x: 3, y: 3)
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
