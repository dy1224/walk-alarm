import AlarmKit
import AppIntents

/// 시스템 알람 화면의 "미션 시작" 버튼.
///
/// 누르면 앱이 열린다(`openAppWhenRun`). 2단계에서는 열린 것을 기록하고 시스템 알람을 멈춘다.
/// 4단계에서는 여기서 앱 내 울림 화면으로 넘어간다.
struct StartMissionIntent: LiveActivityIntent {

    static let title: LocalizedStringResource = "미션 시작"
    static let openAppWhenRun: Bool = true
    static let isDiscoverable: Bool = false

    @Parameter(title: "alarmID")
    var alarmID: String

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    init() {
        self.alarmID = ""
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AlarmScheduler.shared.handleMissionStart(alarmID: alarmID)
        return .result()
    }
}

/// 시스템 알람 화면의 "끄기" 버튼. 눌렸다는 사실을 로그로 남긴다.
struct StopAlarmIntent: LiveActivityIntent {

    static let title: LocalizedStringResource = "알람 끄기"
    static let isDiscoverable: Bool = false

    @Parameter(title: "alarmID")
    var alarmID: String

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    init() {
        self.alarmID = ""
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AlarmScheduler.shared.handleStop(alarmID: alarmID)
        return .result()
    }
}
