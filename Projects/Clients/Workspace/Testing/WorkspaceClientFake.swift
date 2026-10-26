import Core
import Foundation
import Synchronization
import WorkspaceInterface

/// 테스트·Example 용 `WorkspaceClient`. 파일을 만들지 않고 메모리의 예약 목록과 호출 기록만 둔다. Finder 를 열지 않는다.
/// 예약은 스크린샷이면 `folder`, 녹화면 `moviesFolder` 아래 `name.fileName(attempt: n)` 을 돌려주고, n 은 지금 예약 목록에
/// 그 파일이 없는 가장 작은 번호다 (Impl 의 독점 생성과 같다: `removeReservedFile` 로 뺀 이름은 다시 쓸 수 있다).
/// 99 까지 모두 있으면 `.fileNameUnavailable`. 예약 목록은 하나다 (폴더가 달라 두 예약의 파일이 겹치지 않는다).
/// 지우기는 크기를 보지 않고 목록에서 뺀다 (Fake 파일에는 내용이 없다).
/// 보이기는 기록만 하고 성공한다 (예약 목록에 없어도). 오류는 `setReserveError(_:)`·`setRevealError(_:)` 로 바꾼다.
public final class WorkspaceClientFake: WorkspaceClient {
  public enum Call: Hashable, Sendable {
    case reserveScreenshotFile(stem: String)
    case reserveRecordingFile(stem: String)
    case removeReservedFile(URL)
    case revealInFinder(URL)
  }

  /// 스크린샷 예약 파일이 들어가는 가짜 저장 폴더.
  public static let folder = URL(filePath: "/SimLauncher-Fake/", directoryHint: .isDirectory)
  /// 녹화 예약 파일이 들어가는 가짜 저장 폴더.
  public static let moviesFolder = URL(filePath: "/SimLauncher-Fake-Movies/", directoryHint: .isDirectory)

  private struct State {
    var calls: [Call] = []
    var reservedFiles: [URL] = []
    var reserveError: WorkspaceError?
    var revealError: WorkspaceError?
    var reservesSuspended = false
    var waiters: [CheckedContinuation<Void, Never>] = []
  }

  private let state = Mutex(State())

  public init() {}

  /// 들어온 호출 순서대로. 멈춘 호출도 들어오는 즉시 기록된다.
  public var calls: [Call] {
    self.state.withLock { $0.calls }
  }

  /// 지금 예약된 파일 (예약 순서, 지운 것은 빠진다).
  public var reservedFiles: [URL] {
    self.state.withLock { $0.reservedFiles }
  }

  /// 이후 예약(스크린샷·녹화)이 이 오류로 실패한다 (`nil` 이면 성공). 기록은 그대로 한다.
  public func setReserveError(_ error: WorkspaceError?) {
    self.state.withLock { $0.reserveError = error }
  }

  /// 이후 보이기가 이 오류로 실패한다 (`nil` 이면 성공).
  public func setRevealError(_ error: WorkspaceError?) {
    self.state.withLock { $0.revealError = error }
  }

  /// 이후 `reserveScreenshotFile(_:)`·`reserveRecordingFile(_:)` 이 기록만 하고 `resumeReserves()` 까지 기다린다.
  public func suspendReserves() {
    self.state.withLock { $0.reservesSuspended = true }
  }

  /// 기다리는 예약을 모두 이어 가고, 이후 예약은 멈추지 않는다.
  public func resumeReserves() {
    let waiters = self.state.withLock { state in
      state.reservesSuspended = false
      let waiters = state.waiters
      state.waiters = []
      return waiters
    }
    for waiter in waiters {
      waiter.resume()
    }
  }

  public func reserveScreenshotFile(_ name: ScreenshotFileName) async throws(WorkspaceError) -> URL {
    try await self.reserve(
      .reserveScreenshotFile(stem: name.stem),
      in: Self.folder,
      maxAttempts: ScreenshotFileName.maxAttempts
    ) { name.fileName(attempt: $0) }
  }

  public func reserveRecordingFile(_ name: RecordingFileName) async throws(WorkspaceError) -> URL {
    try await self.reserve(
      .reserveRecordingFile(stem: name.stem),
      in: Self.moviesFolder,
      maxAttempts: RecordingFileName.maxAttempts
    ) { name.fileName(attempt: $0) }
  }

  public func removeReservedFile(_ file: URL) async {
    self.state.withLock { state in
      state.calls.append(.removeReservedFile(file))
      state.reservedFiles.removeAll { $0 == file }
    }
  }

  public func revealInFinder(_ file: URL) async throws(WorkspaceError) {
    try self.state.withLock { (current: inout State) throws(WorkspaceError) in
      current.calls.append(.revealInFinder(file))
      if let error = current.revealError {
        throw error
      }
    }
  }

  /// 기록 → 멈춤 확인 → 오류 설정이면 throw → `folder` 아래 빈 번호 예약. 스크린샷·녹화가 함께 쓴다.
  private func reserve(
    _ call: Call,
    in folder: URL,
    maxAttempts: Int,
    fileName: (Int) -> String?
  ) async throws(WorkspaceError) -> URL {
    self.state.withLock { $0.calls.append(call) }
    await self.waitIfSuspended()
    return try self.state.withLock { (current: inout State) throws(WorkspaceError) -> URL in
      if let error = current.reserveError {
        throw error
      }
      for attempt in 1 ... maxAttempts {
        guard let fileName = fileName(attempt) else { break }
        let file = folder.appending(path: fileName, directoryHint: .notDirectory)
        if !current.reservedFiles.contains(file) {
          current.reservedFiles.append(file)
          return file
        }
      }
      throw .fileNameUnavailable
    }
  }

  private func waitIfSuspended() async {
    // 플래그 확인과 continuation 저장을 한 lock 안에서 해야 resume 이 저장보다 먼저 와도 놓치지 않는다.
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let wait = self.state.withLock { state in
        guard state.reservesSuspended else { return false }
        state.waiters.append(continuation)
        return true
      }
      if !wait {
        continuation.resume()
      }
    }
  }
}
