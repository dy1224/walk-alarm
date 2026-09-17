import SwiftUI

/// 알람 설정 화면.
///
/// Night 배경 위에 큰 세리프 시각 하나. 알람은 하나만 두고 시각과 켜기/끄기만 고른다.
struct HomeView: View {

    @State private var settings = AlarmSettings.shared
    @State private var isPickerOpen = false

    var body: some View {
        ZStack {
            Theme.nightBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 32) {
                header
                timeDisplay
                enableCard
                stageNotice
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
        }
        .sheet(isPresented: $isPickerOpen) {
            TimePickerSheet(settings: settings)
        }
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
                Text(settings.isEnabled ? settings.timeUntilNextText : "알람이 꺼져 있어요")
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

    private var stageNotice: some View {
        GlassCard(cornerRadius: 20, padding: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("1단계 확인용 빌드예요")
                    .font(Theme.body)
                    .foregroundStyle(Theme.ink)
                Text("지금은 시각을 저장하는 것까지만 합니다. 실제 알람 울림은 2단계, 밝기 측정은 3단계, 걸으면 멈추는 판정은 4단계에서 붙습니다.")
                    .font(Theme.label)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Text("설치와 실행이 잘 됐는지는 디버그 화면의 로그로 확인해 주세요.")
                    .font(Theme.label)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
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
