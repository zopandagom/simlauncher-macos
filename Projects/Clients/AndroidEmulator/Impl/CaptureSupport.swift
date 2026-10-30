import AndroidEmulatorInterface
import Foundation
import Synchronization

/// 녹화 하나의 공유 상태: pid 읽기·시작 알림 한 번·멈춤 요청·녹화 adb 끝남. 출력 클로저와 취소 처리기(@Sendable)가 바꾸므로
/// lock 으로 감싼다. 기다리는 쪽은 녹화를 시작한 Task 하나다.
final class RecordingSession: Sendable {
  private struct State {
    var reader = RecordingPIDReader()
    var returned = false
    var stopRequested = false
    var ended = false
    var waiter: CheckedContinuation<Void, Never>?
  }

  private let state = Mutex(State())

  var pid: String? {
    self.state.withLock { $0.reader.pid }
  }

  var stopRequested: Bool {
    self.state.withLock { $0.stopRequested }
  }

  var hasEnded: Bool {
    self.state.withLock { $0.ended }
  }

  /// stdout 조각. 처음 pid 를 읽었고 아직 돌아오지 않았으면 true (그때만 `onStarted` 를 부른다).
  func feed(_ data: Data) -> Bool {
    self.state.withLock { $0.reader.feed(data) && !$0.returned }
  }

  func markReturned() {
    self.state.withLock { $0.returned = true }
  }

  func requestStop() {
    self.wake { $0.stopRequested = true }
  }

  func markEnded() {
    self.wake { $0.ended = true }
  }

  /// 멈춤 요청이 오거나 녹화 adb 가 끝날 때까지.
  func waitForStopOrEnd() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      // 확인과 저장을 한 lock 안에서 해야 깨우기가 저장보다 먼저 와도 놓치지 않는다.
      let ready = self.state.withLock { state in
        guard !state.stopRequested, !state.ended else { return true }
        state.waiter = continuation
        return false
      }
      if ready {
        continuation.resume()
      }
    }
  }

  /// 녹화 adb 가 `limit` 안에 끝나면 true.
  func waitForEnd(limit: Duration) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: limit)
    while !self.hasEnded {
      guard ContinuousClock.now < deadline else { return false }
      try? await Task.sleep(for: .milliseconds(20))
    }
    return true
  }

  private func wake(_ change: (inout State) -> Void) {
    let waiter = self.state.withLock { state in
      change(&state)
      defer { state.waiter = nil }
      return state.waiter
    }
    waiter?.resume()
  }
}

/// Workspace 가 예약한 파일에 쓰기·자르기. 만들지 않고(`O_CREAT` 없음) 링크를 따라가지 않으며(`O_NOFOLLOW`) 일반 파일에만 쓴다
/// (FIFO 에 막히지 않게 `O_NONBLOCK` 으로 열어 확인한다).
enum CaptureFile {
  typealias Writer = (Int32, UnsafeRawBufferPointer) -> Int

  /// 전부 쓰지 못하면 0바이트로 자르고 `.captureFileUnwritable`. `writer` 는 테스트가 쓰기 실패를 흉내 낸다.
  static func write(
    _ data: Data,
    to url: URL,
    writer: Writer = { Darwin.write($0, $1.baseAddress, $1.count) }
  ) throws(AndroidEmulatorError) {
    guard let descriptor = self.openRegularFile(url, flags: O_TRUNC) else {
      throw .captureFileUnwritable
    }
    defer { close(descriptor) }
    let complete = data.withUnsafeBytes { buffer in
      var offset = 0
      while offset < buffer.count {
        let written = writer(descriptor, UnsafeRawBufferPointer(rebasing: buffer[offset...]))
        if written > 0 {
          offset += written
        } else if written < 0, errno == EINTR {
          continue
        } else {
          return false
        }
      }
      return true
    }
    guard complete else {
      ftruncate(descriptor, 0)
      throw .captureFileUnwritable
    }
  }

  /// 일반 파일이면 0바이트로 자른다. 없거나 링크면 아무것도 하지 않는다.
  static func truncate(_ url: URL) {
    guard let descriptor = self.openRegularFile(url, flags: 0) else { return }
    ftruncate(descriptor, 0)
    close(descriptor)
  }

  /// 링크를 따라가지 않은 일반 파일의 크기. 아니면 0.
  static func size(_ url: URL) -> Int {
    var info = stat()
    guard lstat(FileFacts.path(url), &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return 0 }
    return Int(info.st_size)
  }

  private static func openRegularFile(_ url: URL, flags: Int32) -> Int32? {
    let descriptor = open(FileFacts.path(url), O_WRONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC | flags)
    guard descriptor >= 0 else { return nil }
    var info = stat()
    guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
      close(descriptor)
      return nil
    }
    return descriptor
  }
}
