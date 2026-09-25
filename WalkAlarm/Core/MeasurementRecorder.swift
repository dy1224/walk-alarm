import Foundation

/// 1초 판정 한 줄.
struct SecondRow: Sendable {
    let date: Date
    let meanBv: Double?
    let delta: Double?
    let significant: Bool
    let changesInWindow: Int
    let frames: Int
    let exifFrames: Int
    let appState: String
}

/// 밝기 측정 기록을 CSV로 남긴다.
///
/// 측정 한 번마다 파일 두 개를 만든다.
/// - `bv-날짜-시각-seconds.csv`: 1초 평균 B(t), 직전과의 차, 유의미한 변화 여부. 4단계 판정값을 맞출 때 본다.
/// - `bv-날짜-시각-frames.csv`: 프레임마다 EXIF Bv·계산 Bv·ISO·노출시간·조리개. 원자료.
///
/// 걸으면서 누른 구간 표시(방·복도·엘리베이터·밖)를 두 파일의 `label` 열에 같이 남긴다.
/// 파일 쓰기는 전용 큐에서만 한다.
final class MeasurementRecorder: @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.geumdongyup.walkalarm.recorder", qos: .utility)
    private var framesHandle: FileHandle?
    private var secondsHandle: FileHandle?
    private var startDate: Date?
    private var label = ""
    private var frameRows = 0
    private var secondRows = 0

    static var directoryURL: URL {
        URL.documentsDirectory.appending(path: "Measurements", directoryHint: .isDirectory)
    }

    /// 남아 있는 CSV 파일(최신이 먼저).
    static func allFiles() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == "csv" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func deleteAll() {
        for url in allFiles() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - 기록

    /// 새 측정을 시작한다. 파일 이름 앞부분을 돌려준다.
    func begin(at date: Date, label: String) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let base = String(
            format: "bv-%04d%02d%02d-%02d%02d%02d",
            c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0
        )
        queue.async { [self] in
            closeFiles()
            try? FileManager.default.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)
            framesHandle = Self.makeFile(
                "\(base)-frames.csv",
                header: "time,elapsed_s,bv_exif,bv_calc,iso,exposure_s,f_number,label"
            )
            secondsHandle = Self.makeFile(
                "\(base)-seconds.csv",
                header: "time,elapsed_s,bv_mean,delta_bv,significant,changes_in_window,frames,exif_frames,label,app_state"
            )
            startDate = date
            self.label = label
            frameRows = 0
            secondRows = 0
        }
        return base
    }

    func setLabel(_ label: String) {
        queue.async { [self] in
            self.label = label
        }
    }

    func writeFrame(_ s: FrameSample) {
        queue.async { [self] in
            guard let handle = framesHandle, let startDate else { return }
            let line = [
                AppLogger.stamp(s.date),
                Self.num(s.date.timeIntervalSince(startDate), 3),
                Self.num(s.exifBv, 3),
                Self.num(s.calcBv, 3),
                Self.num(s.iso, 0),
                Self.num(s.exposure, 6),
                Self.num(s.fNumber, 2),
                label,
            ].joined(separator: ",")
            Self.write(line, to: handle)
            frameRows += 1
        }
    }

    func writeSecond(_ r: SecondRow) {
        queue.async { [self] in
            guard let handle = secondsHandle, let startDate else { return }
            let line = [
                AppLogger.stamp(r.date),
                Self.num(r.date.timeIntervalSince(startDate), 1),
                Self.num(r.meanBv, 3),
                Self.num(r.delta, 3),
                r.significant ? "1" : "0",
                String(r.changesInWindow),
                String(r.frames),
                String(r.exifFrames),
                label,
                r.appState,
            ].joined(separator: ",")
            Self.write(line, to: handle)
            secondRows += 1
        }
    }

    /// 측정을 끝내고 파일을 닫는다.
    func end() {
        queue.async { [self] in
            if framesHandle != nil {
                AppLogger.shared.info("CSV 저장 · 1초 \(secondRows)줄 · 프레임 \(frameRows)줄", category: "measure")
            }
            closeFiles()
        }
    }

    // MARK: - 내부

    private func closeFiles() {
        try? framesHandle?.close()
        try? secondsHandle?.close()
        framesHandle = nil
        secondsHandle = nil
        startDate = nil
    }

    private static func makeFile(_ name: String, header: String) -> FileHandle? {
        let url = directoryURL.appending(path: name)
        FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: Data((header + "\n").utf8))
        let handle = try? FileHandle(forWritingTo: url)
        _ = try? handle?.seekToEnd()
        return handle
    }

    private static func write(_ line: String, to handle: FileHandle) {
        try? handle.write(contentsOf: Data((line + "\n").utf8))
    }

    private static func num(_ value: Double?, _ digits: Int) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.\(digits)f", value)
    }
}
