import Charts
import SwiftUI

/// 밝기 측정 화면 (3단계).
///
/// 방에서 밖까지 폰을 들고 걸으며 후면 카메라로 밝기(Bv)를 잰다.
/// 최근 60초 그래프, 판정 미리보기, 구간 표시, CSV 내보내기.
struct MeasureView: View {

    @State private var model = BrightnessModel.shared
    @State private var isStarting = false
    @State private var isDeleteConfirmOpen = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.nightBackground
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        currentCard
                        chartCard
                        verdictCard
                        labelCard
                        controlCard
                        filesCard
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("밝기 측정")
            .toolbarTitleDisplayMode(.inline)
            .onAppear {
                model.refreshAccess()
                model.refreshFiles()
            }
        }
    }

    // MARK: - 현재 값

    private var currentCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.currentBv.map { String(format: "%.1f", $0) } ?? "–")
                        .font(Theme.display(64))
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.identity)
                    Text("Bv")
                        .font(Theme.body)
                        .foregroundStyle(Theme.inkSoft)
                }
                Text(subtitle)
                    .font(Theme.label)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private var subtitle: String {
        guard model.isMeasuring else { return "측정을 시작하면 1초마다 밝기가 갱신돼요" }
        let s = model.lastSummary
        let ratio = s.frameCount > 0 ? Int(Double(s.exifCount) / Double(s.frameCount) * 100) : 0
        return "초당 \(s.frameCount)프레임 · EXIF 값 \(ratio)%"
    }

    // MARK: - 그래프

    private var chartCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("최근 60초")
                chart
                    .frame(height: 180)
                Text("점은 한 번에 \(String(format: "%.1f", Detection.deltaBv)) Bv 이상 바뀐 순간이에요.")
                    .font(Theme.label)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private var chart: some View {
        let now = model.points.last?.date ?? Date()
        let valued = model.points.filter { $0.bv != nil }
        return Chart {
            ForEach(valued) { p in
                LineMark(
                    x: .value("초", p.date.timeIntervalSince(now)),
                    y: .value("Bv", p.bv ?? 0),
                    series: .value("구간", p.segment)
                )
                .foregroundStyle(Theme.dawnCool)
                .interpolationMethod(.monotone)
            }
            ForEach(valued.filter(\.significant)) { p in
                PointMark(
                    x: .value("초", p.date.timeIntervalSince(now)),
                    y: .value("Bv", p.bv ?? 0)
                )
                .foregroundStyle(Theme.dawnWarm)
                .symbolSize(30)
            }
        }
        .chartXScale(domain: -60.0...0.0)
        .chartXAxis {
            AxisMarks(values: [-60.0, -45.0, -30.0, -15.0, 0.0]) { value in
                AxisGridLine().foregroundStyle(Theme.ink.opacity(0.08))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(v == 0 ? "지금" : "\(Int(v))초")
                            .font(Theme.label)
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Theme.ink.opacity(0.08))
                AxisValueLabel()
                    .font(Theme.label)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
    }

    // MARK: - 판정 미리보기

    private var verdictCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("판정 미리보기")
                InfoRow(label: "지금 판정", value: model.isMeasuring ? model.verdict.text : "–")
                InfoRow(
                    label: "최근 \(Int(Detection.windowSec))초 변화",
                    value: "\(model.changesInWindow) / \(Detection.minChanges)회"
                )
                InfoRow(
                    label: "변화 없이 지난 시간",
                    value: model.isMeasuring ? "\(Int(model.stillSeconds))초 / \(Int(Detection.stillSec))초" : "–"
                )
                Text("4단계에서 알람을 멈추고 다시 울릴 기준이에요. 걸으면서 이 값이 맞게 바뀌는지 봐 주세요.")
                    .font(Theme.label)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 구간 표시

    private var labelCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("지금 있는 곳")
                HStack(spacing: 8) {
                    ForEach(BrightnessModel.labels, id: \.self) { name in
                        Button {
                            model.toggleLabel(name)
                        } label: {
                            Text(name)
                                .font(Theme.label)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.glass)
                        .foregroundStyle(model.label == name ? Theme.night : Theme.ink)
                        .tint(model.label == name ? Theme.dawnWarm : nil)
                    }
                }
                Text("이동할 때마다 눌러 두면 CSV에 같이 기록돼요. 나중에 어느 구간에서 밝기가 어떻게 변했는지 볼 수 있어요.")
                    .font(Theme.label)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - 시작 / 멈춤

    private var controlCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                if let error = model.errorText {
                    Text(error)
                        .font(Theme.label)
                        .foregroundStyle(Theme.signal)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.access == .denied {
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

                Button {
                    if model.isMeasuring {
                        model.stop()
                    } else {
                        isStarting = true
                        Task {
                            await model.start()
                            isStarting = false
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: model.isMeasuring ? "stop.fill" : "record.circle")
                        Text(model.isMeasuring ? "측정 멈추기" : "측정 시작")
                        Spacer(minLength: 0)
                        if model.isMeasuring, let started = model.startedAt {
                            Text(started, style: .timer)
                                .monospacedDigit()
                        }
                    }
                    .font(Theme.body)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .foregroundStyle(model.isMeasuring ? Theme.signal : Theme.ink)
                .disabled(isStarting)

                Text("후면 카메라가 바깥을 향하게 들고 걸어 주세요. 측정 중에는 화면이 꺼지지 않아요. 앱을 벗어나면 카메라가 멈춰 그동안은 기록이 비어요.")
                    .font(Theme.label)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - CSV

    private var filesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                cardTitle("측정 기록 (CSV)")
                if model.files.isEmpty {
                    Text("아직 기록이 없어요.")
                        .font(Theme.label)
                        .foregroundStyle(Theme.inkSoft)
                } else {
                    ForEach(model.files.prefix(8), id: \.self) { url in
                        HStack(spacing: 12) {
                            Text(url.lastPathComponent)
                                .font(Theme.mono)
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .foregroundStyle(Theme.dawnCool)
                        }
                    }
                    Button {
                        isDeleteConfirmOpen = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                            Text("기록 모두 지우기")
                            Spacer(minLength: 0)
                        }
                        .font(Theme.label)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    .foregroundStyle(Theme.signal)
                    .disabled(model.isMeasuring)
                }
            }
        }
        .confirmationDialog("측정 기록을 모두 지울까요?", isPresented: $isDeleteConfirmOpen, titleVisibility: .visible) {
            Button("지우기", role: .destructive) {
                model.deleteAllFiles()
            }
            Button("그만두기", role: .cancel) {}
        }
    }

    private func cardTitle(_ text: String) -> some View {
        Text(text)
            .font(Theme.body)
            .foregroundStyle(Theme.ink)
    }
}

#Preview {
    MeasureView()
        .preferredColorScheme(.dark)
}
