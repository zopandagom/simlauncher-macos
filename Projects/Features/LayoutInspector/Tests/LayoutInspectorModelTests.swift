import Core
import Foundation
import ScreenLayoutInterface
import ScreenLayoutTesting
import Testing
@testable import LayoutInspectorFeature

@MainActor
struct LayoutInspectorModelTests {
  private typealias Support = LayoutInspectorTestSupport
  private let target = Support.target

  // MARK: - 창 열기

  @Test("창이 열리면 한 번 읽고, 성공하면 스냅샷을 보이고 읽는 중이 아니다")
  func appearReadsOnce() async {
    let (model, fake) = Support.fixture()
    fake.enqueue(.success(.sample()), for: self.target)
    await Support.open(model)
    let window = model.window(for: self.target)
    #expect(window.snapshot == .sample())
    #expect(window.loading == nil)
    #expect(window.failure == nil)
    #expect(window.pick == nil)
    #expect(fake.calls == [self.target])
  }

  @Test("같은 창의 onAppear 가 두 번 와도 한 번만 읽는다")
  func appearTwiceReadsOnce() async {
    let (model, fake) = Support.fixture()
    fake.setHolding(true)
    model.windowAppeared(self.target)
    model.windowAppeared(self.target)
    await fake.waitUntilHeld(self.target)
    await Support.settle()
    #expect(fake.calls == [self.target])
    fake.release(self.target)
    await Support.waitUntil { !model.window(for: self.target).isLoading }
    model.windowAppeared(self.target)
    await Support.settle()
    #expect(fake.calls.count == 1)
  }

  @Test("처음 읽는 중에는 스냅샷 없이 .reading 이다")
  func firstLoading() async {
    let (model, fake) = Support.fixture()
    fake.setHolding(true)
    model.windowAppeared(self.target)
    await fake.waitUntilHeld(self.target)
    let window = model.window(for: self.target)
    #expect(window.loading == .reading)
    #expect(window.isLoading)
    #expect(window.snapshot == nil)
    #expect(window.failure == nil)
  }

  @Test("단계 알림(.preparing → .reading)을 그대로 보인다")
  func phases() async {
    let (model, fake) = Support.fixture()
    fake.setAutomaticPhases([.preparing])
    fake.setHolding(true)
    fake.enqueue(.success(.sample()), for: self.target)
    model.windowAppeared(self.target)
    await fake.waitUntilHeld(self.target)
    await Support.waitUntil { model.window(for: self.target).loading == .preparing }
    await fake.sendPhase(.reading, to: self.target)
    await Support.waitUntil { model.window(for: self.target).loading == .reading }
    fake.release(self.target)
    await Support.waitUntil { model.window(for: self.target).snapshot != nil }
    #expect(model.window(for: self.target).loading == nil)
  }

  @Test(
    "처음 읽기가 실패하면 스냅샷 없이 실패 분류를 보인다",
    arguments: LayoutInspectorFailureTests.mapping.filter { $0.1 != nil }.map(\.0)
  )
  func firstFailure(_ error: ScreenLayoutError) async {
    let (model, fake) = Support.fixture()
    fake.enqueue(.failure(error), for: self.target)
    await Support.open(model)
    let window = model.window(for: self.target)
    #expect(window.snapshot == nil)
    #expect(window.failure == LayoutInspectorFailure(error))
    #expect(window.failure != nil)
  }

  @Test("Client 가 .cancelled 를 돌려주면(창은 열린 채) 실패로 보이지 않고 읽기만 끝낸다")
  func cancelledByClient() async {
    let (model, fake) = Support.fixture()
    fake.enqueue(.failure(.cancelled), for: self.target)
    await Support.open(model)
    let window = model.window(for: self.target)
    #expect(window.failure == nil)
    #expect(window.snapshot == nil)
    #expect(!window.isLoading)
  }

  // MARK: - 새로 고침

  @Test("읽는 중 새로 고침은 무시한다")
  func refreshWhileLoadingIgnored() async {
    let (model, fake) = Support.fixture()
    fake.setHolding(true)
    model.windowAppeared(self.target)
    await fake.waitUntilHeld(self.target)
    model.refreshTapped(in: self.target)
    model.refreshTapped(in: self.target)
    await Support.settle()
    #expect(fake.calls.count == 1)
  }

  @Test("창이 없으면 새로 고침은 아무것도 하지 않는다")
  func refreshWithoutWindow() async {
    let (model, fake) = Support.fixture()
    model.refreshTapped(in: self.target)
    await Support.settle()
    #expect(fake.calls.isEmpty)
    #expect(model.windows.isEmpty)
  }

  @Test("새로 고치는 동안 이전 스냅샷·고름이 남고, 시작할 때 앞 실패를 지운다")
  func refreshKeepsSnapshotAndClearsFailure() async {
    let (model, fake) = Support.fixture()
    fake.enqueue(.success(.sample()), for: self.target)
    fake.enqueue(.failure(.screenNotIdle), for: self.target)
    await Support.open(model)
    model.canvasClicked(at: Support.buttonPoint, in: self.target)
    model.refreshTapped(in: self.target)
    await Support.waitUntil { !model.window(for: self.target).isLoading }
    #expect(model.window(for: self.target).failure == .screenNotIdle)
    fake.setHolding(true)
    model.refreshTapped(in: self.target)
    await fake.waitUntilHeld(self.target)
    let window = model.window(for: self.target)
    #expect(window.failure == nil)
    #expect(window.loading == .reading)
    #expect(window.snapshot == .sample())
    #expect(window.pick?.selected == 2)
  }

  @Test("새로 고침이 실패하면 스냅샷과 고름을 그대로 두고 실패를 보인다")
  func refreshFailureKeepsSnapshot() async {
    let (model, fake) = Support.fixture()
    fake.enqueue(.success(.sample()), for: self.target)
    fake.enqueue(.failure(.displayOff), for: self.target)
    await Support.open(model)
    model.canvasClicked(at: Support.buttonPoint, in: self.target)
    let pick = model.window(for: self.target).pick
    model.refreshTapped(in: self.target)
    await Support.waitUntil { model.window(for: self.target).failure != nil }
    let window = model.window(for: self.target)
    #expect(window.failure == .displayOff)
    #expect(window.snapshot == .sample())
    #expect(window.pick == pick)
    #expect(!window.isLoading)
  }

  @Test("새 스냅샷을 읽으면 같은 클릭 점으로 다시 골라 가장 안쪽 노드를 고른다 (노드 번호는 새 덤프 기준)")
  func refreshRepicksSamePoint() async {
    let (model, fake) = Support.fixture()
    // 새 덤프: 툴바 앞에 노드 하나가 더 있어 번호가 하나씩 밀린다.
    var shifted = LayoutSnapshot.sampleNodes.map { node in
      LayoutNode(
        id: node.id + 1, depth: node.depth, parentID: node.parentID.map { $0 + 1 } ?? 0, frame: node.frame,
        type: node.type, identifier: node.identifier, text: node.text, label: node.label
      )
    }
    shifted[0] = LayoutNode(
      id: 1, depth: 1, parentID: 0, frame: shifted[0].frame, type: shifted[0].type
    )
    let newSnapshot = LayoutSnapshot.sample(
      capturedAt: Date(timeIntervalSince1970: 1_800_000_100),
      nodes: [LayoutNode(
        id: 0,
        depth: 0,
        parentID: nil,
        frame: LayoutRect(x: 0, y: 0, width: 1080, height: 2400),
        type: "android.widget.LinearLayout"
      )] + shifted
    )
    fake.enqueue(.success(.sample()), for: self.target)
    fake.enqueue(.success(newSnapshot), for: self.target)
    await Support.open(model)
    model.canvasClicked(at: Support.buttonPoint, in: self.target)
    model.stackNodeSelected(1, in: self.target)
    #expect(model.window(for: self.target).pick?.selected == 1)
    model.refreshTapped(in: self.target)
    await Support.waitUntil { model.window(for: self.target).snapshot == newSnapshot }
    let pick = model.window(for: self.target).pick
    #expect(pick?.point == Support.buttonPoint)
    #expect(pick?.stack == newSnapshot.nodes(at: Support.buttonPoint))
    #expect(pick?.selected == 3)
    #expect(model.selectedNode(for: self.target)?.label == "Navigate up")
  }

  @Test("클릭 점이 새 화면 밖이면(회전 등) 새로 읽은 뒤 고름을 푼다")
  func refreshOutsideClearsPick() async {
    let (model, fake) = Support.fixture()
    let landscape = LayoutSnapshot.sample(
      capturedAt: Date(timeIntervalSince1970: 1_800_000_100),
      pixelSize: LayoutSize(width: 2400, height: 1080),
      nodes: [LayoutNode(
        id: 0,
        depth: 0,
        parentID: nil,
        frame: LayoutRect(x: 0, y: 0, width: 2400, height: 1080),
        type: "android.widget.FrameLayout"
      )]
    )
    fake.enqueue(.success(.sample()), for: self.target)
    fake.enqueue(.success(landscape), for: self.target)
    await Support.open(model)
    let lowPoint = LayoutPoint(x: 540, y: 2000)
    model.canvasClicked(at: lowPoint, in: self.target)
    #expect(model.window(for: self.target).pick != nil)
    model.refreshTapped(in: self.target)
    await Support.waitUntil { model.window(for: self.target).snapshot == landscape }
    #expect(model.window(for: self.target).pick == nil)
  }

  // MARK: - 창 닫기

  @Test("읽는 중 창을 닫으면 읽기를 취소하고 창 값을 버리며, 다시 열면 새로 읽는다")
  func disappearCancelsAndReopenReads() async {
    let (model, fake) = Support.fixture()
    fake.setHolding(true)
    model.windowAppeared(self.target)
    await fake.waitUntilHeld(self.target)
    model.windowDisappeared(self.target)
    await Support.waitUntil { fake.heldCount(for: self.target) == 0 }
    #expect(model.windows[self.target] == nil)
    fake.setHolding(false)
    fake.enqueue(.success(.sample()), for: self.target)
    await Support.open(model)
    #expect(fake.calls.count == 2)
    #expect(model.window(for: self.target).snapshot == .sample())
  }

  @Test("닫은 뒤 늦게 끝난 앞 읽기의 결과·단계는 다시 연 창에 들어가지 않는다")
  func lateResultAfterReopenIgnored() async {
    let client = ControlledScreenLayoutClient()
    let model = LayoutInspectorModel(screenLayout: client)
    model.windowAppeared(self.target)
    await Support.waitUntil { client.waitingCount == 1 }
    model.windowDisappeared(self.target)
    model.windowAppeared(self.target)
    await Support.waitUntil { client.waitingCount == 2 }
    // 앞 읽기(취소를 보지 않는다)가 이제야 단계를 알리고 성공한다.
    await client.sendPhase(.preparing, toCall: 0)
    client.finish(call: 0, with: .success(.sample()))
    await Support.settle()
    var window = model.window(for: self.target)
    #expect(window.loading == .reading)
    #expect(window.snapshot == nil)
    client.finish(call: 1, with: .failure(.timedOut))
    await Support.waitUntil { !model.window(for: self.target).isLoading }
    window = model.window(for: self.target)
    #expect(window.failure == .timedOut)
    #expect(window.snapshot == nil)
  }

  @Test("닫힌 창에는 늦은 결과가 창 값을 다시 만들지 않는다")
  func lateResultAfterCloseIgnored() async {
    let client = ControlledScreenLayoutClient()
    let model = LayoutInspectorModel(screenLayout: client)
    model.windowAppeared(self.target)
    await Support.waitUntil { client.waitingCount == 1 }
    model.windowDisappeared(self.target)
    client.finish(call: 0, with: .success(.sample()))
    await Support.settle()
    #expect(model.windows.isEmpty)
  }
}

/// `ScreenLayoutError` → 화면 실패 분류.
struct LayoutInspectorFailureTests {
  static let mapping: [(ScreenLayoutError, LayoutInspectorFailure?)] = [
    (.xcodeUnavailable, .xcodeUnavailable),
    (.inspectorSetupFailed, .setupFailed),
    (.appNotInForeground, .appNotInForeground),
    (.deviceNotFound, .deviceGone),
    (.deviceUnavailable, .deviceGone),
    (.deviceNotBooted, .deviceNotBooted),
    (.toolsUnavailable, .toolsUnavailable),
    (.screenNotIdle, .screenNotIdle),
    (.displayOff, .displayOff),
    (.automationBusy, .automationBusy),
    (.timedOut, .timedOut),
    (.unreadable, .unreadable),
    (.cancelled, nil),
    (.unsupportedPlatform, .unsupported),
  ]

  @Test("모든 오류가 정한 분류로 가고, 취소만 분류가 없으며, 모든 분류가 쓰인다")
  func mappingTable() {
    for (error, expected) in Self.mapping {
      #expect(LayoutInspectorFailure(error) == expected, "\(error)")
    }
    #expect(Set(Self.mapping.compactMap(\.1)) == Set(LayoutInspectorFailure.allCases))
  }
}
