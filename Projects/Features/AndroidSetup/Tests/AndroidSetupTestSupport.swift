import AndroidSDKInterface
import AndroidSDKTesting
import Core
import Foundation
import PreferencesTesting
import Testing
import WorkspaceTesting
@testable import AndroidSetupFeature

/// AndroidSetup Model 테스트가 함께 쓰는 도움 함수. 테스트 타입이 채택하면 `Self.checkedFixture()` 처럼 부른다.
@MainActor
protocol AndroidSetupTesting {}

@MainActor
extension AndroidSetupTesting {
  /// Fake 를 설정하고 첫 확인(`onAppear`)까지 마친 Model. 기본 상태는 기본 위치가 없음(셋 다 없음)이다.
  static func checkedFixture(
    _ status: AndroidSDKStatus = .absentSample,
    preferences: PreferencesClientFake = PreferencesClientFake(),
    _ configure: (AndroidSDKClientFake) -> Void = { _ in }
  ) async -> AndroidSetupFixture {
    let fake = AndroidSDKClientFake(status: status)
    configure(fake)
    let workspace = WorkspaceClientFake()
    let model = AndroidSetupModel(androidSDK: fake, preferences: preferences, workspace: workspace)
    await model.onAppear()
    return AndroidSetupFixture(model: model, fake: fake, preferences: preferences, workspace: workspace)
  }

  /// `.sample` 계획의 두 원문에 이미 동의한 설정.
  static func acceptedPreferences(isLocked: Bool = false) -> PreferencesClientFake {
    PreferencesClientFake(
      androidSDKPath: .absent,
      androidLicenses: Set(AndroidSDKInstallPlan.sample.licenses.map(\.fingerprint)),
      androidLicensesLocked: isLocked
    )
  }

  static func count(_ call: AndroidSDKClientFake.Call, in fake: AndroidSDKClientFake) -> Int {
    fake.calls.count(where: { $0 == call })
  }

  static func installCalls(in fake: AndroidSDKClientFake) -> [Set<String>] {
    fake.calls.compactMap { call in
      if case let .install(_, accepted) = call {
        return accepted
      }
      return nil
    }
  }

  /// 동의 대기까지 간 Model (기본 Fake: 계획 `.sample`, 동의 기록 없음).
  static func awaitingConsentFixture(
    preferences: PreferencesClientFake = PreferencesClientFake()
  ) async -> AndroidSetupFixture {
    let setup = await Self.checkedFixture(preferences: preferences)
    await setup.model.installButtonTapped()
    return setup
  }

  /// 이미 동의한 상태에서 설치를 띄우고, Fake 가 진행을 모두 보낸 뒤 멈춰 재개를 기다릴 때까지 기다린다.
  static func suspendedInstall(
    progress: [AndroidSDKInstallProgress] = [.firstSample],
    result: Result<AndroidSDKInstallOutcome, AndroidSDKInstallError>? = nil
  ) async -> (AndroidSetupFixture, TrackedTask) {
    let setup = await Self.checkedFixture(preferences: Self.acceptedPreferences()) { fake in
      fake.setInstallScript(progress: progress, result: result)
      fake.suspendInstalls()
    }
    let task = Self.start { await setup.model.installButtonTapped() }
    await Self.waitUntil { setup.fake.suspendedInstallCount == 1 }
    return (setup, task)
  }

  /// 조건이 참이 될 때까지 다른 작업에 차례를 넘긴다. `waitLimit` 안에 참이 되지 않으면 호출 지점에 실패를 기록하고
  /// 돌아온다 (회귀가 있어도 테스트가 멈추지 않고 실패로 끝나게).
  static func waitUntil(
    _ condition: () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    let deadline = ContinuousClock.now + waitLimit
    while !condition() {
      guard ContinuousClock.now < deadline else {
        Issue.record("\(waitLimit) 안에 조건이 참이 되지 않았다", sourceLocation: sourceLocation)
        return
      }
      await Task.yield()
    }
  }

  /// 끝났는지 `waitUntil` 조건에서 볼 수 있게 작업을 띄운다.
  static func start(_ operation: @escaping @MainActor () async -> Void) -> TrackedTask {
    TrackedTask(operation)
  }
}

/// 첫 확인까지 마친 Model 과 주입한 Fake.
@MainActor
struct AndroidSetupFixture {
  let model: AndroidSetupModel
  let fake: AndroidSDKClientFake
  let preferences: PreferencesClientFake
  let workspace: WorkspaceClientFake
}

/// 기다리는 조건은 Fake 와 MainActor 의 차례 넘기기만으로 참이 되어 정상이면 수 ms 안에 끝난다.
/// 느린 CI 에서 거짓 실패가 나지 않게 10초로 둔다.
private let waitLimit: Duration = .seconds(10)

/// 끝났는지 볼 수 있는 작업.
@MainActor
final class TrackedTask {
  private(set) var isFinished = false
  private var task: Task<Void, Never>?

  init(_ operation: @escaping @MainActor () async -> Void) {
    self.task = Task {
      await operation()
      self.isFinished = true
    }
  }

  /// 작업이 끝날 때까지 기다린다.
  func value() async {
    await self.task?.value
  }
}

extension AndroidSDKInstallProgress {
  /// `.sample` 계획의 패키지 `index` 단계.
  static func at(_ index: Int, _ phase: Phase) -> AndroidSDKInstallProgress {
    .sample(index: index, phase: phase)
  }
}
