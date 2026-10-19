import Foundation
import Synchronization
import Testing
@testable import SimulatorImpl

enum Fixture {
  static func data(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
  }
}

/// 실행 요청을 기록하고, 받은 처리기로 결과를 정한다.
final class StubCommandRunner: CommandRunner {
  struct Invocation: Hashable, Sendable {
    let executable: URL
    let arguments: [String]
    let environment: [String: String]
  }

  struct LaunchError: Error {}

  private let handler: @Sendable (Invocation) throws -> CommandResult
  private let recorded = Mutex<[Invocation]>([])

  init(handler: @escaping @Sendable (Invocation) throws -> CommandResult) {
    self.handler = handler
  }

  var invocations: [Invocation] {
    self.recorded.withLock { $0 }
  }

  func run(_ executable: URL, _ arguments: [String], environment: [String: String]) async throws -> CommandResult {
    let invocation = Invocation(executable: executable, arguments: arguments, environment: environment)
    self.recorded.withLock { $0.append(invocation) }
    return try self.handler(invocation)
  }
}

/// provider 가 몇 번 불렸는지 센다.
final class ProviderCounter: Sendable {
  private let count = Mutex(0)
  private let url: URL?

  init(returning url: URL?) {
    self.url = url
  }

  var calls: Int {
    self.count.withLock { $0 }
  }

  func provide() -> URL? {
    self.count.withLock { $0 += 1 }
    return self.url
  }
}

extension CommandResult {
  static func success(_ stdout: Data = Data()) -> CommandResult {
    CommandResult(exitCode: 0, stdout: stdout, stderr: Data())
  }

  static func failure(_ exitCode: Int32, _ stderr: String) -> CommandResult {
    CommandResult(exitCode: exitCode, stdout: Data(), stderr: Data(stderr.utf8))
  }
}
