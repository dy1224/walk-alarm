import Foundation
import Observation

/// 알람 시각 저장소. 알람은 하나만 둔다.
///
/// 1단계에서는 값을 저장하고 화면에 보여주는 것까지만 한다.
/// 실제 예약(AlarmKit)은 2단계에서 이 값을 읽어 붙인다.
///
/// 값이 바뀔 때 UserDefaults에 쓰고 로그를 남겨야 하는데, `@Observable`은 저장
/// 프로퍼티를 계산 프로퍼티로 바꾸므로 `didSet`을 쓸 수 없다. 대신 저장은
/// `@ObservationIgnored` 뒤에 숨기고 `access`/`withMutation`으로 직접 알린다.
@Observable
final class AlarmSettings: @unchecked Sendable {

    static let shared = AlarmSettings()

    private enum Key {
        static let isEnabled = "alarm.isEnabled"
        static let hour = "alarm.hour"
        static let minute = "alarm.minute"
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var storedIsEnabled: Bool
    @ObservationIgnored private var storedHour: Int
    @ObservationIgnored private var storedMinute: Int

    var isEnabled: Bool {
        get {
            access(keyPath: \.isEnabled)
            return storedIsEnabled
        }
        set {
            guard storedIsEnabled != newValue else { return }
            withMutation(keyPath: \.isEnabled) { storedIsEnabled = newValue }
            defaults.set(newValue, forKey: Key.isEnabled)
            AppLogger.shared.info("알람 \(newValue ? "켜기" : "끄기") · \(timeText)", category: "settings")
        }
    }

    var hour: Int {
        get {
            access(keyPath: \.hour)
            return storedHour
        }
        set {
            guard storedHour != newValue else { return }
            withMutation(keyPath: \.hour) { storedHour = newValue }
            defaults.set(newValue, forKey: Key.hour)
            AppLogger.shared.info("알람 시각 변경 · \(timeText)", category: "settings")
        }
    }

    var minute: Int {
        get {
            access(keyPath: \.minute)
            return storedMinute
        }
        set {
            guard storedMinute != newValue else { return }
            withMutation(keyPath: \.minute) { storedMinute = newValue }
            defaults.set(newValue, forKey: Key.minute)
            AppLogger.shared.info("알람 시각 변경 · \(timeText)", category: "settings")
        }
    }

    private init() {
        defaults.register(defaults: [
            Key.isEnabled: false,
            Key.hour: 7,
            Key.minute: 0,
        ])
        storedIsEnabled = defaults.bool(forKey: Key.isEnabled)
        storedHour = defaults.integer(forKey: Key.hour)
        storedMinute = defaults.integer(forKey: Key.minute)
    }

    /// 큰 세리프 표시용. 예: `07:00`
    var timeText: String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// DatePicker와 주고받을 Date. 날짜 부분은 오늘로 둔다.
    var alarmDate: Date {
        get {
            let today = Calendar.current.startOfDay(for: Date())
            return Calendar.current.date(byAdding: DateComponents(hour: hour, minute: minute), to: today) ?? today
        }
        set {
            let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            hour = c.hour ?? hour
            minute = c.minute ?? minute
        }
    }

    /// 다음 알람이 울릴 시각. 오늘 그 시각이 지났으면 내일.
    var nextFireDate: Date {
        let now = Date()
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        let candidate = calendar.date(from: components) ?? now
        if candidate > now { return candidate }
        return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
    }

    /// 예: `13시간 20분 뒤`
    var timeUntilNextText: String {
        let seconds = Int(nextFireDate.timeIntervalSinceNow)
        guard seconds > 0 else { return "곧" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 { return "\(hours)시간 \(minutes)분 뒤" }
        if minutes > 0 { return "\(minutes)분 뒤" }
        return "1분 안에"
    }
}
