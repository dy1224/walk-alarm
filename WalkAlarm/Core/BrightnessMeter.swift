import AVFoundation
import CoreMedia
import ImageIO
import os

/// 한 프레임에서 읽은 노출 정보.
struct FrameSample: Sendable {
    let date: Date
    /// 프레임 EXIF의 BrightnessValue (APEX Bv). 없으면 nil.
    let exifBv: Double?
    /// ISO·노출시간·조리개로 계산한 Bv.
    let calcBv: Double?
    let iso: Double?
    let exposure: Double?
    let fNumber: Double?

    /// 판정에 쓰는 값. EXIF가 있으면 EXIF, 없으면 계산값.
    var bv: Double? { exifBv ?? calcBv }
}

/// 1초 동안 모인 프레임 요약.
struct SecondSummary: Sendable {
    var frameCount = 0
    var exifCount = 0
    var meanBv: Double?
    var latest: FrameSample?
}

/// 후면 카메라로 주변 밝기(Bv)를 잰다.
///
/// 아이폰은 조도 센서 값을 앱에 주지 않으므로, 카메라 프레임 메타데이터의
/// EXIF BrightnessValue를 조도 대용으로 쓴다. 자동노출이 픽셀 밝기를 일정하게
/// 맞추므로 픽셀 평균은 쓰지 않는다. EXIF 값이 없는 프레임은 ISO·노출시간·조리개로 계산한다.
///
/// 세션 조작은 `sessionQueue`, 프레임 처리는 `videoQueue`에서만 한다.
/// 프레임 값은 잠금으로 모아 두고, 1초 타이머가 `drain()`으로 가져간다.
final class BrightnessMeter: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    enum StartResult: Sendable {
        case started
        case noCamera
        case configurationFailed(String)
    }

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.geumdongyup.walkalarm.camera.session")
    private let videoQueue = DispatchQueue(label: "com.geumdongyup.walkalarm.camera.video", qos: .userInitiated)
    /// sessionQueue에서 한 번 정하고, 이후 videoQueue에서 읽기만 한다.
    private var device: AVCaptureDevice?
    private var isConfigured = false
    private var observers: [any NSObjectProtocol] = []

    private let accumulator = OSAllocatedUnfairLock(initialState: Accumulator())
    private let onFrame: @Sendable (FrameSample) -> Void

    private struct Accumulator: Sendable {
        var sum = 0.0
        var valued = 0
        var frames = 0
        var exif = 0
        var latest: FrameSample?
    }

    /// - Parameter onFrame: 프레임마다 videoQueue에서 불린다. CSV 기록용.
    init(onFrame: @escaping @Sendable (FrameSample) -> Void) {
        self.onFrame = onFrame
        super.init()
        observeSession()
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - 시작 / 멈춤

    func start() async -> StartResult {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [self] in
                if !isConfigured, let failure = configure() {
                    continuation.resume(returning: failure)
                    return
                }
                accumulator.withLock { $0 = Accumulator() }
                if !session.isRunning {
                    session.startRunning()
                }
                continuation.resume(returning: .started)
            }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    /// 지난 호출 이후 모인 프레임을 요약해 가져가고 비운다.
    func drain() -> SecondSummary {
        accumulator.withLock { a in
            let summary = SecondSummary(
                frameCount: a.frames,
                exifCount: a.exif,
                meanBv: a.valued > 0 ? a.sum / Double(a.valued) : nil,
                latest: a.latest
            )
            a = Accumulator()
            return summary
        }
    }

    // MARK: - 설정

    private func configure() -> StartResult? {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return .noCamera
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 밝기 메타데이터만 필요하므로 가장 낮은 화질로 전력을 아낀다.
        if session.canSetSessionPreset(.low) {
            session.sessionPreset = .low
        }

        do {
            let input = try AVCaptureDeviceInput(device: camera)
            guard session.canAddInput(input) else {
                return .configurationFailed("카메라 입력을 붙일 수 없음")
            }
            session.addInput(input)
        } catch {
            return .configurationFailed(error.localizedDescription)
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else {
            return .configurationFailed("영상 출력을 붙일 수 없음")
        }
        session.addOutput(output)

        device = camera
        isConfigured = true
        AppLogger.shared.info("카메라 준비 · \(camera.localizedName) · preset \(session.sessionPreset.rawValue)", category: "camera")
        return nil
    }

    /// 앱이 백그라운드로 가면 카메라가 끊긴다. 4단계 판정에서 중요한 신호라 기록한다.
    private func observeSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil
        ) { note in
            let reason = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int).map(String.init) ?? "?"
            AppLogger.shared.warn("카메라 중단 · reason \(reason)", category: "camera")
        })
        observers.append(center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil
        ) { _ in
            AppLogger.shared.info("카메라 재개", category: "camera")
        })
        observers.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
        ) { note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            AppLogger.shared.error("카메라 오류 · \(error?.localizedDescription ?? "알 수 없음")", category: "camera")
        })
    }

    // MARK: - 프레임

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let sample = Self.read(sampleBuffer, device: device)
        accumulator.withLock { a in
            a.frames += 1
            if sample.exifBv != nil { a.exif += 1 }
            if let bv = sample.bv {
                a.sum += bv
                a.valued += 1
            }
            a.latest = sample
        }
        onFrame(sample)
    }

    private static func read(_ buffer: CMSampleBuffer, device: AVCaptureDevice?) -> FrameSample {
        var exifBv: Double?
        var iso: Double?
        var exposure: Double?
        var fNumber: Double?

        let attachments = CMCopyDictionaryOfAttachments(
            allocator: kCFAllocatorDefault,
            target: buffer,
            attachmentMode: kCMAttachmentMode_ShouldPropagate
        ) as NSDictionary?
        if let exif = attachments?[kCGImagePropertyExifDictionary as String] as? NSDictionary {
            exifBv = (exif[kCGImagePropertyExifBrightnessValue as String] as? NSNumber)?.doubleValue
            iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first?.doubleValue
            exposure = (exif[kCGImagePropertyExifExposureTime as String] as? NSNumber)?.doubleValue
            fNumber = (exif[kCGImagePropertyExifFNumber as String] as? NSNumber)?.doubleValue
        }

        // EXIF에 없으면 카메라의 현재 노출 값으로 채운다.
        if let device {
            iso = iso ?? Double(device.iso)
            exposure = exposure ?? device.exposureDuration.seconds
            fNumber = fNumber ?? Double(device.lensAperture)
        }

        return FrameSample(
            date: Date(),
            exifBv: exifBv,
            calcBv: apexBv(iso: iso, exposure: exposure, fNumber: fNumber),
            iso: iso,
            exposure: exposure,
            fNumber: fNumber
        )
    }

    /// APEX: Bv = Av + Tv − Sv.
    /// Av = log2(N²), Tv = log2(1/t), Sv = log2(ISO / 3.125) (ISO 100일 때 5).
    static func apexBv(iso: Double?, exposure: Double?, fNumber: Double?) -> Double? {
        guard let iso, let exposure, let fNumber,
              iso > 0, exposure > 0, fNumber > 0,
              exposure.isFinite else { return nil }
        let av = log2(fNumber * fNumber)
        let tv = log2(1 / exposure)
        let sv = log2(iso / 3.125)
        return av + tv - sv
    }
}
