import Core
import Foundation
import ScreenLayoutInterface
import ScreenLayoutTesting
import Testing
@testable import LayoutInspectorFeature

@MainActor
struct LayoutInspectorModelPickTests {
  private typealias Support = LayoutInspectorTestSupport
  private let target = Support.target

  // MARK: - 고르기

  @Test("캔버스 클릭은 점의 가장 안쪽 노드를 고르고, 스택은 바깥→안쪽이다")
  func clickPicksInnermost() async {
    let (model, fake) = Support.fixture()
    fake.enqueue(.success(.sample()), for: self.target)
    await Support.open(model)
    model.canvasClicked(at: Support.buttonPoint, in: self.target)
    #expect(model.window(for: self.target).pick?.stack == [0, 1, 2])
    #expect(model.window(for: self.target).pick?.selected == 2)
    #expect(model.stackNodes(for: self.target).map(\.id) == [0, 1, 2])
    model.canvasClicked(at: Support.itemPoint, in: self.target)
    #expect(model.window(for: self.target).pick?.stack == [0, 3, 4])
    #expect(model.selectedNode(for: self.target)?.text == "Wi-Fi")
  }

  @Test("노드가 없는 곳이나 화면 밖을 클릭하면 고름을 푼다")
  func clickEmptyClearsPick() async {
    let (model, fake) = Support.fixture()
    let sparse = LayoutSnapshot.sample(nodes: [LayoutSnapshot.sampleNodes[2]].map {
      LayoutNode(id: 0, depth: 0, parentID: nil, frame: $0.frame, type: $0.type, label: $0.label)
    })
    fake.enqueue(.success(sparse), for: self.target)
    await Support.open(model)
    model.canvasClicked(at: Support.buttonPoint, in: self.target)
    #expect(model.window(for: self.target).pick?.selected == 0)
    model.canvasClicked(at: LayoutPoint(x: 900, y: 1500), in: self.target)
    #expect(model.window(for: self.target).pick == nil)
    model.canvasClicked(at: Support.buttonPoint, in: self.target)
    model.canvasClicked(at: LayoutPoint(x: 5000, y: 5000), in: self.target)
    #expect(model.window(for: self.target).pick == nil)
    #expect(model.selectedNode(for: self.target) == nil)
    #expect(model.stackNodes(for: self.target).isEmpty)
  }

  @Test("스냅샷이 없으면 클릭을 무시한다")
  func clickWithoutSnapshotIgnored() async {
    let (model, fake) = Support.fixture()
    fake.setHolding(true)
    model.windowAppeared(self.target)
    await fake.waitUntilHeld(self.target)
    model.canvasClicked(at: Support.buttonPoint, in: self.target)
    #expect(model.window(for: self.target).pick == nil)
    model.canvasClicked(at: Support.buttonPoint, in: Support.otherTarget)
    #expect(model.windows[Support.otherTarget] == nil)
  }

  @Test("목록 고르기는 지금 스택 안의 노드만 바꾼다")
  func stackSelection() async {
    let (model, fake) = Support.fixture()
    fake.enqueue(.success(.sample()), for: self.target)
    await Support.open(model)
    model.stackNodeSelected(1, in: self.target)
    #expect(model.window(for: self.target).pick == nil)
    model.canvasClicked(at: Support.buttonPoint, in: self.target)
    model.stackNodeSelected(1, in: self.target)
    #expect(model.window(for: self.target).pick?.selected == 1)
    model.stackNodeSelected(4, in: self.target)
    #expect(model.window(for: self.target).pick?.selected == 1)
  }

  // MARK: - 제목·여러 창

  @Test("기기 이름을 모르면 제목은 스냅샷 전에는 기기 ID, 뒤에는 스냅샷의 기기 이름이다")
  func title() async {
    let (model, fake) = Support.fixture()
    fake.setHolding(true)
    fake.enqueue(.success(.sample(deviceName: "Pixel 9")), for: self.target)
    model.windowAppeared(self.target)
    await fake.waitUntilHeld(self.target)
    #expect(model.title(for: self.target) == "Pixel_9 레이아웃")
    fake.release(self.target)
    await Support.waitUntil { model.window(for: self.target).snapshot != nil }
    #expect(model.title(for: self.target) == "Pixel 9 레이아웃")
  }

  @Test("스냅샷 전에 Client 가 기기 이름을 알려 주면 제목에 쓰고, 첫 읽기가 실패해도 그 이름이다")
  func titleUsesResolvedNameBeforeSnapshot() async {
    let (model, fake) = Support.fixture()
    let iOS = LayoutTarget.iOS(VirtualDevice.ID("11111111-2222-3333-4444-555555555555"))
    fake.setDeviceName("Design iPhone", for: iOS)
    fake.setHolding(true)
    fake.enqueue(.failure(.inspectorSetupFailed), for: iOS)
    model.windowAppeared(iOS)
    await fake.waitUntilHeld(iOS)
    await Support.waitUntil { model.window(for: iOS).deviceName != nil }
    #expect(model.title(for: iOS) == "Design iPhone 레이아웃")
    fake.release(iOS)
    await Support.waitUntil { !model.window(for: iOS).isLoading }
    #expect(model.window(for: iOS).failure != nil)
    #expect(model.title(for: iOS) == "Design iPhone 레이아웃")
  }

  @Test("스냅샷의 기기 이름이 창을 열 때 물은 이름보다 앞선다 (그 사이 이름을 바꾼 경우)")
  func snapshotNameWinsOverResolvedName() async {
    let (model, fake) = Support.fixture()
    fake.setDeviceName("Old Name", for: self.target)
    fake.enqueue(.success(.sample(deviceName: "Pixel 9")), for: self.target)
    await Support.open(model)
    await Support.waitUntil { model.window(for: self.target).deviceName != nil }
    #expect(model.title(for: self.target) == "Pixel 9 레이아웃")
  }

  @Test("창을 닫으면 기기 이름도 버리고, 다시 열면 다시 묻는다")
  func closeDropsResolvedName() async {
    let (model, fake) = Support.fixture()
    fake.setDeviceName("Pixel 9", for: self.target)
    fake.setHolding(true)
    model.windowAppeared(self.target)
    await Support.waitUntil { model.window(for: self.target).deviceName != nil }
    model.windowDisappeared(self.target)
    #expect(model.window(for: self.target).deviceName == nil)
    fake.setDeviceName(nil, for: self.target)
    model.windowAppeared(self.target)
    await fake.waitUntilHeld(self.target)
    await Support.settle()
    #expect(model.title(for: self.target) == "Pixel_9 레이아웃")
  }

  @Test("두 기기의 창은 서로의 읽기·고름에 영향이 없다")
  func windowsAreIndependent() async {
    let (model, fake) = Support.fixture()
    let other = Support.otherTarget
    fake.enqueue(.success(.sample()), for: self.target)
    fake.enqueue(.failure(.deviceNotBooted), for: other)
    await Support.open(model)
    await Support.open(model, other)
    model.canvasClicked(at: Support.buttonPoint, in: self.target)
    #expect(model.window(for: self.target).snapshot == .sample())
    #expect(model.window(for: other).snapshot == nil)
    #expect(model.window(for: other).failure == .deviceNotBooted)
    #expect(model.window(for: other).pick == nil)
    model.windowDisappeared(other)
    #expect(model.window(for: self.target).pick?.selected == 2)
    #expect(model.windows.keys.sorted { $0.deviceID < $1.deviceID } == [self.target])
  }
}
