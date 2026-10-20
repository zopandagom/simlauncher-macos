import CommandInterface
import Foundation
import Synchronization
import Testing
@testable import CommandImpl

/// `runCancellable` 테스트가 함께 쓰는 실행: 실제 `/bin/sh` 를 단계 간격을 줄인 Impl 로 실행한다.
enum Shell {
  static let shell = URL(filePath: "/bin/sh")

  /// 단계 간격을 줄인 Impl. 손자 프로세스가 파이프를 쥐는 테스트가 오래 걸리지 않게 eofGrace 도 줄인다.
  static func client(
    interruptGrace: Duration = .seconds(5),
    terminateGrace: Duration = .seconds(5),
    eofGrace: Duration = .milliseconds(300)
  ) -> CommandClientImpl {
    CommandClientImpl(interruptGrace: interruptGrace, terminateGrace: terminateGrace, eofGrace: eofGrace)
  }

  static func run(
    _ client: CommandClientImpl,
    _ script: String,
    timeout: Duration? = nil,
    log: OutputLog = OutputLog()
  ) async throws(CommandError) -> CommandResult {
    try await client.runCancellable(self.shell, ["-c", script], environment: [:], timeout: timeout) { output in
      log.append(output)
    }
  }
}

/// 받은 출력 조각 기록.
final class OutputLog: Sendable {
  private let recorded = Mutex<[CommandOutput]>([])

  var chunks: [CommandOutput] {
    self.recorded.withLock { $0 }
  }

  var stdout: Data {
    var data = Data()
    for case let .stdout(chunk) in self.chunks {
      data.append(chunk)
    }
    return data
  }

  var stderr: Data {
    var data = Data()
    for case let .stderr(chunk) in self.chunks {
      data.append(chunk)
    }
    return data
  }

  func append(_ output: CommandOutput) {
    self.recorded.withLock { $0.append(output) }
  }
}

/// 스크립트가 pid·표시를 남기는 임시 폴더. `remove()` 는 남은 손자 프로세스(`child`)도 끝낸다.
struct Scratch {
  let url: URL

  init() throws {
    self.url = FileManager.default.temporaryDirectory
      .appending(path: "CommandTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: self.url, withIntermediateDirectories: true)
  }

  var pid: URL {
    self.url.appending(path: "pid")
  }

  var child: URL {
    self.url.appending(path: "child")
  }

  var mark: URL {
    self.url.appending(path: "mark")
  }

  /// 셸 스크립트에 넣을 작은따옴표 경로.
  func quoted(_ file: URL) -> String {
    "'\(file.path(percentEncoded: false))'"
  }

  var markText: String? {
    Self.text(self.mark)
  }

  func remove() {
    Self.kill(Self.number(self.child))
    try? FileManager.default.removeItem(at: self.url)
  }

  /// 스크립트가 `pid` 파일에 자기 pid 를 쓸 때까지 기다린다.
  func waitForPID() async throws -> Int32 {
    try await Self.waitUntil { Self.number(self.pid) != nil }
    return try #require(Self.number(self.pid))
  }

  static func text(_ file: URL) -> String? {
    guard let data = try? Data(contentsOf: file), let text = String(bytes: data, encoding: .utf8) else {
      return nil
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func number(_ file: URL) -> Int32? {
    self.text(file).flatMap { Int32($0) }
  }

  static func isAlive(_ pid: Int32) -> Bool {
    Darwin.kill(pid, 0) == 0
  }

  static func kill(_ pid: Int32?) {
    if let pid {
      _ = Darwin.kill(pid, SIGKILL)
    }
  }

  /// 조건이 참이 될 때까지 10ms 마다 본다. 10초가 지나면 실패.
  static func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(10)
    while !condition() {
      guard ContinuousClock.now < deadline else {
        Issue.record("10초 안에 조건이 참이 되지 않았다")
        throw CancellationError()
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  /// Task 취소로 끊기지 않는 대기 (느린 onOutput 흉내).
  static func uncancellableSleep(_ duration: Duration) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      DispatchQueue.global().asyncAfter(deadline: .now() + ProcessControl.dispatchInterval(duration)) {
        continuation.resume()
      }
    }
  }
}
