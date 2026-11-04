import AppLogInterface
import AppLogTesting
import Core
import Foundation
import Testing
@testable import DeviceLogFeature

/// DeviceLog Model 테스트가 함께 쓰는 값과 도움 함수.
@MainActor
enum DeviceLogTestSupport {
  static let device = VirtualDevice.ID("5C0F3A2E-0000-4000-8000-000000000001")
  static let otherDevice = VirtualDevice.ID("5C0F3A2E-0000-4000-8000-000000000002")
  static let target = AppLogTarget.iOS(device)
  static let otherTarget = AppLogTarget.iOS(otherDevice)
  static let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

  static func summary(
    _ appID: String = "dev.example.probe",
    at offset: TimeInterval = 0,
    state: AppLogSessionState = .receiving,
    target: AppLogTarget = Self.target,
    id: AppLogSessionID = AppLogSessionID(UUID())
  ) -> AppLogSessionSummary {
    AppLogSessionSummary(
      id: id, target: target, deviceName: "iPhone 17 Pro", appID: appID,
      appName: appID.components(separatedBy: ".").last ?? appID,
      startedAt: self.baseDate.addingTimeInterval(offset), state: state
    )
  }

  /// 창을 연 Model 과 그 Fake·세션.
  struct Opened {
    let model: DeviceLogModel
    let fake: AppLogClientFake
    let session: AppLogSessionSummary
  }

  /// 세션을 넣은 Fake 와 Model.
  static func fixture(_ sessions: [AppLogSessionSummary]) -> (DeviceLogModel, AppLogClientFake) {
    let fake = AppLogClientFake(sessions: sessions)
    return (DeviceLogModel(appLog: fake), fake)
  }

  /// 창을 열고 그 세션을 골라 보이는 줄이 `visible` 개가 되기까지 기다린다.
  static func openAndWait(
    _ model: DeviceLogModel,
    expecting session: AppLogSessionID,
    visible: Int,
    target: AppLogTarget = Self.target,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    model.windowAppeared(target)
    await self.waitUntil(sourceLocation: sourceLocation) {
      model.window(for: target).selectedSessionID == session && model.window(for: target).visibleCount == visible
    }
  }

  static func texts(_ lines: [AppLogLine]) -> [String] {
    lines.map(\.text)
  }

  static func texts(_ lines: [VisibleLogLine]) -> [String] {
    lines.map(\.line.text)
  }

  /// 조건이 참이 될 때까지 다른 작업에 차례를 넘긴다. `waitLimit` 안에 참이 되지 않으면 실패를 기록하고 돌아온다.
  static func waitUntil(
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () -> Bool
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

  /// 일어나지 않아야 할 변화를 기다려 본다 (메인 밖 거르기·스트림이 돌 차례를 충분히 준다).
  static func settle() async {
    for _ in 0 ..< 200 {
      await Task.yield()
    }
    try? await Task.sleep(for: .milliseconds(20))
    for _ in 0 ..< 200 {
      await Task.yield()
    }
  }
}

/// 기다리는 조건은 Fake 와 MainActor 차례 넘기기, 메인 밖 거르기(줄 수십 개)만으로 참이 되어 정상이면 수 ms 안에 끝난다.
/// 느린 CI 에서 거짓 실패가 나지 않게 10초로 둔다.
private let waitLimit: Duration = .seconds(10)
