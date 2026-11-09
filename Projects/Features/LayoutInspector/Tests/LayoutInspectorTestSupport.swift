import Core
import Foundation
import ScreenLayoutTesting
import Testing
@testable import LayoutInspectorFeature

/// LayoutInspector Model 테스트가 함께 쓰는 값과 도움 함수.
@MainActor
enum LayoutInspectorTestSupport {
  static let target = LayoutTarget.android(AndroidVirtualDevice.ID("Pixel_9"))
  static let otherTarget = LayoutTarget.android(AndroidVirtualDevice.ID("Tablet"))

  /// "Navigate up" 버튼(85,105,63,63) 안의 점.
  static let buttonPoint = LayoutPoint(x: 100, y: 150)
  /// 목록 항목 "Wi-Fi" 안의 점.
  static let itemPoint = LayoutPoint(x: 540, y: 200)

  static func fixture() -> (LayoutInspectorModel, ScreenLayoutClientFake) {
    let fake = ScreenLayoutClientFake()
    return (LayoutInspectorModel(screenLayout: fake), fake)
  }

  /// 창을 열고 첫 읽기가 끝나기(읽는 중이 아니게 되기)를 기다린다.
  static func open(
    _ model: LayoutInspectorModel,
    _ target: LayoutTarget = Self.target,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    model.windowAppeared(target)
    await self.waitUntil(sourceLocation: sourceLocation) { !model.window(for: target).isLoading }
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

  /// 일어나지 않아야 할 변화를 기다려 본다.
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

/// 기다리는 조건은 Fake 와 MainActor 차례 넘기기만으로 참이 되어 정상이면 수 ms 안에 끝난다. 느린 CI 를 위해 10초.
private let waitLimit: Duration = .seconds(10)
