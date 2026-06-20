@preconcurrency import AVFoundation
import Foundation

@MainActor
final class CameraService: NSObject, ObservableObject {
    enum CameraError: LocalizedError {
        case permissionDenied
        case configurationFailed
        case captureFailed

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "設定でカメラの使用を許可してください。"
            case .configurationFailed:
                "カメラを起動できませんでした。"
            case .captureFailed:
                "撮影できませんでした。もう一度お試しください。"
            }
        }
    }

    var permissionIsDenied: Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return status == .denied || status == .restricted
    }

    let session = AVCaptureSession()
    @Published private(set) var isRunning = false

    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.shirangana.camera.session")
    private var captureDelegate: PhotoCaptureDelegate?

    func start() async throws {
        #if targetEnvironment(simulator)
        isRunning = true
        #else
        let allowed = await requestPermission()
        guard allowed else { throw CameraError.permissionDenied }

        if session.inputs.isEmpty {
            try await configure()
        }

        await withCheckedContinuation { continuation in
            sessionQueue.async { [session] in
                if !session.isRunning {
                    session.startRunning()
                }
                continuation.resume()
            }
        }
        isRunning = true
        #endif
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
        isRunning = false
    }

    func capture() async throws -> Data {
        #if targetEnvironment(simulator)
        throw CameraError.captureFailed
        #else
        try await withCheckedThrowingContinuation { continuation in
            let delegate = PhotoCaptureDelegate { [weak self] result in
                Task { @MainActor in
                    self?.captureDelegate = nil
                    continuation.resume(with: result)
                }
            }
            captureDelegate = delegate

            let settings = AVCapturePhotoSettings()
            settings.flashMode = .off
            settings.photoQualityPrioritization = .speed
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
        #endif
    }

    private func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .video)
        default:
            false
        }
    }

    private func configure() async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [session, photoOutput] in
                session.beginConfiguration()
                defer { session.commitConfiguration() }
                session.sessionPreset = .photo

                guard let device = AVCaptureDevice.default(
                    .builtInWideAngleCamera,
                    for: .video,
                    position: .back
                ),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input),
                session.canAddOutput(photoOutput) else {
                    continuation.resume(throwing: CameraError.configurationFailed)
                    return
                }

                session.addInput(input)
                session.addOutput(photoOutput)
                continuation.resume(returning: ())
            }
        }
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<Data, Error>) -> Void

    init(completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            completion(.failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            completion(.failure(CameraService.CameraError.captureFailed))
            return
        }
        completion(.success(data))
    }
}
