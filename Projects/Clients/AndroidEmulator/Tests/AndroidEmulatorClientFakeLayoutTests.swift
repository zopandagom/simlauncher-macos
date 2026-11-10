import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Foundation
import Testing

/// ScreenLayout 테스트가 기대는 Fake 의 레이아웃 읽기 동작.
struct AndroidEmulatorClientFakeLayoutTests {
  @Test("레이아웃: 기본은 샘플 스냅샷, 설정한 결과를 돌려주고 기록한다, 멈춤은 재개까지 기다린다")
  func layoutSnapshot() async throws {
    let fake = AndroidEmulatorClientFake(inventory: .sample)
    let tablet = AndroidVirtualDevice.bootedTabletSample.id

    #expect(try await fake.layoutSnapshot(on: tablet) == .androidLayoutSample)
    fake.setLayoutSnapshotResult(.failure(.layoutDisplayOff))
    await #expect(throws: AndroidEmulatorError.layoutDisplayOff) { try await fake.layoutSnapshot(on: tablet) }
    fake.setLayoutSnapshotResult(.success(.androidLayoutSample))
    fake.suspendLayoutSnapshots()
    let reading = Task { try await fake.layoutSnapshot(on: tablet) }
    while fake.calls.count < 3 {
      await Task.yield()
    }
    fake.resumeLayoutSnapshots()
    #expect(try await reading.value == .androidLayoutSample)
    #expect(fake.calls == Array(repeating: .layoutSnapshot(tablet), count: 3))
  }

  @Test("샘플 스냅샷은 dp 단위·2.625 배율이고 'Navigate up' 이 가장 안쪽")
  func sample() {
    let sample = LayoutSnapshot.androidLayoutSample

    #expect(sample.unit == .dp)
    #expect(sample.pixelsPerUnit == 2.625)
    #expect(sample.nodes(at: LayoutPoint(x: 100, y: 150)) == [0, 1])
  }
}
