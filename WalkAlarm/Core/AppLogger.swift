import Foundation
import OSLog

/// 앱 내부 파일에 남기는 로그.
///
/// 개발자가 맥이 없어 Xcode 콘솔을 볼 수 없으므로, 모든 기록은
/// `Documents/Logs/walkalarm-yyyy-MM-dd.log` 파일에 쌓고
/// 디버그 화면에서 보거나 공유 시트로 내보낸다.
///
/// 카메라 콜백 등 백그라운드 스레드에서도 호출되므로 스레드 안전하게 만들었다.
/// 날짜 포맷은 `DateFormatter`를 공유하지 않도록 `Calendar`로 직접 만든다.
final class AppLogger: @unchecked Sendable {

    static let shared = AppLogger()

    enum Level: String, Sendable, CaseIterable {
        case debug = "DEBUG"
        case info  = "INFO"
        case state = "STATE"
        case warn  = "WARN"
        case error = "ERROR"
    }

    private let queue = DispatchQueue(label: "com.geumdongyup.walkalarm.logger", qos: .utility)
    private let osLogger = Logger(subsystem: "com.geumdongyup.walkalarm", category: "app")
    private let fileManager = FileManager.default

    private init() {
        queue.async { [self] in
            try? fileManager.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - 경로

    /// 로그 파일이 모이는 폴더.
    static var directoryURL: URL {
        URL.documentsDirectory.appending(path: "Logs", directoryHint: .isDirectory)
    }

    /// 해당 날짜의 로그 파일 경로. 하루에 한 파일씩 쌓인다.
    static func fileURL(for date: Date = Date()) -> URL {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let name = String(format: "walkalarm-%04d-%02d-%02d.log",
                          c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return directoryURL.appending(path: name)
    }

    /// 오늘 로그 파일 경로.
    var currentFileURL: URL { Self.fileURL() }

    /// 남아 있는 모든 로그 파일(최신 날짜가 먼저).
    func allFileURLs() -> [URL] {
        let urls = (try? fileManager.contentsOfDirectory(at: Self.directoryURL,
                                                         includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// 오늘 로그 파일 크기를 사람이 읽을 수 있는 문자열로.
    func currentFileSizeText() -> String {
        let attrs = try? fileManager.attributesOfItem(atPath: currentFileURL.path(percentEncoded: false))
        let bytes = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - 시각 문자열

    /// `12:34:56.789` 형태. 스레드 안전하도록 DateFormatter를 쓰지 않는다.
    static func stamp(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let millis = (c.nanosecond ?? 0) / 1_000_000
        return String(format: "%02d:%02d:%02d.%03d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0, millis)
    }

    /// `2026-09-17 12:34:56.789` 형태. 파일에 쓸 때 사용한다.
    static func fullStamp(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d ", c.year ?? 0, c.month ?? 0, c.day ?? 0) + stamp(date)
    }

    // MARK: - 기록

    func log(_ message: String, level: Level = .info, category: String = "app") {
        let date = Date()

        // 1) 화면에 실시간으로 보여줄 메모리 버퍼
        LogStore.shared.append(
            LogStore.Line(date: date, level: level, category: category, message: message)
        )

        // 2) 혹시 맥이 생기면 쓸 수 있도록 시스템 로그에도 남긴다
        let line = "[\(category)] \(message)"
        switch level {
        case .error: osLogger.error("\(line, privacy: .public)")
        case .warn:  osLogger.warning("\(line, privacy: .public)")
        case .debug: osLogger.debug("\(line, privacy: .public)")
        default:     osLogger.info("\(line, privacy: .public)")
        }

        // 3) 파일
        let padded = level.rawValue.padding(toLength: 5, withPad: " ", startingAt: 0)
        let text = "\(Self.fullStamp(date)) \(padded) [\(category)] \(message)\n"
        queue.async { [self] in
            appendToFile(text, url: Self.fileURL(for: date))
        }
    }

    func debug(_ message: String, category: String = "app") { log(message, level: .debug, category: category) }
    func info(_ message: String, category: String = "app")  { log(message, level: .info, category: category) }
    func state(_ message: String, category: String = "state") { log(message, level: .state, category: category) }
    func warn(_ message: String, category: String = "app")  { log(message, level: .warn, category: category) }
    func error(_ message: String, category: String = "app") { log(message, level: .error, category: category) }

    private func appendToFile(_ text: String, url: URL) {
        guard let data = text.data(using: .utf8) else { return }
        try? fileManager.createDirectory(at: Self.directoryURL, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: url.path(percentEncoded: false)) {
            fileManager.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    // MARK: - 읽기 / 지우기

    /// 파일 내용을 읽어 온다. 너무 길면 뒤쪽(최신)만 남긴다.
    func readFile(_ url: URL, maxBytes: Int = 400_000) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        if data.count <= maxBytes {
            return String(decoding: data, as: UTF8.self)
        }
        let tail = data.suffix(maxBytes)
        return "… (앞부분 생략)\n" + String(decoding: tail, as: UTF8.self)
    }

    /// 로그 파일 전부 삭제 + 화면 버퍼 비우기.
    func clearAll() {
        let urls = allFileURLs()
        queue.async { [self] in
            for url in urls { try? fileManager.removeItem(at: url) }
        }
        LogStore.shared.clear()
        log("로그를 모두 지웠습니다.", level: .info, category: "logger")
    }
}
