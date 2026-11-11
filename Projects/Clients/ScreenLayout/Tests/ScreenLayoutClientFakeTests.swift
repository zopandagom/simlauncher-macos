import Core
import Foundation
import ScreenLayoutInterface
import ScreenLayoutTesting
import Synchronization
import Testing

/// Feature 테스트·Example 이 기대는 Fake 동작.
struct ScreenLayoutClientFakeTests {
  final class Phases: Sendable {
    private let phases = Mutex<[LayoutReadPhase]>([])

    func add(_ phase: LayoutReadPhase) {
      self.phases.withLock { $0.append(phase) }
    }

    var all: [LayoutReadPhase] {
      self.phases.withLock { $0 }
    }
  }

  static let pixel = LayoutTarget.android(AndroidVirtualDevice.ID("Pixel"))
  static let tablet = LayoutTarget.android(AndroidVirtualDevice.ID("Tablet"))

  @Test("기기 이름은 대상별로 정한 값이고, 정하지 않았거나 지우면 nil. 스냅샷 호출로 기록하지 않는다")
  func deviceName() async {
    let fake = ScreenLayoutClientFake()
    #expect(await fake.deviceName(of: Self.pixel) == nil)
    fake.setDeviceName("Pixel 9", for: Self.pixel)
    #expect(await fake.deviceName(of: Self.pixel) == "Pixel 9")
    #expect(await fake.deviceName(of: Self.tablet) == nil)
    fake.setDeviceName(nil, for: Self.pixel)
    #expect(await fake.deviceName(of: Self.pixel) == nil)
    #expect(fake.calls.isEmpty)
  }

  @Test("대상별 결과를 넣은 순서대로 돌려주고, 비면 기본 결과. 호출과 자동 단계를 기록한다")
  func results() async throws {
    let fake = ScreenLayoutClientFake()
    let phases = Phases()
    fake.enqueue(.success(.sample(deviceName: "A")), for: Self.pixel)
    fake.enqueue(.failure(.displayOff), for: Self.pixel)
    fake.enqueue(.success(.sample(deviceName: "T")), for: Self.tablet)

    #expect(try await fake.snapshot(of: Self.pixel) { phases.add($0) }.deviceName == "A")
    #expect(try await fake.snapshot(of: Self.tablet) { phases.add($0) }.deviceName == "T")
    await #expect(throws: ScreenLayoutError.displayOff) { try await fake.snapshot(of: Self.pixel) { _ in } }
    await #expect(throws: ScreenLayoutError.unreadable) { try await fake.snapshot(of: Self.pixel) { _ in } }
    fake.setDefaultResult(.success(.sample()))
    #expect(try await fake.snapshot(of: Self.pixel) { _ in } == .sample())

    #expect(fake.calls == [Self.pixel, Self.tablet, Self.pixel, Self.pixel, Self.pixel])
    #expect(phases.all == [.reading, .reading])
  }

  @Test("붙잡기: 자동 단계 뒤 기다리고, 늦은 단계를 보낼 수 있으며, release 때 큐에서 결과를 꺼낸다")
  func holding() async throws {
    let fake = ScreenLayoutClientFake(automaticPhases: [.preparing])
    fake.setHolding(true)
    let phases = Phases()
    let reading = Task { try await fake.snapshot(of: Self.pixel) { phases.add($0) } }
    await fake.waitUntilHeld(Self.pixel)
    #expect(phases.all == [.preparing])
    #expect(fake.heldCount(for: Self.tablet) == 0)

    await fake.sendPhase(.reading, to: Self.pixel)
    fake.enqueue(.success(.sample(deviceName: "late")), for: Self.pixel)
    #expect(fake.release(Self.pixel))

    #expect(try await reading.value.deviceName == "late")
    #expect(phases.all == [.preparing, .reading])
    #expect(fake.heldCount(for: Self.pixel) == 0)
    #expect(!fake.release(Self.pixel))
  }

  @Test("붙잡힌 호출이 취소되면 결과를 꺼내지 않고 cancelled")
  func cancelHeld() async throws {
    let fake = ScreenLayoutClientFake()
    fake.setHolding(true)
    fake.enqueue(.success(.sample(deviceName: "kept")), for: Self.pixel)
    let reading = Task { try await fake.snapshot(of: Self.pixel) { _ in } }
    await fake.waitUntilHeld(Self.pixel)

    reading.cancel()

    await #expect(throws: ScreenLayoutError.cancelled) { try await reading.value }
    #expect(fake.heldCount(for: Self.pixel) == 0)
    fake.setHolding(false)
    #expect(try await fake.snapshot(of: Self.pixel) { _ in }.deviceName == "kept")
  }

  @Test("붙잡힌 호출 여럿은 오래된 것부터 놓는다")
  func releaseOrder() async throws {
    let fake = ScreenLayoutClientFake()
    fake.setHolding(true)
    fake.enqueue(.success(.sample(deviceName: "1")), for: Self.pixel)
    fake.enqueue(.success(.sample(deviceName: "2")), for: Self.pixel)
    let first = Task { try await fake.snapshot(of: Self.pixel) { _ in } }
    await fake.waitUntilHeld(Self.pixel)
    let second = Task { try await fake.snapshot(of: Self.pixel) { _ in } }
    await fake.waitUntilHeld(Self.pixel, count: 2)

    fake.release(Self.pixel)
    #expect(try await first.value.deviceName == "1")
    fake.release(Self.pixel)
    #expect(try await second.value.deviceName == "2")
  }

  @Test("샘플: 'Navigate up' 점의 스택과 숨긴 크기 0 노드")
  func sample() {
    let sample = LayoutSnapshot.sample()

    #expect(sample.nodes(at: LayoutPoint(x: 100, y: 150)) == [0, 1, 2])
    #expect(sample.nodes(at: LayoutPoint(x: 500, y: 200)) == [0, 3, 4])
    #expect(sample.visibleNodes.map(\.id) == [0, 1, 2, 3, 4])
  }
}
