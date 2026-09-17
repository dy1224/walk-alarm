import Foundation
import Observation

/// 디버그 화면에서 실시간으로 보여줄 로그 버퍼.
///
/// `AppLogger`가 파일에 쓰는 것과 별개로 최근 줄만 메모리에 들고 있는다.
/// 백그라운드 스레드에서 들어오는 기록도 메인에서만 반영해 UI 갱신을 안전하게 한다.
@Observable
final class LogStore: @unchecked Sendable {

    struct Line: Identifiable, Sendable {
        let id = UUID()
        let date: Date
        let level: AppLogger.Level
        let category: String
        let message: String

        /// 화면·복사용 한 줄.
        var display: String {
            "\(AppLogger.stamp(date))  \(level.rawValue.padding(toLength: 5, withPad: " ", startingAt: 0))  [\(category)] \(message)"
        }
    }

    static let shared = LogStore()

    /// 최근 로그(오래된 것 → 최신 순).
    private(set) var lines: [Line] = []
    /// 앱을 켠 뒤 남긴 전체 줄 수.
    private(set) var totalCount: Int = 0

    private let limit = 1_000

    private init() {}

    func append(_ line: Line) {
        if Thread.isMainThread {
            insert(line)
        } else {
            DispatchQueue.main.async { self.insert(line) }
        }
    }

    func clear() {
        if Thread.isMainThread {
            lines.removeAll()
            totalCount = 0
        } else {
            DispatchQueue.main.async {
                self.lines.removeAll()
                self.totalCount = 0
            }
        }
    }

    /// 화면 버퍼 전체를 한 덩어리 텍스트로. 복사할 때 쓴다.
    var joinedText: String {
        lines.map(\.display).joined(separator: "\n")
    }

    private func insert(_ line: Line) {
        lines.append(line)
        totalCount += 1
        if lines.count > limit {
            lines.removeFirst(lines.count - limit)
        }
    }
}
