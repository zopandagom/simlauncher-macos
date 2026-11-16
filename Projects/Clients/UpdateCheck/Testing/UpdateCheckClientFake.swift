import Core
import Foundation
import Synchronization
import UpdateCheckInterface

/// 테스트·Example 용 `UpdateCheckClient`. 호출 수를 세고, 결과·멈춤을 바꿀 수 있다. 네트워크를 쓰지 않는다.
/// `latestReleaseVersion()` 은 호출 수 기록 → `releasePageURL` 이 nil 이면 `.notConfigured` → 취소 확인(`.cancelled`)
/// → 멈춤이면 `resume()` 이나 Task 취소(`.cancelled`)까지 기다림 → 그때의 결과 순서다 (`DownloadClientFake` 의 멈춤과 같은 결).
public final class UpdateCheckClientFake: UpdateCheckClient {
  private struct State {
    var result: Result<AppVersion?, UpdateCheckError>
    var callCount = 0
    var isSuspended = false
    /// 멈춘 호출. 재개면 true, 취소면 false 로 깨우고 목록에서 뺀다.
    var suspended: [UUID: CheckedContinuation<Bool, Never>] = [:]
    /// 기다리기 전에 취소가 먼저 온 호출.
    var cancelledWaits: Set<UUID> = []
  }

  public let releasePageURL: URL?
  private let state: Mutex<State>

  /// 기본 저장소 주소 `https://github.com/example/app/releases/latest`, 기본 결과 `.success(nil)`(버전 값 해석 불가).
  public init(
    releasePageURL: URL? = URL(string: "https://github.com/example/app/releases/latest"),
    result: Result<AppVersion?, UpdateCheckError> = .success(nil)
  ) {
    self.releasePageURL = releasePageURL
    self.state = Mutex(State(result: result))
  }

  /// 이후 호출의 결과 (멈춘 호출은 재개될 때의 결과를 받는다).
  public func setResult(_ result: Result<AppVersion?, UpdateCheckError>) {
    self.state.withLock { $0.result = result }
  }

  /// 이후 호출을 `resume()` 까지 멈춘다.
  public func suspend() {
    self.state.withLock { $0.isSuspended = true }
  }

  /// 멈춘 호출을 모두 지금 결과로 끝내고, 이후 호출은 멈추지 않는다.
  public func resume() {
    let ready: [CheckedContinuation<Bool, Never>] = self.state.withLock { state in
      state.isSuspended = false
      let ready = Array(state.suspended.values)
      state.suspended = [:]
      return ready
    }
    for continuation in ready {
      continuation.resume(returning: true)
    }
  }

  /// 들어온 호출 수 (releasePageURL nil 이어도 센다).
  public var callCount: Int {
    self.state.withLock { $0.callCount }
  }

  /// 지금 멈춰 기다리는 호출 수 (테스트가 "요청이 시작됐다"를 기다리는 데 쓴다).
  public var suspendedCallCount: Int {
    self.state.withLock { $0.suspended.count }
  }

  public func latestReleaseVersion() async throws(UpdateCheckError) -> AppVersion? {
    self.state.withLock { $0.callCount += 1 }
    guard self.releasePageURL != nil else {
      throw .notConfigured
    }
    guard !Task.isCancelled else {
      throw .cancelled
    }
    guard await self.waitIfSuspended() else {
      throw .cancelled
    }
    return try self.state.withLock { $0.result }.get()
  }

  /// 멈춤이 아니면 바로 true. 멈춤이면 재개(true)나 Task 취소(false)까지 기다린다.
  private func waitIfSuspended() async -> Bool {
    let id = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
        // 플래그·취소 확인과 continuation 저장을 한 lock 안에서 해야 재개·취소를 놓치지 않는다.
        let immediate: Bool? = self.state.withLock { state in
          if state.cancelledWaits.remove(id) != nil {
            return false
          }
          guard state.isSuspended else {
            return true
          }
          state.suspended[id] = continuation
          return nil
        }
        if let immediate {
          continuation.resume(returning: immediate)
        }
      }
    } onCancel: {
      let ready: CheckedContinuation<Bool, Never>? = self.state.withLock { state in
        guard let continuation = state.suspended.removeValue(forKey: id) else {
          if state.isSuspended {
            state.cancelledWaits.insert(id)
          }
          return nil
        }
        return continuation
      }
      ready?.resume(returning: false)
    }
  }
}
