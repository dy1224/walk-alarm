import SwiftUI

/// "새벽으로 나가는 길" 색과 글꼴.
///
/// 배경 색 하나가 방에서 새벽 하늘까지의 이동을 이야기한다.
/// 강조는 배경 그라데이션과 빛의 선에만 쓰고, 나머지는 차분하게 둔다.
enum Theme {

    // MARK: - 색

    /// 이동 전, 앱 기본 배경.
    static let night = Color(hex: 0x0E1224)
    /// 새벽 하늘의 따뜻한 쪽.
    static let dawnWarm = Color(hex: 0xE9B99A)
    /// 새벽 하늘의 찬 쪽.
    static let dawnCool = Color(hex: 0xA7C4DC)
    /// 울림(멈춤 경고)에만 쓴다.
    static let signal = Color(hex: 0xFF5A4E)
    /// 주요 텍스트.
    static let ink = Color(hex: 0xF3F1EC)
    /// 보조 텍스트.
    static let inkSoft = Color(hex: 0xF3F1EC).opacity(0.58)

    // MARK: - 배경

    /// 기본 배경(완전한 Night).
    static var nightBackground: LinearGradient {
        background(progress: 0)
    }

    /// 누적 이동 시간에 따라 깊은 밤에서 새벽 하늘로 밝아지는 배경.
    /// - Parameter progress: 0이면 Night, 1이면 완전한 Dawn.
    static func background(progress: Double) -> LinearGradient {
        let p = min(max(progress, 0), 1)
        // Night에서 출발해 위쪽은 따뜻한 빛, 아래쪽은 찬 하늘로 번진다.
        let top = night.mix(with: dawnWarm, by: p * 0.92)
        let mid = night.mix(with: dawnWarm, by: p * 0.55)
        let bottom = night.mix(with: dawnCool, by: p * 0.75)
        return LinearGradient(
            colors: [top, mid, bottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - 글꼴

    /// 큰 시각 표시: New York(Apple 세리프), 가벼운 굵기.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .thin, design: .serif)
    }

    /// 화면 제목.
    static let title = Font.system(.title3, design: .serif).weight(.regular)
    /// 본문.
    static let body = Font.system(.subheadline, design: .default)
    /// 라벨. 대문자·과한 굵기는 쓰지 않는다.
    static let label = Font.system(.footnote, design: .default)
    /// 로그처럼 자리를 맞춰야 하는 글자.
    static let mono = Font.system(size: 11, weight: .regular, design: .monospaced)
}

extension Color {
    /// `0x0E1224` 형태의 16진수로 색을 만든다.
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
