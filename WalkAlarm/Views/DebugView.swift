import SwiftUI

/// 디버그 화면.
///
/// 실행 중 콘솔을 볼 수 없으므로 이 화면이 유일한 관측 창구다.
/// 1단계에서는 앱 정보와 로그 보기·내보내기까지. Bv 그래프와 판정 파라미터는 3·4단계에서 붙는다.
struct DebugView: View {

    @State private var store = LogStore.shared
    @State private var isClearConfirmOpen = false
    @State private var fileSizeText = "-"

    private let logger = AppLogger.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        appInfoCard
                        logCard
                        logFilesCard
                        nextStageCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("디버그")
            .toolbarTitleDisplayMode(.inline)
            .onAppear { refresh() }
        }
    }

    // MARK: - 앱 정보

    private var appInfoCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("앱 정보")
                InfoRow(label: "이름", value: AppInfo.displayName)
                InfoRow(label: "버전", value: AppInfo.versionLine)
                InfoRow(label: "번들 ID", value: AppInfo.bundleID, isMono: true)
                InfoRow(label: "iOS", value: AppInfo.systemVersion)
                InfoRow(label: "기기", value: AppInfo.deviceModel, isMono: true)
            }
        }
    }

    // MARK: - 로그

    private var logCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle("로그")
                InfoRow(label: "이번 실행에서 남긴 줄", value: "\(store.totalCount)줄")
                InfoRow(label: "오늘 로그 파일 크기", value: fileSizeText)

                recentLines

                VStack(spacing: 10) {
                    NavigationLink {
                        LogViewerView()
                    } label: {
                        actionLabel("로그 전체 보기", systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(.glass)

                    ShareLink(item: logger.currentFileURL) {
                        actionLabel("로그 파일 내보내기", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.glass)

                    Button {
                        logger.info("테스트 로그 · \(AppLogger.stamp(Date()))", category: "debug")
                        logger.warn("테스트 경고", category: "debug")
                        refresh()
                    } label: {
                        actionLabel("테스트 로그 남기기", systemImage: "plus.circle")
                    }
                    .buttonStyle(.glass)

                    Button {
                        isClearConfirmOpen = true
                    } label: {
                        actionLabel("로그 지우기", systemImage: "trash")
                    }
                    .buttonStyle(.glass)
                    .foregroundStyle(Theme.signal)
                }
                .font(Theme.label)
                .foregroundStyle(Theme.ink)
            }
        }
        .confirmationDialog("로그를 모두 지울까요?", isPresented: $isClearConfirmOpen, titleVisibility: .visible) {
            Button("지우기", role: .destructive) {
                logger.clearAll()
                refresh()
            }
            Button("그만두기", role: .cancel) {}
        } message: {
            Text("저장된 로그 파일과 화면에 보이는 기록이 함께 사라집니다.")
        }
    }

    private var recentLines: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.lines.isEmpty {
                Text("아직 로그가 없어요.")
                    .font(Theme.label)
                    .foregroundStyle(Theme.inkSoft)
            } else {
                ForEach(store.lines.suffix(8)) { line in
                    Text(line.display)
                        .font(Theme.mono)
                        .foregroundStyle(color(for: line.level))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.22), in: .rect(cornerRadius: 14))
    }

    // MARK: - 로그 파일 목록

    private var logFilesCard: some View {
        let files = logger.allFileURLs()
        return GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("로그 파일")
                if files.isEmpty {
                    Text("아직 저장된 파일이 없어요.")
                        .font(Theme.label)
                        .foregroundStyle(Theme.inkSoft)
                } else {
                    ForEach(files, id: \.self) { url in
                        HStack(spacing: 12) {
                            Text(url.lastPathComponent)
                                .font(Theme.mono)
                                .foregroundStyle(Theme.ink)
                            Spacer(minLength: 8)
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .foregroundStyle(Theme.dawnCool)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 다음 단계

    private var nextStageCard: some View {
        GlassCard(cornerRadius: 20, padding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                cardTitle("다음 단계")
                stageLine("2단계", "AlarmKit 알람 1개 + 알람 화면의 '미션 시작' 버튼")
                stageLine("3단계", "카메라 Bv 측정 + 실시간 그래프 + CSV 내보내기")
                stageLine("4단계", "상태 머신 + 앱 내 울림/일시정지 + 연쇄 알람 + '도착했어요'")
            }
        }
    }

    private func stageLine(_ stage: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(stage)
                .font(Theme.label)
                .foregroundStyle(Theme.dawnCool)
                .frame(width: 48, alignment: .leading)
            Text(text)
                .font(Theme.label)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 공통

    private func cardTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.body)
            .foregroundStyle(Theme.ink)
    }

    private func actionLabel(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(text)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
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

    private func refresh() {
        fileSizeText = logger.currentFileSizeText()
    }
}

#Preview {
    DebugView()
        .preferredColorScheme(.dark)
}
