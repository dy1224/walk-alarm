import SwiftUI

/// iOS 26 Liquid Glass 재질을 쓰는 카드.
///
/// 재질을 한 곳에서만 지정해 두면 전체 톤을 한 번에 바꿀 수 있다.
struct GlassCard<Content: View>: View {

    var cornerRadius: CGFloat = 24
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

/// 라벨과 값을 한 줄로 보여준다. 디버그 화면에서 반복 사용.
struct InfoRow: View {

    let label: String
    let value: String
    var isMono: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(Theme.label)
                .foregroundStyle(Theme.inkSoft)
            Spacer(minLength: 8)
            Text(value)
                .font(isMono ? Theme.mono : Theme.label)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}
