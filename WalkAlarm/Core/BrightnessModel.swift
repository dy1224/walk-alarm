import AVFoundation
import Foundation
import Observation
import UIKit

/// 밝기 변화 판정값. 3단계에서는 화면 미리보기와 CSV의 `significant` 열에만 쓴다.
/// 4단계에서 설정 화면으로 조정할 수 있게 옮긴다.
enum Detection {
    /// 한 번의 변화로 인정할 최소 밝기 차 (Bv).
    static let deltaBv = 0.5
    /// 변화 횟수를 세는 구간 (초).
    static let windowSec = 10.0
    /// 이동으로 판정할 최소 변화 횟수.
    static let minChanges = 3
    /// 다시 울리기까지의 무변화 시간 (초).
    static let stillSec = 15.0
}

/// 밝기 측정 화면의 상태.
///
/// 1초마다 카메라가 모은 프레임의 Bv 평균 B(t)를 만들고, 직전 값과의 차로
/// 유의미한 변화를 센다. 최근 60초를 그래프로 보여 주고 CSV로 남긴다.
@MainActor
@Observable
final class BrightnessModel {

    static let shared = BrightnessModel()

    struct Point: Identifiable {
        let date: Date
        let bv: Double?
        let significant: Bool
        /// 끊긴 구간(프레임 없음)을 넘어 선이 이어지지 않도록 구간 번호를 나눈다.
        let segment: Int
        var id: Date { date }
    }

    enum CameraAccess {
        case notDetermined, authorized, denied
    }

    /// 판정 미리보기.
    enum Verdict {
        case waiting, moving, still, noData

        var text: String {
            switch self {
            case .waiting: "판단 중"
            case .moving: "이동 중으로 판정"
            case .still: "멈춤으로 판정"
            case .noData: "밝기 데이터 없음"
            }
        }
    }

    static let labels = ["방", "복도", "엘리베이터", "밖"]

    private(set) var access: CameraAccess = .notDetermined
    private(set) var isMeasuring = false
    private(set) var startedAt: Date?
    private(set) var points: [Point] = []
    private(set) var currentBv: Double?
    private(set) var lastSummary = SecondSummary()
    private(set) var changesInWindow = 0
    private(set) var stillSeconds = 0.0
    private(set) var verdict: Verdict = .waiting
    private(set) var label = ""
    private(set) var errorText: String?
    private(set) var files: [URL] = []

    @ObservationIgnored private let recorder: MeasurementRecorder
    @ObservationIgnored private let meter: BrightnessMeter
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var previousBv: Double?
    @ObservationIgnored private var changeTimes: [Date] = []
    @ObservationIgnored private var lastChangeAt: Date?
    @ObservationIgnored private var segment = 0

    private init() {
        let recorder = MeasurementRecorder()
        self.recorder = recorder
        self.meter = BrightnessMeter { sample in
            recorder.writeFrame(sample)
        }
        refreshAccess()
        refreshFiles()
    }

    // MARK: - 권한

    func refreshAccess() {
        access = switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    private func ensureAccess() async -> Bool {
        refreshAccess()
        switch access {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            refreshAccess()
            AppLogger.shared.info("카메라 권한 요청 결과 · \(granted ? "허용" : "거부")", category: "camera")
            return granted
        }
    }

    // MARK: - 측정

    func start() async {
        guard !isMeasuring else { return }
        errorText = nil

        guard await ensureAccess() else {
            errorText = "카메라 권한이 꺼져 있어요. 설정 > 산책 알람에서 카메라를 켜 주세요."
            AppLogger.shared.warn("카메라 권한이 없어 측정하지 못함", category: "camera")
            return
        }

        let now = Date()
        let base = recorder.begin(at: now, label: label)

        switch await meter.start() {
        case .started:
            break
        case .noCamera:
            recorder.end()
            errorText = "후면 카메라를 찾지 못했어요."
            AppLogger.shared.error("후면 카메라 없음", category: "camera")
            return
        case .configurationFailed(let message):
            recorder.end()
            errorText = "카메라를 켜지 못했어요. \(message)"
            AppLogger.shared.error("카메라 설정 실패 · \(message)", category: "camera")
            return
        }

        isMeasuring = true
        startedAt = now
        points = []
        currentBv = nil
        previousBv = nil
        changeTimes = []
        lastChangeAt = nil
        changesInWindow = 0
        stillSeconds = 0
        verdict = .waiting
        segment = 0
        // 걸으면서 화면이 꺼지면 카메라가 멈춘다.
        UIApplication.shared.isIdleTimerDisabled = true
        AppLogger.shared.info("측정 시작 · \(base)", category: "measure")

        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    func stop() {
        guard isMeasuring else { return }
        tickTask?.cancel()
        tickTask = nil
        meter.stop()
        recorder.end()
        isMeasuring = false
        UIApplication.shared.isIdleTimerDisabled = false
        let seconds = Int(Date().timeIntervalSince(startedAt ?? Date()))
        AppLogger.shared.info("측정 멈춤 · \(seconds)초", category: "measure")
        // 파일 닫기가 끝난 뒤 목록을 다시 읽는다.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.refreshFiles()
        }
    }

    /// 걸으면서 지금 어느 구간인지 표시한다. 같은 걸 다시 누르면 지운다.
    func toggleLabel(_ name: String) {
        label = (label == name) ? "" : name
        recorder.setLabel(label)
        if isMeasuring {
            AppLogger.shared.info("구간 표시 · \(label.isEmpty ? "없음" : label)", category: "measure")
        }
    }

    func refreshFiles() {
        files = MeasurementRecorder.allFiles()
    }

    func deleteAllFiles() {
        MeasurementRecorder.deleteAll()
        refreshFiles()
        AppLogger.shared.info("측정 CSV 모두 삭제", category: "measure")
    }

    // MARK: - 1초 판정

    private func tick() {
        let now = Date()
        let summary = meter.drain()
        let b = summary.meanBv

        var delta: Double?
        var significant = false
        if let b, let previousBv {
            delta = b - previousBv
            significant = abs(b - previousBv) >= Detection.deltaBv
        }
        if let b {
            previousBv = b
        } else if points.last?.bv != nil {
            segment += 1
        }

        if significant {
            changeTimes.append(now)
            lastChangeAt = now
        }
        changeTimes.removeAll { now.timeIntervalSince($0) > Detection.windowSec }
        changesInWindow = changeTimes.count
        stillSeconds = now.timeIntervalSince(lastChangeAt ?? startedAt ?? now)

        if b == nil {
            verdict = .noData
        } else if changesInWindow >= Detection.minChanges {
            verdict = .moving
        } else if stillSeconds >= Detection.stillSec {
            verdict = .still
        } else {
            verdict = .waiting
        }

        currentBv = b
        lastSummary = summary
        points.append(Point(date: now, bv: b, significant: significant, segment: segment))
        points.removeAll { now.timeIntervalSince($0.date) > 60 }

        recorder.writeSecond(SecondRow(
            date: now,
            meanBv: b,
            delta: delta,
            significant: significant,
            changesInWindow: changesInWindow,
            frames: summary.frameCount,
            exifFrames: summary.exifCount,
            appState: Self.appState()
        ))
    }

    private static func appState() -> String {
        switch UIApplication.shared.applicationState {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }
}
