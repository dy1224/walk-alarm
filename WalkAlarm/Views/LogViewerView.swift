import SwiftUI

/// 이번 실행에서 남긴 로그를 한 줄씩 보여준다.
///
/// 파일 전체가 아니라 메모리 버퍼(최근 1,000줄)를 보여주므로 실시간으로 갱신된다.
/// 지난 날짜까지 보려면 디버그 화면에서 파일을 내보내면 된다.
struct LogViewerView: View {

    @State private var store = LogStore.shared
    @State private var newestFirst = false

    private var displayLines: [LogStore.Line] {
        newestFirst ? Array(store.lines.reversed()) : store.lines
    }

    var body: some View {
        ZStack {
            Theme.nightBackground
                .ignoresSafeArea()

            if store.lines.isEmpty {
                Text("아직 로그가 없어요.")
                    .font(Theme.label)
                    .foregroundStyle(Theme.inkSoft)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 5) {
                            ForEach(displayLines) { line in
                                Text(line.display)
                                    .font(Theme.mono)
                                    .foregroundStyle(color(for: line.level))
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(line.id)
                            }
                        }
                        .padding(16)
                    }
                    .onAppear { scrollToEnd(proxy) }
                    .onChange(of: store.lines.count) { _, _ in scrollToEnd(proxy) }
                }
            }
        }
        .navigationTitle("로그 \(store.lines.count)줄")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newestFirst.toggle()
                } label: {
                    Image(systemName: newestFirst ? "arrow.up" : "arrow.down")
                }
                .accessibilityLabel(newestFirst ? "최신이 위" : "최신이 아래")
            }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard !newestFirst, let last = store.lines.last else { return }
        proxy.scrollTo(last.id, anchor: .bottom)
    }

    private func color(for level: AppLogger.Level) -> Color {
        switch level {
        case .error: Theme.signal
        case .warn: Theme.dawnWarm
        case .state: Theme.dawnCool
        case .debug: Theme.inkSoft
        case .info: Theme.ink.opacity(0.85)
        }
    }
}

#Preview {
    NavigationStack {
        LogViewerView()
    }
    .preferredColorScheme(.dark)
}
