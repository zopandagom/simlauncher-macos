import Core
import DevEnvironmentTesting
import Testing
@testable import SetupFeature

/// Setup Model 테스트가 함께 쓰는 도움 함수. 테스트 타입이 채택하면 `Self.checkedModel()` 처럼 부른다.
@MainActor
protocol SetupModelTesting {}

@MainActor
extension SetupModelTesting {
  /// `status` 로 설정한 Fake 와 첫 확인까지 마친 Model.
  static func checkedModel(
    _ status: DevEnvironmentStatus,
    _ configure: (DevEnvironmentClientFake) -> Void = { _ in }
  ) async -> (SetupModel, DevEnvironmentClientFake) {
    let fake = DevEnvironmentClientFake(status: status)
    configure(fake)
    let model = SetupModel(devEnvironment: fake)
    await model.onAppear()
    return (model, fake)
  }

  static func checkCount(in fake: DevEnvironmentClientFake) -> Int {
    fake.calls.filter { $0 == .checkEnvironment }.count
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

  /// 끝났는지 `waitUntil` 조건에서 볼 수 있게 작업을 띄운다. 회귀가 있으면 멈출 수 있는 호출(Fake 를 멈춘 동안의
  /// 이벤트)을 직접 await 하지 않고 이것으로 띄운다.
  static func start(_ operation: @escaping @MainActor () async -> Void) -> TrackedTask {
    TrackedTask(operation)
  }
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
