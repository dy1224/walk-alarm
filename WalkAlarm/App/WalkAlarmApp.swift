import SwiftUI

@main
struct WalkAlarmApp: App {

    init() {
        AppLogger.shared.info(
            "앱 시작 · \(AppInfo.displayName) \(AppInfo.versionLine) · iOS \(AppInfo.systemVersion) · \(AppInfo.deviceModel)",
            category: "lifecycle"
        )
        AppLogger.shared.debug("로그 파일: \(AppLogger.shared.currentFileURL.path(percentEncoded: false))", category: "lifecycle")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.dawnWarm)
        }
    }
}
