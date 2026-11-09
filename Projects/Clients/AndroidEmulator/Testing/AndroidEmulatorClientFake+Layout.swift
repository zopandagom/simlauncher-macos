import AndroidEmulatorInterface
import Core

/// 레이아웃 읽기 (`layoutSnapshot`) 의 Fake 동작과 설정 메서드.
public extension AndroidEmulatorClientFake {
  /// 기록 → 멈춤 → 지연 → 설정한 결과.
  func layoutSnapshot(on id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) -> LayoutSnapshot {
    self.record(.layoutSnapshot(id))
    await self.waitIfSuspended(.layout)
    await self.sleepIfNeeded()
    return try self.state.withLock { $0.layoutSnapshotResult }.get()
  }

  /// 이후 `layoutSnapshot(on:)` 의 결과.
  func setLayoutSnapshotResult(_ result: Result<LayoutSnapshot, AndroidEmulatorError>) {
    self.state.withLock { $0.layoutSnapshotResult = result }
  }

  /// 이후 `layoutSnapshot(on:)` 이 기록만 하고 `resumeLayoutSnapshots()` 까지 기다린다.
  func suspendLayoutSnapshots() {
    self.suspend(.layout)
  }

  func resumeLayoutSnapshots() {
    self.resume(.layout)
  }
}
