import Core
import Foundation
import ScreenLayoutInterface
import Synchronization

/// 취소를 보지 않고, 테스트가 정한 때에 결과를 돌려주는 `ScreenLayoutClient`.
/// 창을 닫은 뒤에 끝난 앞 읽기(늦은 결과·늦은 단계 알림)를 흉내 낸다. 호출마다 `onPhase` 와 결과 대기를 기록한다.
final class ControlledScreenLayoutClient: ScreenLayoutClient {
  private struct Call {
    let target: LayoutTarget
    let onPhase: @Sendable (LayoutReadPhase) async -> Void
    var continuation: CheckedContinuation<Result<LayoutSnapshot, ScreenLayoutError>, Never>?
  }

  private let calls = Mutex<[Call]>([])

  var callCount: Int {
    self.calls.withLock { $0.count }
  }

  /// 결과를 기다리는 중인(continuation 이 걸린) 호출 수.
  var waitingCount: Int {
    self.calls.withLock { calls in calls.count { $0.continuation != nil } }
  }

  func snapshot(
    of target: LayoutTarget,
    onPhase: @escaping @Sendable (LayoutReadPhase) async -> Void
  ) async throws(ScreenLayoutError) -> LayoutSnapshot {
    let index = self.calls.withLock { calls in
      calls.append(Call(target: target, onPhase: onPhase))
      return calls.count - 1
    }
    let result = await withCheckedContinuation { continuation in
      self.calls.withLock { $0[index].continuation = continuation }
    }
    return try result.get()
  }

  /// `index` 번째 호출의 `onPhase` 를 부른다.
  func sendPhase(_ phase: LayoutReadPhase, toCall index: Int) async {
    let onPhase = self.calls.withLock { $0[index].onPhase }
    await onPhase(phase)
  }

  /// `index` 번째 호출에 결과를 준다.
  func finish(call index: Int, with result: Result<LayoutSnapshot, ScreenLayoutError>) {
    let continuation = self.calls.withLock { calls in
      let continuation = calls[index].continuation
      calls[index].continuation = nil
      return continuation
    }
    continuation?.resume(returning: result)
  }
}
