import AlarmKit
import Foundation
import Observation
import SwiftUI

/// AlarmKit 알람에 붙는 메타데이터. 2단계에서는 담을 것이 없다.
struct WalkAlarmMetadata: AlarmMetadata {}

/// AlarmKit 예약을 한 곳에서 맡는다.
///
/// 2단계 범위: 매일 알람 1개 + 디버그용 "1분 뒤 테스트 알람".
/// 시스템 알람 화면에는 "끄기"와 "미션 시작"(누르면 앱이 열림) 버튼을 둔다.
/// 연쇄 알람 15개는 4단계에서 여기에 붙인다.
///
/// 예약·취소는 `await`를 끼고 일어나므로, 토글을 빠르게 여러 번 눌러도 알람이
/// 겹치지 않도록 동기화 요청을 하나의 체인으로 줄 세운다.
@MainActor
@Observable
final class AlarmScheduler {

    static let shared = AlarmScheduler()

    enum Authorization: Equatable {
        case notDetermined, authorized, denied

        var text: String {
            switch self {
            case .notDetermined: "아직 묻지 않음"
            case .authorized: "허용됨"
            case .denied: "꺼져 있음"
            }
        }
    }

    /// 디버그 화면에 보여줄 알람 한 줄.
    struct Entry: Identifiable, Equatable {
        let id: UUID
        let kind: String
        let scheduleText: String
        let stateText: String
    }

    private(set) var authorization: Authorization = .notDetermined
    private(set) var entries: [Entry] = []
    private(set) var lastError: String?
    /// 시스템 알람 화면의 "미션 시작"으로 앱이 열린 시각.
    private(set) var lastMissionStart: Date?

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var syncChain: Task<Void, Never>?
    @ObservationIgnored private var lastStates: [UUID: String] = [:]

    private enum Key {
        static let dailyID = "alarmkit.dailyID"
        static let dailySignature = "alarmkit.dailySignature"
    }

    private static let everyDay: [Locale.Weekday] = [
        .sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday,
    ]

    private init() {}

    // MARK: - 상태

    private var dailyID: UUID? {
        get { defaults.string(forKey: Key.dailyID).flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: Key.dailyID) }
    }

    /// 매일 알람이 AlarmKit에 실제로 올라가 있는지.
    var isDailyScheduled: Bool {
        guard let dailyID else { return false }
        return entries.contains { $0.id == dailyID }
    }

    // MARK: - 시작

    /// 앱이 뜰 때 한 번 부른다. 권한·예약 목록을 읽고 알람 상태 변화를 구독한다.
    func start() {
        refreshAuthorization()
        refreshAlarms()
        AppLogger.shared.info(
            "AlarmKit 권한 · \(authorization.text) · 예약 \(entries.count)개",
            category: "alarm"
        )

        guard updatesTask == nil else { return }
        let updates = AlarmManager.shared.alarmUpdates
        updatesTask = Task { [weak self] in
            for await alarms in updates {
                self?.receive(alarms)
            }
        }
    }

    func refreshAuthorization() {
        authorization = Self.map(AlarmManager.shared.authorizationState)
    }

    func refreshAlarms() {
        receive((try? AlarmManager.shared.alarms) ?? [])
    }

    // MARK: - 권한

    /// 권한이 없으면 묻는다. 허용되면 true.
    func requestAuthorizationIfNeeded() async -> Bool {
        refreshAuthorization()
        switch authorization {
        case .authorized:
            return true
        case .denied:
            AppLogger.shared.warn("AlarmKit 권한이 꺼져 있어 예약하지 못함", category: "alarm")
            return false
        case .notDetermined:
            do {
                let state = try await AlarmManager.shared.requestAuthorization()
                authorization = Self.map(state)
                AppLogger.shared.info("AlarmKit 권한 요청 결과 · \(authorization.text)", category: "alarm")
                return authorization == .authorized
            } catch {
                report("AlarmKit 권한 요청 실패", error)
                return false
            }
        }
    }

    // MARK: - 매일 알람

    /// 저장된 설정에 맞춰 매일 알람을 다시 맞춘다.
    ///
    /// 요청은 체인으로 줄 세우고, 실행 시점의 최신 설정을 읽는다.
    /// 이미 같은 시각으로 올라가 있으면 아무것도 하지 않는다.
    func requestSync() {
        let previous = syncChain
        syncChain = Task {
            await previous?.value
            await syncDaily()
        }
    }

    private func syncDaily() async {
        let settings = AlarmSettings.shared
        let signature = settings.timeText
        refreshAlarms()

        if settings.isEnabled,
           isDailyScheduled,
           defaults.string(forKey: Key.dailySignature) == signature {
            return
        }

        if let id = dailyID {
            do {
                try AlarmManager.shared.cancel(id: id)
                AppLogger.shared.info("매일 알람 예약 취소 · \(Self.short(id))", category: "alarm")
            } catch {
                AppLogger.shared.debug("이전 매일 알람이 이미 없음 · \(Self.short(id))", category: "alarm")
            }
            dailyID = nil
            defaults.removeObject(forKey: Key.dailySignature)
        }

        guard settings.isEnabled else {
            refreshAlarms()
            return
        }
        guard await requestAuthorizationIfNeeded() else {
            refreshAlarms()
            return
        }

        let id = UUID()
        let schedule = Alarm.Schedule.relative(
            Alarm.Schedule.Relative(
                time: Alarm.Schedule.Relative.Time(hour: settings.hour, minute: settings.minute),
                repeats: .weekly(Self.everyDay)
            )
        )
        do {
            _ = try await AlarmManager.shared.schedule(
                id: id,
                configuration: Self.makeConfiguration(id: id, schedule: schedule, title: "산책 갈 시간이에요")
            )
            dailyID = id
            defaults.set(signature, forKey: Key.dailySignature)
            lastError = nil
            AppLogger.shared.info("매일 알람 예약 · \(signature) · \(Self.short(id))", category: "alarm")
        } catch {
            report("매일 알람 예약 실패", error)
        }
        refreshAlarms()
    }

    // MARK: - 테스트 알람

    /// 지금부터 `seconds`초 뒤에 한 번 울리는 알람. 잠금·무음 상태 확인용.
    func scheduleTest(after seconds: TimeInterval) async {
        guard await requestAuthorizationIfNeeded() else { return }

        let id = UUID()
        let fireDate = Date().addingTimeInterval(seconds)
        do {
            _ = try await AlarmManager.shared.schedule(
                id: id,
                configuration: Self.makeConfiguration(id: id, schedule: .fixed(fireDate), title: "테스트 알람이에요")
            )
            lastError = nil
            AppLogger.shared.info(
                "테스트 알람 예약 · \(AppLogger.stamp(fireDate)) · \(Self.short(id))",
                category: "alarm"
            )
        } catch {
            report("테스트 알람 예약 실패", error)
        }
        refreshAlarms()
    }

    /// 매일 알람을 뺀 나머지(테스트 알람)를 모두 취소한다.
    func cancelTests() {
        for entry in entries where entry.id != dailyID {
            do {
                try AlarmManager.shared.cancel(id: entry.id)
                AppLogger.shared.info("테스트 알람 취소 · \(Self.short(entry.id))", category: "alarm")
            } catch {
                report("테스트 알람 취소 실패", error)
            }
        }
        refreshAlarms()
    }

    // MARK: - 버튼 인텐트에서 호출

    /// 시스템 알람 화면에서 "미션 시작"을 눌러 앱이 열렸다.
    func handleMissionStart(alarmID: String) {
        lastMissionStart = Date()
        AppLogger.shared.state("미션 시작 버튼으로 앱 열림 · \(alarmID.prefix(8))", category: "alarm")
        stopIfAlerting(alarmID: alarmID)
    }

    /// 시스템 알람 화면에서 "끄기"를 눌렀다.
    func handleStop(alarmID: String) {
        AppLogger.shared.state("시스템 알람 끄기 버튼 · \(alarmID.prefix(8))", category: "alarm")
        stopIfAlerting(alarmID: alarmID)
    }

    private func stopIfAlerting(alarmID: String) {
        guard let id = UUID(uuidString: alarmID) else { return }
        // 시스템이 이미 멈췄으면 오류가 나므로 무시한다.
        try? AlarmManager.shared.stop(id: id)
        refreshAlarms()
    }

    // MARK: - 내부

    nonisolated private static func makeConfiguration(
        id: UUID,
        schedule: Alarm.Schedule,
        title: LocalizedStringResource
    ) -> AlarmManager.AlarmConfiguration<WalkAlarmMetadata> {
        let alert = AlarmPresentation.Alert(
            title: title,
            stopButton: AlarmButton(text: "끄기", textColor: Theme.ink, systemImageName: "stop.fill"),
            secondaryButton: AlarmButton(text: "미션 시작", textColor: Theme.night, systemImageName: "figure.walk"),
            secondaryButtonBehavior: .custom
        )
        let attributes = AlarmAttributes<WalkAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: WalkAlarmMetadata(),
            tintColor: Theme.dawnWarm
        )
        return AlarmManager.AlarmConfiguration<WalkAlarmMetadata>(
            countdownDuration: nil,
            schedule: schedule,
            attributes: attributes,
            stopIntent: StopAlarmIntent(alarmID: id.uuidString),
            secondaryIntent: StartMissionIntent(alarmID: id.uuidString)
        )
    }

    /// AlarmKit이 알려 준 목록으로 화면을 갱신하고, 상태가 바뀐 알람만 로그에 남긴다.
    private func receive(_ alarms: [Alarm]) {
        let daily = dailyID
        var next: [UUID: String] = [:]
        entries = alarms.map { alarm in
            let kind = alarm.id == daily ? "매일" : "테스트"
            let state = Self.describe(alarm.state)
            next[alarm.id] = state
            if lastStates[alarm.id] != state {
                AppLogger.shared.state("알람 상태 · \(kind) · \(Self.short(alarm.id)) · \(state)", category: "alarm")
            }
            return Entry(
                id: alarm.id,
                kind: kind,
                scheduleText: Self.describe(alarm.schedule),
                stateText: state
            )
        }
        for id in lastStates.keys where next[id] == nil {
            AppLogger.shared.state("알람 목록에서 빠짐 · \(Self.short(id))", category: "alarm")
        }
        lastStates = next
    }

    private func report(_ what: String, _ error: any Error) {
        lastError = "\(what): \(error.localizedDescription)"
        AppLogger.shared.error("\(what) · \(error)", category: "alarm")
    }

    private static func map(_ state: AlarmManager.AuthorizationState) -> Authorization {
        switch state {
        case .authorized: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    private static func describe(_ state: Alarm.State) -> String {
        switch state {
        case .scheduled: "scheduled"
        case .countdown: "countdown"
        case .paused: "paused"
        case .alerting: "alerting"
        @unknown default: "unknown"
        }
    }

    private static func describe(_ schedule: Alarm.Schedule?) -> String {
        switch schedule {
        case .fixed(let date):
            return "한 번 · \(AppLogger.stamp(date).prefix(8))"
        case .relative(let relative):
            return String(format: "매일 · %02d:%02d", relative.time.hour, relative.time.minute)
        case nil:
            return "일정 없음"
        @unknown default:
            return "알 수 없음"
        }
    }

    private static func short(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}
