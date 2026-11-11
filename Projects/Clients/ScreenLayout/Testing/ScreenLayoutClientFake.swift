import Core
import Foundation
import ScreenLayoutInterface
import Synchronization

/// 테스트·Example 용 `ScreenLayoutClient`. 호출을 기록하고, 대상별로 넣어 둔 결과를 차례로 돌려준다.
///
/// 한 호출의 흐름: 호출 기록 → `automaticPhases` 를 차례로 `onPhase` 로 보냄 → (붙잡기가 켜져 있으면) `release` 까지 기다림
/// → 그 대상의 결과 큐 맨 앞(비었으면 `defaultResult`)을 돌려준다. 결과는 기다림이 끝난 때 꺼내므로 붙잡힌 뒤에 넣어도 된다.
/// 붙잡힌 호출의 Task 가 취소되면 결과를 꺼내지 않고 `.cancelled` 를 던진다.
public final class ScreenLayoutClientFake: ScreenLayoutClient {
  private struct Held {
    let id: UUID
    let target: LayoutTarget
    let onPhase: @Sendable (LayoutReadPhase) async -> Void
    var continuation: CheckedContinuation<Bool, Never>?
    var cancelled = false
  }

  private struct State {
    var calls: [LayoutTarget] = []
    var results: [LayoutTarget: [Result<LayoutSnapshot, ScreenLayoutError>]] = [:]
    var defaultResult: Result<LayoutSnapshot, ScreenLayoutError>
    var automaticPhases: [LayoutReadPhase]
    var deviceNames: [LayoutTarget: String] = [:]
    var holding = false
    var held: [Held] = []
    var heldWaiters: [CheckedContinuation<Void, Never>] = []
  }

  private let state: Mutex<State>

  /// - Parameters:
  ///   - defaultResult: 대상의 결과 큐가 비었을 때 돌려줄 결과.
  ///   - automaticPhases: 호출마다 붙잡기 전에 보낼 단계 (실제 Android 처럼 `.reading` 한 번이 기본).
  public init(
    defaultResult: Result<LayoutSnapshot, ScreenLayoutError> = .failure(.unreadable),
    automaticPhases: [LayoutReadPhase] = [.reading]
  ) {
    self.state = Mutex(State(defaultResult: defaultResult, automaticPhases: automaticPhases))
  }

  /// 들어온 호출의 대상, 순서대로.
  public var calls: [LayoutTarget] {
    self.state.withLock { $0.calls }
  }

  // MARK: - 조종

  /// 대상의 결과 큐 끝에 넣는다.
  public func enqueue(_ result: Result<LayoutSnapshot, ScreenLayoutError>, for target: LayoutTarget) {
    self.state.withLock { $0.results[target, default: []].append(result) }
  }

  /// 결과 큐가 비었을 때의 결과를 바꾼다.
  public func setDefaultResult(_ result: Result<LayoutSnapshot, ScreenLayoutError>) {
    self.state.withLock { $0.defaultResult = result }
  }

  /// `deviceName(of:)` 이 돌려줄 이름을 정한다 (nil 이면 지운다. 기본은 모두 nil).
  public func setDeviceName(_ name: String?, for target: LayoutTarget) {
    self.state.withLock { $0.deviceNames[target] = name }
  }

  /// 호출마다 자동으로 보낼 단계를 바꾼다.
  public func setAutomaticPhases(_ phases: [LayoutReadPhase]) {
    self.state.withLock { $0.automaticPhases = phases }
  }

  /// true 면 이후 호출이 단계를 보낸 뒤 `release` 까지 기다린다. false 로 바꿔도 이미 붙잡힌 호출은 놓지 않는다.
  public func setHolding(_ holding: Bool) {
    self.state.withLock { $0.holding = holding }
  }

  /// 붙잡혀 있는(취소되지 않은) 그 대상의 호출 수.
  public func heldCount(for target: LayoutTarget) -> Int {
    self.state.withLock { state in state.held.count { $0.target == target && !$0.cancelled } }
  }

  /// 그 대상의 호출이 `count` 개 이상 붙잡힐 때까지 기다린다.
  public func waitUntilHeld(_ target: LayoutTarget, count: Int = 1) async {
    while self.heldCount(for: target) < count {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let ready = self.state.withLock { state in
          if state.held.count(where: { $0.target == target && !$0.cancelled }) >= count {
            return true
          }
          state.heldWaiters.append(continuation)
          return false
        }
        if ready {
          continuation.resume()
        }
      }
    }
  }

  /// 붙잡힌 그 대상의 가장 오래된 호출에 단계를 보낸다 (그 호출의 `onPhase`). 없으면 아무것도 하지 않는다.
  public func sendPhase(_ phase: LayoutReadPhase, to target: LayoutTarget) async {
    let onPhase = self.state.withLock { state in
      state.held.first { $0.target == target && !$0.cancelled }?.onPhase
    }
    await onPhase?(phase)
  }

  /// 붙잡힌 그 대상의 가장 오래된 호출을 놓는다 (그 호출은 결과 큐에서 결과를 꺼내 돌려준다). 없으면 false.
  @discardableResult
  public func release(_ target: LayoutTarget) -> Bool {
    let continuation = self.state.withLock { state -> CheckedContinuation<Bool, Never>? in
      guard let index = state.held.firstIndex(where: { $0.target == target && !$0.cancelled && $0.continuation != nil })
      else { return nil }
      let continuation = state.held[index].continuation
      state.held.remove(at: index)
      return continuation
    }
    continuation?.resume(returning: true)
    return continuation != nil
  }

  // MARK: - ScreenLayoutClient

  public func snapshot(
    of target: LayoutTarget,
    onPhase: @escaping @Sendable (LayoutReadPhase) async -> Void
  ) async throws(ScreenLayoutError) -> LayoutSnapshot {
    let (phases, holding) = self.state.withLock { state in
      state.calls.append(target)
      return (state.automaticPhases, state.holding)
    }
    for phase in phases {
      await onPhase(phase)
    }
    if holding {
      let released = await self.hold(target, onPhase: onPhase)
      guard released else { throw .cancelled }
    }
    let result = self.state.withLock { state in
      if var queue = state.results[target], !queue.isEmpty {
        let first = queue.removeFirst()
        state.results[target] = queue
        return first
      }
      return state.defaultResult
    }
    return try result.get()
  }

  public func deviceName(of target: LayoutTarget) async -> String? {
    self.state.withLock { $0.deviceNames[target] }
  }

  /// `release` 면 true, 취소면 false.
  private func hold(
    _ target: LayoutTarget,
    onPhase: @escaping @Sendable (LayoutReadPhase) async -> Void
  ) async -> Bool {
    let id = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
        let (waiters, cancelledAlready) = self.state.withLock { state in
          if let index = state.held.firstIndex(where: { $0.id == id }) {
            // 기다림을 시작하기 전에 취소됐다.
            state.held.remove(at: index)
            return ([CheckedContinuation<Void, Never>](), true)
          }
          state.held.append(Held(id: id, target: target, onPhase: onPhase, continuation: continuation))
          let waiters = state.heldWaiters
          state.heldWaiters = []
          return (waiters, false)
        }
        if cancelledAlready {
          continuation.resume(returning: false)
          return
        }
        for waiter in waiters {
          waiter.resume()
        }
      }
    } onCancel: {
      let continuation = self.state.withLock { state -> CheckedContinuation<Bool, Never>? in
        if let index = state.held.firstIndex(where: { $0.id == id }) {
          let continuation = state.held[index].continuation
          state.held.remove(at: index)
          return continuation
        }
        // 아직 붙잡히기 전: 표시만 남겨 두면 붙잡을 때 곧바로 취소로 끝낸다.
        state.held.append(Held(id: id, target: target, onPhase: onPhase, continuation: nil, cancelled: true))
        return nil
      }
      continuation?.resume(returning: false)
    }
  }
}
