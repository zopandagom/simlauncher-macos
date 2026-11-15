import Core
import Foundation
import Testing
import UpdateCheckInterface
import UpdateCheckTesting

/// 멈춘 호출을 들고 있는 상자. 결과는 끝날 때 채운다.
private final class CheckTask: Sendable {
  private let task: Task<Result<AppVersion?, UpdateCheckError>, Never>

  init(fake: UpdateCheckClientFake) {
    self.task = Task {
      do throws(UpdateCheckError) {
        return try await .success(fake.latestReleaseVersion())
      } catch {
        return .failure(error)
      }
    }
  }

  func cancel() {
    self.task.cancel()
  }

  var value: Result<AppVersion?, UpdateCheckError> {
    get async {
      await self.task.value
    }
  }
}

struct UpdateCheckClientFakeTests {
  @Test("기본 결과는 success(nil), 기본 주소가 있고, 호출 수를 센다")
  func defaults() async throws {
    let fake = UpdateCheckClientFake()
    #expect(try await fake.latestReleaseVersion() == nil)
    #expect(fake.releasePageURL?.absoluteString == "https://github.com/example/app/releases/latest")
    #expect(fake.callCount == 1)
  }

  @Test("setResult 는 이후 호출의 결과를 바꾼다")
  func setsResult() async throws {
    let fake = UpdateCheckClientFake()
    try fake.setResult(.success(version("1.3.0")))
    #expect(try await fake.latestReleaseVersion() == version("1.3.0"))

    fake.setResult(.failure(.refused))
    await #expect(throws: UpdateCheckError.refused) { try await fake.latestReleaseVersion() }
    #expect(fake.callCount == 2)
  }

  @Test("멈춘 호출은 resume 까지 기다리고, 재개될 때의 결과를 받는다")
  func suspendAndResume() async throws {
    let fake = UpdateCheckClientFake()
    fake.suspend()
    let first = CheckTask(fake: fake)
    let second = CheckTask(fake: fake)

    try await waitUntil { fake.suspendedCallCount == 2 }
    #expect(fake.callCount == 2)
    try fake.setResult(.success(version("1.4.0")))
    fake.resume()

    #expect(try await first.value == .success(version("1.4.0")))
    #expect(try await second.value == .success(version("1.4.0")))
    #expect(fake.suspendedCallCount == 0)

    // 재개 뒤 호출은 멈추지 않는다.
    #expect(try await fake.latestReleaseVersion() == version("1.4.0"))
  }

  @Test("멈춘 동안 Task 가 취소되면 cancelled")
  func cancelWhileSuspended() async throws {
    let fake = UpdateCheckClientFake()
    fake.suspend()
    let task = CheckTask(fake: fake)

    try await waitUntil { fake.suspendedCallCount == 1 }
    task.cancel()

    #expect(await task.value == .failure(.cancelled))
    #expect(fake.suspendedCallCount == 0)
  }

  @Test("releasePageURL 이 nil 이면 멈춤과 관계없이 notConfigured, 호출 수는 센다")
  func notConfigured() async {
    let fake = UpdateCheckClientFake(releasePageURL: nil, result: .success(nil))
    fake.suspend()

    await #expect(throws: UpdateCheckError.notConfigured) { try await fake.latestReleaseVersion() }
    #expect(fake.callCount == 1)
    #expect(fake.suspendedCallCount == 0)
  }
}
