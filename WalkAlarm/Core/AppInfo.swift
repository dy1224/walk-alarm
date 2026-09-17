import Foundation

/// 디버그 화면에 보여줄 앱·기기 정보.
///
/// 어떤 빌드를 설치했는지 실기기에서 바로 확인할 수 있게 한다.
/// `UIDevice`는 메인 액터에 묶여 있어 초기화 시점에 쓰기 불편하므로 쓰지 않는다.
enum AppInfo {

    static var displayName: String {
        info("CFBundleDisplayName") ?? info("CFBundleName") ?? "WalkAlarm"
    }

    static var version: String { info("CFBundleShortVersionString") ?? "0" }

    static var build: String { info("CFBundleVersion") ?? "0" }

    static var bundleID: String { Bundle.main.bundleIdentifier ?? "-" }

    static var versionLine: String { "v\(version) (build \(build))" }

    /// 예: `26.0.1`
    static var systemVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    /// 예: `iPhone15,2`
    static var deviceModel: String {
        var system = utsname()
        uname(&system)
        let machine = withUnsafeBytes(of: &system.machine) { raw -> String in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
        return machine.isEmpty ? "unknown" : machine
    }

    private static func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
