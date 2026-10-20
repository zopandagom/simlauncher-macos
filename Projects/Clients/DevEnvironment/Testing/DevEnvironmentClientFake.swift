import Core
import DevEnvironmentInterface
import Synchronization

/// 테스트·Example 용 `DevEnvironmentClient`. 호출을 기록하고, 상태·에러를 바꿀 수 있다. 명령은 실행하지 않는다.
/// `selectedXcode()` 는 설정한 상태의 Xcode(`status.xcode`)를 돌려준다 (Impl 처럼 같은 규칙 결과를 함께 쓴다).
public final class DevEnvironmentClientFake: DevEnvironmentClient {
  public enum Call: Hashable, Sendable {
    case selectedXcode
    case checkEnvironment
    case openXcode
    case openXcodeInAppStore
  }

  private struct State {
    var status: DevEnvironmentStatus
    var calls: [Call] = []
    var checkError: DevEnvironmentError?
    var openXcodeError: DevEnvironmentError?
    var openAppStoreError: DevEnvironmentError?
  }

  private let state: Mutex<State>

  public init(status: DevEnvironmentStatus = .ready(.sample)) {
    self.state = Mutex(State(status: status))
  }

  /// 들어온 호출 순서대로.
  public var calls: [Call] {
    self.state.withLock { $0.calls }
  }

  /// 이후 `checkEnvironment()` 결과와 `selectedXcode()`·`openXcode()` 가 쓰는 Xcode.
  public func setStatus(_ status: DevEnvironmentStatus) {
    self.state.withLock { $0.status = status }
  }

  /// non-nil 이면 `checkEnvironment()` 가 상태 대신 이 에러를 던진다.
  public func setCheckError(_ error: DevEnvironmentError?) {
    self.state.withLock { $0.checkError = error }
  }

  /// non-nil 이면 `openXcode()` 가 이 에러를 던진다 (Xcode 없음보다 우선).
  public func setOpenXcodeError(_ error: DevEnvironmentError?) {
    self.state.withLock { $0.openXcodeError = error }
  }

  /// non-nil 이면 `openXcodeInAppStore()` 가 이 에러를 던진다.
  public func setOpenAppStoreError(_ error: DevEnvironmentError?) {
    self.state.withLock { $0.openAppStoreError = error }
  }

  public func selectedXcode() async -> XcodeInstallation? {
    self.state.withLock { state in
      state.calls.append(.selectedXcode)
      return state.status.xcode
    }
  }

  public func checkEnvironment() async throws(DevEnvironmentError) -> DevEnvironmentStatus {
    let result: Result<DevEnvironmentStatus, DevEnvironmentError> = self.state.withLock { state in
      state.calls.append(.checkEnvironment)
      if let error = state.checkError {
        return .failure(error)
      }
      return .success(state.status)
    }
    return try result.get()
  }

  /// 설정한 에러 → 상태에 Xcode 가 없으면 `.xcodeNotFound` → 성공.
  public func openXcode() async throws(DevEnvironmentError) {
    let error: DevEnvironmentError? = self.state.withLock { state in
      state.calls.append(.openXcode)
      if let error = state.openXcodeError {
        return error
      }
      return state.status.xcode == nil ? .xcodeNotFound : nil
    }
    if let error {
      throw error
    }
  }

  public func openXcodeInAppStore() async throws(DevEnvironmentError) {
    let error = self.state.withLock { state in
      state.calls.append(.openXcodeInAppStore)
      return state.openAppStoreError
    }
    if let error {
      throw error
    }
  }
}
