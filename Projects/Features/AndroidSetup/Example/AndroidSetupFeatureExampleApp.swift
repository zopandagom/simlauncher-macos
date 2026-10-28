import AndroidSDKInterface
import AndroidSDKTesting
import AndroidSetupFeature
import Core
import Foundation
import PreferencesTesting
import SwiftUI
import WorkspaceTesting

/// App 없이 Android 도구 화면만 띄우는 데모 앱. Preview 도 여기에 둔다.
/// 실제 SDK·Google 서버 대신 Testing 모듈의 `AndroidSDKClientFake`(확인·진행 알림마다 지연)와 `PreferencesClientFake`·
/// `WorkspaceClientFake` 를 주입한다. 파일·네트워크·명령을 쓰지 않으므로 아무것도 받거나 설치하지 않고 Finder 도 열리지 않는다.
/// 왼쪽 목록에서 상태를 고른다: "설치해 보기" 는 계획 받기 → 동의 시트 → 패키지별 진행 → 끝나면 셋 다 설치됨으로 바뀐다.
/// 계획 받는 중·동의 대기·진행 단계·실패 상태는 고르면 "Android 도구 설치" 를 대신 눌러 그 상태에서 멈춘다.
/// 셋 다 설치됨으로 넘어가면(첫 확인이 준비됨이거나 "기기 목록 열기") 기기 목록 자리와 "Android 도구" 버튼(`reopened()`)을 보인다.
@main
struct AndroidSetupFeatureExampleApp: App {
  @State private var scenario: DemoScenario = .install
  @State private var models: [DemoScenario: AndroidSetupModel] = Dictionary(
    uniqueKeysWithValues: DemoScenario.allCases.map { ($0, $0.makeModel()) }
  )

  var body: some Scene {
    WindowGroup {
      NavigationSplitView {
        List(DemoScenario.allCases, id: \.self, selection: Binding(
          get: { Optional(self.scenario) },
          set: { self.scenario = $0 ?? .install }
        )) { scenario in
          Text(verbatim: scenario.title)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220)
      } detail: {
        if let model = self.models[self.scenario] {
          // App 처럼 셋 다 설치됨으로 넘어가면 기기 목록 자리를 보인다 (기기 목록은 다른 Feature 라 여기 없다).
          if model.isFinished {
            DeviceListPlaceholder(model: model)
          } else {
            AndroidSetupView(model: model)
              .id(self.scenario)
              .task(id: self.scenario) {
                await self.scenario.prepare(model)
              }
          }
        }
      }
    }
    Settings {
      Text(verbatim: "설정 창 자리 (Example 은 SDK 위치를 바꾸지 않는다)")
        .padding(40)
    }
  }
}

/// 데모 상태. 원시값이 목록에 보이는 이름이다.
enum DemoScenario: String, CaseIterable, Hashable {
  case install = "설치해 보기 (빈 SDK)"
  case ready = "정상 (셋 다 설치됨)"
  case partial = "일부 설치·쓸 수 없음"
  case absent = "빈 상태 (기본 위치 없음)"
  case chosenMissing = "위치: 고른 폴더 없음"
  case notDirectory = "위치: 폴더가 아님"
  case brokenLink = "위치: 깨진 링크"
  case unreadable = "위치: 읽을 수 없음"
  case invalidSetting = "위치: 잘못된 설정"
  case locked = "위치: 잘못된 설정 (관리자 잠김)"
  case notWritable = "위치: 쓸 수 없음"
  case unsupportedVolume = "위치: 링크·RENAME_EXCL 미지원 볼륨"
  case fetchingPlan = "계획 받는 중"
  case consent = "동의 대기 (원문 두 개)"
  case downloading = "진행: 받기"
  case verifying = "진행: 확인"
  case extracting = "진행: 풀기"
  case finishing = "진행: 마무리"
  case planFailed = "실패: 목록 받기"
  case downloadFailed = "실패: 패키지 받기"
  case checksumFailed = "실패: 손상"
  case spaceFailed = "실패: 저장 공간"
  case cancelled = "취소됨"

  var title: String {
    self.rawValue
  }

  /// 확인 결과. 없으면 기본 위치 없음(셋 다 없음).
  private static let statuses: [DemoScenario: AndroidSDKStatus] = [
    .ready: .readySample,
    .partial: .partialSample,
    .chosenMissing: .chosenMissingSample,
    .notDirectory: .unusableSample(.notDirectory),
    .brokenLink: .unusableSample(.brokenLink),
    .unreadable: .unusableSample(.unreadable),
    .invalidSetting: .unusableSample(.invalidSetting),
    .locked: .unusableSample(.invalidSetting),
    .notWritable: .notWritableSample,
    .unsupportedVolume: AndroidSDKStatus(
      location: .folder(.chosenSample, writable: true),
      components: [.platformTools: .missing, .emulator: .missing, .systemImage: .missing],
      installBlocker: .unsupportedVolume,
      installedSystemImages: []
    ),
  ]

  /// 이 진행을 보낸 뒤 멈추는 설치.
  private static let suspendedProgress: [DemoScenario: AndroidSDKInstallProgress] = [
    .downloading: .at(3, .downloading(received: 812_000_000, expected: 2_104_098_168)),
    .verifying: .at(3, .verifying),
    .extracting: .at(3, .extracting),
    .finishing: .at(3, .finishing),
  ]

  /// 진행 없이 이 결과로 끝나는 설치.
  private static let installFailures: [DemoScenario: AndroidSDKInstallError] = [
    .downloadFailed: .download(.systemImage, .connectionLost),
    .checksumFailed: .checksumMismatch(.emulator),
    .spaceFailed: .insufficientDiskSpace(.systemImage, required: 9_100_000_000, available: 3_200_000_000),
    .cancelled: .cancelled,
  ]

  /// 고르면 "Android 도구 설치" 를 대신 누르는 상태.
  private var pressesInstall: Bool {
    self == .fetchingPlan || self == .consent || self == .planFailed
      || Self.suspendedProgress[self] != nil || Self.installFailures[self] != nil
  }

  @MainActor
  func makeModel() -> AndroidSetupModel {
    let fake = AndroidSDKClientFake(status: Self.statuses[self] ?? .absentSample)
    self.configure(fake)
    let client: any AndroidSDKClient = self == .install ? InstallingDemoClient(fake: fake) : fake
    return AndroidSetupModel(androidSDK: client, preferences: self.makePreferences(), workspace: WorkspaceClientFake())
  }

  /// 고르면 "Android 도구 설치" 를 대신 눌러 그 상태로 간다 (이미 간 상태면 Model 이 무시한다).
  @MainActor
  func prepare(_ model: AndroidSetupModel) async {
    guard self.pressesInstall else { return }
    await model.onAppear()
    await model.installButtonTapped()
  }

  /// 진행·실패 상태는 동의를 마친 설정으로 시트를 건너뛴다. 잠김은 위치 키를 강제한 설정.
  @MainActor
  private func makePreferences() -> PreferencesClientFake {
    if Self.suspendedProgress[self] != nil || Self.installFailures[self] != nil {
      let accepted = Set(AndroidSDKInstallPlan.sample.licenses.map(\.fingerprint))
      return PreferencesClientFake(androidSDKPath: .absent, androidLicenses: accepted)
    }
    if self == .locked {
      return PreferencesClientFake(androidSDKPath: AndroidSDKPathSetting(value: .malformed, isLocked: true))
    }
    return PreferencesClientFake()
  }

  private func configure(_ fake: AndroidSDKClientFake) {
    if self == .install {
      fake.setDelay(.seconds(1))
      fake.setInstallScript(progress: demoProgress, result: nil)
    }
    if self == .fetchingPlan {
      fake.suspendPlans()
    }
    if self == .planFailed {
      fake.setPlanResult(.failure(.download(.offline)))
    }
    if let progress = Self.suspendedProgress[self] {
      fake.setInstallScript(progress: [progress], result: nil)
      fake.suspendInstalls()
    }
    if let error = Self.installFailures[self] {
      fake.setInstallScript(progress: [], result: .failure(error))
    }
  }
}

extension AndroidSDKInstallProgress {
  static func at(_ index: Int, _ phase: Phase) -> AndroidSDKInstallProgress {
    .sample(index: index, phase: phase)
  }
}

/// 세 패키지의 받기 → 확인 → 풀기 → 마무리 (1초 간격).
private let demoProgress: [AndroidSDKInstallProgress] = [
  .at(1, .downloading(received: 0, expected: 16_110_554)),
  .at(1, .downloading(received: 16_110_554, expected: 16_110_554)),
  .at(1, .verifying), .at(1, .extracting), .at(1, .finishing),
  .at(2, .downloading(received: 208_000_000, expected: 416_112_708)),
  .at(2, .downloading(received: 416_112_708, expected: 416_112_708)),
  .at(2, .verifying), .at(2, .extracting), .at(2, .finishing),
  .at(3, .downloading(received: 700_000_000, expected: 2_104_098_168)),
  .at(3, .downloading(received: 1_400_000_000, expected: 2_104_098_168)),
  .at(3, .downloading(received: 2_104_098_168, expected: 2_104_098_168)),
  .at(3, .verifying), .at(3, .extracting), .at(3, .finishing),
]

/// 설치가 성공하면 Fake 의 상태를 셋 다 설치됨으로 바꾸는 데모용 Client. 나머지는 Fake 에 그대로 넘긴다.
private struct InstallingDemoClient: AndroidSDKClient {
  let fake: AndroidSDKClientFake

  func checkSDK() async -> AndroidSDKStatus {
    await self.fake.checkSDK()
  }

  func fetchInstallPlan() async throws(AndroidSDKPlanError) -> AndroidSDKInstallPlan {
    try await self.fake.fetchInstallPlan()
  }

  func install(
    _ plan: AndroidSDKInstallPlan,
    acceptedLicenses: Set<String>,
    progress: @escaping @Sendable (AndroidSDKInstallProgress) async -> Void
  ) async throws(AndroidSDKInstallError) -> AndroidSDKInstallOutcome {
    let outcome = try await self.fake.install(plan, acceptedLicenses: acceptedLicenses, progress: progress)
    self.fake.setStatus(.readySample)
    return outcome
  }

  func removeLeftovers() async {
    await self.fake.removeLeftovers()
  }

  func inspectCandidateFolder(_ url: URL) async -> (candidate: AndroidSDKFolderCandidate, writable: Bool) {
    await self.fake.inspectCandidateFolder(url)
  }
}

/// App 의 Android 기기 목록 자리. "Android 도구" 는 App 처럼 `reopened()` 로 도구 화면을 다시 연다.
private struct DeviceListPlaceholder: View {
  let model: AndroidSetupModel

  var body: some View {
    VStack(spacing: 12) {
      Text(verbatim: "기기 목록 화면 자리 (AndroidDevices Feature, Example 밖)")
        .foregroundStyle(.secondary)
      Button {
        self.model.reopened()
      } label: {
        Text(verbatim: "Android 도구")
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

@MainActor
private func demoPreview(_ scenario: DemoScenario) -> some View {
  let model = scenario.makeModel()
  return AndroidSetupView(model: model)
    .task { await scenario.prepare(model) }
    .frame(width: 640, height: 560)
}

#Preview("정상") {
  demoPreview(.ready)
}

#Preview("빈 상태") {
  demoPreview(.absent)
}

#Preview("일부·쓸 수 없음") {
  demoPreview(.partial)
}

#Preview("고른 폴더 없음") {
  demoPreview(.chosenMissing)
}

#Preview("쓸 수 없는 위치") {
  demoPreview(.notWritable)
}

#Preview("동의 대기") {
  demoPreview(.consent)
}

#Preview("받는 중") {
  demoPreview(.downloading)
}

#Preview("받기 실패") {
  demoPreview(.downloadFailed)
}
