import Core
import Foundation
import Testing

/// 조건이 참이 될 때까지 10ms 마다 본다. 10초가 넘으면 실패로 기록하고 던진다.
func waitUntil(_ condition: () -> Bool) async throws {
  let deadline = ContinuousClock.now + .seconds(10)
  while !condition() {
    guard ContinuousClock.now < deadline else {
      Issue.record("10초 안에 조건이 참이 되지 않았다")
      throw CancellationError()
    }
    try await Task.sleep(for: .milliseconds(10))
  }
}

/// 테스트 안에서 버전을 만든다.
func version(_ raw: String) throws -> AppVersion {
  try #require(AppVersion(raw))
}

/// 릴리스 워크플로가 올리는 버전 파일과 같은 바이트(1.2.0 에 올린 파일, 2026-11-15): `{"version":"<값>"}` + 줄바꿈.
func versionFileJSON(_ version: String) -> Data {
  Data("{\"version\":\"\(version)\"}\n".utf8)
}
