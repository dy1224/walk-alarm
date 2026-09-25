import SwiftUI

/// 알람 설정 화면.
///
/// Night 배경 위에 큰 세리프 시각 하나. 알람은 하나만 두고 시각과 켜기/끄기만 고른다.
struct HomeView: View {

    @State private var settings = AlarmSettings.shared
    @State private var scheduler = AlarmScheduler.shared
    @State private var isPickerOpen = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Theme.nightBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 32) {
                header
                timeDisplay
                enableCard
                if let started = scheduler.lastMissionStart {
                    missionCard(started)
                }
                statusCard
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
        }
        .sheet(isPresented: $isPickerOpen) {
            TimePickerSheet(settings: settings)
        }
        .onChange(of: settings.isEnabled) { scheduler.requestSync() }
        .onChange(of: settings.timeText) { scheduler.requestSync() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("산책 알람")
                .font(Theme.title)
                .foregroundStyle(Theme.ink)
            Text("걸어야 멈추는 알람")
                .font(Theme.label)
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private var timeDisplay: some View {
        Button {
            isPickerOpen = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(settings.timeText)
                    .font(Theme.display(84))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(Theme.label)
                    .foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("알람 시각 \(settings.timeText), 눌러서 바꾸기")
    }

    private var enableCard: some View {
        GlassCard {
            Toggle(isOn: $settings.isEnabled) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("알람 켜기")
                        .font(Theme.body)
                        .foregroundStyle(Theme.ink)
                    Text("매일 \(settings.timeText)")
                        .font(Theme.label)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
            .tint(Theme.dawnWarm)
        }
    }

    private var subtitle: String {
        guard settings.isEnabled else { return "알람이 꺼져 있어요" }
        guard scheduler.isDailyScheduled else { return "아직 예약되지 않았어요" }
        return settings.timeUntilNextText
    }

    private func missionCard(_ started: Date) -> some View {
        GlassCard(cornerRadius: 20, padding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("미션 시작으로 열렸어요")
                    .font(Theme.body)
                    .foregroundStyle(Theme.ink)
                Text("\(AppLogger.stamp(started).prefix(8))에 알람 화면의 미션 시작 버튼을 눌렀어요. 걸으면 멈추는 판정은 4단계에서 붙습니다.")
                    .font(Theme.label)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 예약 상태. 권한이 꺼져 있거나 예약에 실패했으면 이유와 고치는 방법을 말한다.
    @ViewBuilder
    private var statusCard: some View {
        if scheduler.authorization == .denied {
            GlassCard(cornerRadius: 20, padding: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("알람 권한이 꺼져 있어요")
                        .font(Theme.body)
                        .foregroundStyle(Theme.signal)
                    Text("권한이 없으면 정해진 시각에 알람을 울릴 수 없어요. 설정 > 산책 알람 > 알람에서 켜 주세요.")
                        .font(Theme.label)
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("설정 열기") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.glass)
                    .font(Theme.label)
                    .foregroundStyle(Theme.ink)
                }
            }
        } else if let error = scheduler.lastError {
            GlassCard(cornerRadius: 20, padding: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("알람을 예약하지 못했어요")
                        .font(Theme.body)
                        .foregroundStyle(Theme.signal)
                    Text(error)
                        .font(Theme.label)
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("디버그 화면에서 로그를 내보내 보내 주세요.")
                        .font(Theme.label)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        } else {
            GlassCard(cornerRadius: 20, padding: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("3단계 확인용 빌드예요")
                        .font(Theme.body)
                        .foregroundStyle(Theme.ink)
                    Text("측정 탭에서 폰을 들고 방에서 밖까지 걸으며 밝기를 기록해 주세요. 이 기록으로 4단계의 '걸으면 멈추는' 기준을 맞춥니다.")
                        .font(Theme.label)
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// 시각 고르기. 시트 안에서만 휠을 쓰고, 본 화면은 큰 시각 하나로 조용히 둔다.
private struct TimePickerSheet: View {

    let settings: AlarmSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Theme.nightBackground.ignoresSafeArea()

            VStack(spacing: 24) {
                Text("알람 시각")
                    .font(Theme.title)
                    .foregroundStyle(Theme.ink)
                    .padding(.top, 28)

                DatePicker(
                    "알람 시각",
                    selection: Binding(
                        get: { settings.alarmDate },
                        set: { settings.alarmDate = $0 }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()

                Button("알람 저장") {
                    AppLogger.shared.info("알람 저장 · \(settings.timeText)", category: "settings")
                    dismiss()
                }
                .buttonStyle(.glass)
                .font(Theme.body)
                .foregroundStyle(Theme.ink)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .presentationDetents([.height(380)])
    }
}

#Preview {
    HomeView()
        .preferredColorScheme(.dark)
}
