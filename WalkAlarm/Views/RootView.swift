import SwiftUI

/// 알람 / 측정 / 디버그 탭. 울림·해제 완료 화면은 4단계에서 붙는다.
struct RootView: View {

    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Screen = .alarm

    private enum Screen: Hashable {
        case alarm, measure, debug
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("알람", systemImage: "alarm", value: Screen.alarm) {
                HomeView()
            }
            Tab("측정", systemImage: "sun.max", value: Screen.measure) {
                MeasureView()
            }
            Tab("디버그", systemImage: "waveform.path.ecg", value: Screen.debug) {
                DebugView()
            }
        }
        .task {
            AlarmScheduler.shared.start()
            AlarmScheduler.shared.requestSync()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // 앱을 벗어나면 밝기 데이터가 끊긴다. 4단계 판정에서 중요한 신호라 지금부터 기록해 둔다.
            AppLogger.shared.state("scenePhase = \(describe(phase))", category: "lifecycle")
            if phase == .active {
                // 설정 앱에서 권한을 바꾸고 돌아왔을 수 있다.
                AlarmScheduler.shared.refreshAuthorization()
                AlarmScheduler.shared.refreshAlarms()
            }
        }
    }

    private func describe(_ phase: ScenePhase) -> String {
        switch phase {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }
}

#Preview {
    RootView()
        .preferredColorScheme(.dark)
}
