import AlarmKit
import AppIntents

/// 시스템 알람 화면의 "미션 시작" 버튼. 알람 화면의 유일한 버튼(멈춤 버튼 자리)이다.
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
