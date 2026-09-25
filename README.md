# 산책 알람 (Walk Alarm)

걸어야 멈추는 알람. 알람이 울리면 폰을 들고 방 → 복도 → 엘리베이터 → 산책지로 나가야 하고,
주변 밝기(Bv)가 계속 변하는 동안만 소리가 멈춘다. 멈춰 서면 다시 울린다.

맥 없이 만든다. 코드는 윈도우에서 쓰고, 빌드는 GitHub Actions의 macOS 러너에서,
설치는 윈도우의 Sideloadly로 무료 Apple ID 서명을 붙여서 한다.

- 최소 iOS: **26.0**
- 언어/프레임워크: Swift 6 · SwiftUI · (2단계 이후) AlarmKit, AVFoundation
- 프로젝트 정의: **XcodeGen** (`project.yml`). `.xcodeproj`는 저장소에 넣지 않고 러너에서 생성한다.

---

## 현재 진행 상태

| 단계 | 내용 | 상태 |
| --- | --- | --- |
| 1 | 빈 앱 + 빌드 워크플로 + 로그 화면 | ✅ 실기기 통과 (2026-09-25) |
| 2 | AlarmKit 알람 1개 + "미션 시작" 버튼으로 앱 열기 | ✅ 실기기 통과 (2026-09-25) |
| 3 | 카메라 Bv 측정 + 실시간 그래프 + CSV 내보내기 | 🔄 코드 완료 · 실기기 확인 대기 |
| 4 | 상태 머신 + 앱 내 울림/일시정지 + 연쇄 알람 + "도착했어요" | ⬜ |

3단계 앱에는 "측정" 탭이 추가됐다. 후면 카메라 프레임의 EXIF BrightnessValue(Bv)를 1초마다 평균 내어
최근 60초 그래프와 판정 미리보기(변화 횟수·무변화 시간)를 보여 주고, 측정마다 CSV 두 개(1초 요약·프레임 원자료)를 남긴다.
걸으면서 방·복도·엘리베이터·밖 구간을 눌러 두면 CSV에 같이 기록된다.
목표는 **방에서 밖까지 걸으며 밝기 로그를 확보**해 4단계 판정값(DELTA_BV 등)을 맞추는 것.

(2단계) 저장한 시각에 AlarmKit 시스템 알람을 매일 울린다. 알람 화면에는 "미션 시작" 버튼 하나만 있고,
누르면 알람이 멈추면서 앱이 열린다. 디버그 화면의 "1분 뒤 알람 테스트"로 잠금·무음 상태에서 바로 확인할 수 있다.
무료 Apple ID 서명에서 AlarmKit이 잠금·무음 상태로 울리는 것을 확인했다.

---

## 파일 트리

```
walk-alarm/
├── project.yml                     XcodeGen 프로젝트 정의
├── README.md
├── .gitignore
├── .github/
│   └── workflows/
│       └── build.yml               macOS 러너에서 서명 없는 .ipa 빌드
└── WalkAlarm/
    ├── App/
    │   └── WalkAlarmApp.swift      @main, 시작 로그
    ├── Core/
    │   ├── AppLogger.swift         파일 로그 (Documents/Logs/*.log)
    │   ├── LogStore.swift          화면 표시용 실시간 로그 버퍼
    │   ├── AppInfo.swift           버전·기기 정보
    │   ├── Theme.swift             Night/Dawn/Signal/Ink 색, 세리프 글꼴
    │   ├── AlarmSettings.swift     알람 시각 저장 (UserDefaults)
    │   ├── AlarmScheduler.swift    AlarmKit 권한·예약·취소, 상태 변화 로그
    │   ├── BrightnessMeter.swift   후면 카메라 프레임 EXIF Bv 읽기 (계산 Bv 대체)
    │   ├── BrightnessModel.swift   1초 평균 B(t), 유의미한 변화 판정 미리보기, 측정 시작/멈춤
    │   ├── MeasurementRecorder.swift  측정 CSV (1초 요약 / 프레임 원자료)
    │   └── AlarmIntents.swift      알람 화면 "미션 시작" 버튼 (멈춤 + 앱 열기)
    ├── Views/
    │   ├── RootView.swift          탭 3개 (알람 / 측정 / 디버그)
    │   ├── HomeView.swift          알람 설정 화면
    │   ├── MeasureView.swift       밝기 측정: 현재 Bv, 60초 그래프, 판정 미리보기, 구간 표시, CSV
    │   ├── DebugView.swift         디버그 화면
    │   ├── LogViewerView.swift     로그 전체 보기
    │   └── Components/
    │       └── GlassCard.swift     Liquid Glass 카드, InfoRow
    ├── Resources/
    │   └── Assets.xcassets/        앱 아이콘, AccentColor, LaunchBackground
    └── Support/
        └── Info.plist              권한 문구, UIBackgroundModes: audio
```

---

## 1. 빌드 (GitHub Actions)

저장소를 **공개(public)** 로 만들어야 macOS 러너를 무료로 쓸 수 있다.

```powershell
# 저장소 만들고 첫 푸시
cd walk-alarm
git init -b main
git add .
git commit -m "1단계: 빈 앱 + 빌드 워크플로 + 로그 화면"
gh repo create walk-alarm --public --source . --remote origin --push
```

푸시하면 `build` 워크플로가 자동으로 돈다.

```powershell
gh run watch                 # 진행 상황 보기
gh run view --log-failed     # 실패했을 때 실패한 단계 로그만 보기
```

성공하면 `WalkAlarm-unsigned-ipa` 라는 이름의 artifact가 생긴다.

```powershell
gh run download --name WalkAlarm-unsigned-ipa
```

`WalkAlarm-unsigned.ipa` 파일이 내려온다. 이 파일은 **서명이 없어서** 그대로는 설치되지 않는다.
서명은 다음 단계에서 Sideloadly가 붙인다.

### 워크플로가 하는 일

1. 러너에 설치된 Xcode 중 가장 높은 버전을 고르고, 26 미만이면 멈춘다
2. `brew install xcodegen` → `xcodegen generate`
3. `xcodebuild -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO`
4. `Payload/WalkAlarm.app` 을 zip으로 묶어 `.ipa` 생성
5. artifact 업로드

러너 이미지에 Xcode 26이 없으면 `build.yml` 의 `runs-on: macos-26` 을 바꿔야 한다.
실패 로그의 "Runner에 설치된 Xcode 목록" 단계를 보면 어떤 버전이 있는지 알 수 있다.

---

## 2. 설치 (윈도우 + Sideloadly, 무료 Apple ID)

### 준비물

- [ ] Sideloadly ([sideloadly.io](https://sideloadly.io)) — 설치 중 안내에 따라 **Apple 웹사이트판** iTunes와 iCloud가 필요하다 (Microsoft Store 버전은 안 된다)
- [ ] 아이폰 USB 케이블
- [ ] Apple ID (무료 계정으로 충분)
- [ ] 아이폰 iOS 26 이상

### 순서

1. 아이폰을 USB로 연결하고, 아이폰에서 "이 컴퓨터를 신뢰" 를 누른다
2. Sideloadly를 켜고 `WalkAlarm-unsigned.ipa` 를 창에 끌어다 놓는다
3. Apple ID를 입력한다 (2단계 인증을 쓰면 **앱 암호**가 아니라 계정 암호를 넣고, 뜨는 인증 코드를 입력한다)
4. `Start` 를 누른다. 서명 후 설치까지 몇 분 걸린다
5. 설치가 끝나면 아이폰에서:
   - **설정 > 개인정보 보호 및 보안 > 개발자 모드** 를 켜고 재부팅
   - **설정 > 일반 > VPN 및 기기 관리** 에서 내 Apple ID를 **신뢰**
6. 홈 화면의 "산책 알람" 을 실행한다

### 무료 Apple ID의 제약

- 서명이 **7일** 마다 만료된다. 만료되면 Sideloadly로 같은 과정을 다시 하면 된다 (앱 데이터는 유지)
- 한 Apple ID로 7일에 앱 10개까지
- 무료 계정은 쓸 수 있는 entitlement가 제한된다. **2단계의 AlarmKit이 무료 서명에서 동작하지 않을 가능성이 있다.**
  그 경우 유료 개발자 계정($99/년)을 쓸지 다른 방식으로 갈지 결정해야 한다

---

## 3. 실기기 테스트 체크리스트

### 3단계 (지금)

- [ ] 측정 탭에서 "측정 시작" → 카메라 권한 허용 → 1초마다 Bv가 바뀌고 그래프가 그려진다
- [ ] 손으로 카메라를 가리거나 불빛에 비추면 Bv가 크게 변하고 그래프에 점(유의미한 변화)이 찍힌다
- [ ] 폰을 가만히 두면 15초 뒤 "멈춤으로 판정"이 된다
- [ ] 방 → 복도 → 엘리베이터 → 밖까지 걸으며 구간 버튼을 누르고, 끝나면 "측정 멈추기"
- [ ] CSV 두 개(`-seconds.csv`, `-frames.csv`)를 내보낼 수 있다
- [ ] 측정 중 홈으로 나갔다 오면 그동안 기록이 비고(로그에 "카메라 중단"), 돌아오면 이어진다

### 2단계 (통과, 2026-09-25)

- [x] 알람을 켜면 AlarmKit 권한을 묻고, 허용하면 알람 화면에 "N시간 M분 뒤"가 보인다
- [x] 디버그 화면 "알람 (AlarmKit)"에 권한 "허용됨", 매일 알람 1개(`scheduled`)가 보인다
- [x] "1분 뒤 알람 테스트" → 화면 잠금 + 무음 스위치 켬 → 1분 뒤 시스템 알람이 소리와 함께 울린다
- [x] 알람 화면에 "미션 시작" 버튼 하나만 있고, 누르면 (잠금 해제 후) 앱이 열리며 "미션 시작으로 열렸어요"가 보인다
- [x] 로그에 `테스트 알람 예약` → `alerting` → `미션 시작 버튼으로 앱 열림`이 남는다

### 1단계 (통과, 2026-09-25)

- [x] Sideloadly 서명·설치가 끝까지 성공한다
- [x] 홈 화면에 아이콘이 생기고 앱이 실행된다 (바로 튕기지 않는다)
- [x] 알람 화면에 큰 시각이 보이고, 눌러서 시각을 바꾸면 저장된다
- [x] 앱을 끄고 다시 켜도 바꾼 시각이 남아 있다
- [x] 디버그 화면에 앱 정보(버전·iOS·기기)가 보인다
- [x] "테스트 로그 남기기" 를 누르면 로그가 늘어난다
- [x] "로그 파일 내보내기" 로 공유 시트가 뜨고 파일을 내보낼 수 있다
- [x] 앱을 껐다 켠 뒤에도 이전 로그가 파일에 남아 있다 (내보내서 확인)

### 4단계까지 끝난 뒤 (최종)

- [ ] 잠금 상태·무음 모드에서 알람이 울린다
- [ ] 시스템 알람을 끈 뒤에도 연쇄 알람이 다시 울린다
- [ ] 이동 중 일시정지, 멈추면 재개된다
- [ ] 앱을 벗어나면 계속 울린다
- [ ] UNLOCK_SEC 전에는 "도착했어요" 버튼이 눌리지 않는다

---

## 판정 파라미터 (3·4단계에서 사용)

실측 전 임시값. 설정 화면에서 조정할 수 있게 만든다.

| 파라미터 | 초기값 | 의미 |
| --- | --- | --- |
| DELTA_BV | 0.5 Bv | 한 번의 변화로 인정할 최소 밝기 차 |
| WINDOW_SEC | 10 s | 변화 횟수를 세는 구간 |
| MIN_CHANGES | 3회 | 이동으로 판정할 최소 변화 횟수 |
| STILL_SEC | 15 s | 다시 울리기까지의 무변화 시간 |
| UNLOCK_SEC | 180 s | "도착했어요" 버튼이 활성화되는 누적 이동 시간 |

---

## 디자인: 새벽으로 나가는 길

| 이름 | 값 | 용도 |
| --- | --- | --- |
| Night | `#0E1224` | 이동 전, 앱 기본 배경 |
| Dawn | `#E9B99A` → `#A7C4DC` | 이동이 쌓일수록 번지는 새벽 하늘 |
| Signal | `#FF5A4E` | 울림 상태(멈춤 경고)에만 |
| Ink | `#F3F1EC` | 주요 텍스트 |

강조는 **배경 그라데이션**과 **빛의 선** 두 가지에만 쓴다. 나머지는 차분하게 둔다.
큰 시각은 New York(세리프) 가벼운 굵기, 그 외 UI는 SF Pro. 대문자 라벨은 쓰지 않는다.
