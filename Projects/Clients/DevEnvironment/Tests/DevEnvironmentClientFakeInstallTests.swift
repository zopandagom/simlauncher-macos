import Core
import DevEnvironmentInterface
import DevEnvironmentTesting
import Foundation
import Synchronization
import Testing

struct DevEnvironmentClientFakeInstallTests {
  private static let half = RuntimeInstallProgress(
    phase: .downloading,
    fractionCompleted: 0.5,
    completedBytes: 1_880_000_000,
    totalBytes: 3_760_000_000
  )

  @Test("기본: 기본 iOS 런타임은 sample, 설치는 .preparing 하나 뒤 installed, 호출을 기록한다")
  func defaults() async throws {
    let fake = DevEnvironmentClientFake()
    let received = Mutex<[RuntimeInstallProgress]>([])

    #expect(await fake.defaultIOSRuntime() == .sample)
    let outcome = try await fake.installDefaultIOSRuntime { progress in
      received.withLock { $0.append(progress) }
    }

    #expect(outcome == .installed)
    #expect(received.withLock { $0 } == [.preparing])
    #expect(fake.calls == [.defaultIOSRuntime, .installDefaultIOSRuntime])
    #expect(DefaultIOSRuntime.sample == DefaultIOSRuntime(version: OSVersion(major: 27, minor: 1), build: "24A94232"))
  }

  @Test("설정한 진행을 순서대로 알린 뒤 결과로 끝나고, 에러도 던진다")
  func script() async throws {
    let fake = DevEnvironmentClientFake()
    fake.setDefaultIOSRuntime(nil)
    fake.setInstallScript(progress: [.preparing, Self.half], result: .success(.alreadyInstalled))
    let received = Mutex<[RuntimeInstallProgress]>([])

    #expect(await fake.defaultIOSRuntime() == nil)
    let outcome = try await fake.installDefaultIOSRuntime { progress in
      received.withLock { $0.append(progress) }
    }
    #expect(outcome == .alreadyInstalled)
    #expect(received.withLock { $0 } == [.preparing, Self.half])

    fake.setInstallScript(progress: [], result: .failure(.failed))
    await #expect(throws: RuntimeInstallError.failed) {
      try await fake.installDefaultIOSRuntime { _ in }
    }
  }

  @Test("suspendInstalls 동안 진행을 모두 알린 뒤 기다리고, resumeInstalls 뒤 그때의 결과로 끝난다")
  func suspendAndResume() async throws {
    let fake = DevEnvironmentClientFake()
    fake.setInstallScript(progress: [.preparing, Self.half], result: .success(.installed))
    fake.suspendInstalls()
    let received = Mutex<[RuntimeInstallProgress]>([])

    let install = Task {
      try await fake.installDefaultIOSRuntime { progress in
        received.withLock { $0.append(progress) }
      }
    }
    await waitUntil { received.withLock { $0.count } == 2 }
    fake.setInstallScript(progress: [], result: .failure(.launchFailed))

    fake.resumeInstalls()

    await #expect(throws: RuntimeInstallError.launchFailed) { try await install.value }
    // 재개한 뒤의 호출은 기다리지 않는다.
    fake.setInstallScript(progress: [], result: .success(.installed))
    #expect(try await fake.installDefaultIOSRuntime { _ in } == .installed)
  }

  @Test("멈춘 동안 결과를 xcodeNotFound 로 바꿔도 부를 때의 결과로 끝난다 (알림 뒤 xcodeNotFound 는 Impl 에서 나오지 않는다)")
  func xcodeNotFoundAfterProgressIsIgnored() async throws {
    let fake = DevEnvironmentClientFake()
    fake.setInstallScript(progress: [.preparing, Self.half], result: .success(.installed))
    fake.suspendInstalls()
    let received = Mutex<[RuntimeInstallProgress]>([])

    let install = Task {
      try await fake.installDefaultIOSRuntime { progress in
        received.withLock { $0.append(progress) }
      }
    }
    await waitUntil { received.withLock { $0.count } == 2 }
    fake.setInstallScript(progress: [], result: .failure(.xcodeNotFound))

    fake.resumeInstalls()

    #expect(try await install.value == .installed)
    #expect(received.withLock { $0 } == [.preparing, Self.half])
  }

  @Test("멈춘 동안 Task 를 취소하면 cancelled")
  func cancelWhileSuspended() async throws {
    let fake = DevEnvironmentClientFake()
    fake.suspendInstalls()
    let received = Mutex(0)

    let install = Task {
      try await fake.installDefaultIOSRuntime { _ in
        received.withLock { $0 += 1 }
      }
    }
    await waitUntil { received.withLock { $0 } == 1 }

    install.cancel()

    await #expect(throws: RuntimeInstallError.cancelled) { try await install.value }
    #expect(fake.calls == [.installDefaultIOSRuntime])
  }

  @Test("이미 취소된 Task 에서는 진행을 알리지 않고 cancelled (호출은 기록한다)")
  func alreadyCancelled() async throws {
    let fake = DevEnvironmentClientFake()
    let received = Mutex(0)

    let install = Task {
      while !Task.isCancelled {
        await Task.yield()
      }
      return try await fake.installDefaultIOSRuntime { _ in
        received.withLock { $0 += 1 }
      }
    }
    install.cancel()

    await #expect(throws: RuntimeInstallError.cancelled) { try await install.value }
    #expect(received.withLock { $0 } == 0)
    #expect(fake.calls == [.installDefaultIOSRuntime])
  }

  @Test("진행 알림 사이에 취소되면 다음 알림 없이 cancelled (성공 결과를 돌려주지 않는다)")
  func cancelledBetweenProgress() async throws {
    let fake = DevEnvironmentClientFake()
    fake.setInstallScript(progress: [.preparing, Self.half], result: .success(.installed))
    let received = Mutex<[RuntimeInstallProgress]>([])

    let install = Task {
      try await fake.installDefaultIOSRuntime { progress in
        received.withLock { $0.append(progress) }
        // 첫 알림을 처리하는 동안 자기 Task 를 취소한다.
        withUnsafeCurrentTask { $0?.cancel() }
      }
    }

    await #expect(throws: RuntimeInstallError.cancelled) { try await install.value }
    #expect(received.withLock { $0 } == [.preparing])
  }

  @Test("마지막 알림 뒤 결과 전에 취소되면 cancelled")
  func cancelledAfterLastProgress() async throws {
    let fake = DevEnvironmentClientFake()
    fake.setInstallScript(progress: [.preparing], result: .success(.alreadyInstalled))

    let install = Task {
      try await fake.installDefaultIOSRuntime { _ in
        withUnsafeCurrentTask { $0?.cancel() }
      }
    }

    await #expect(throws: RuntimeInstallError.cancelled) { try await install.value }
  }

  @Test("결과가 xcodeNotFound 면 진행을 알리지 않고 바로 던진다 (Impl 처럼 실행 전에 실패)")
  func xcodeNotFoundWithoutProgress() async {
    let fake = DevEnvironmentClientFake()
    fake.setInstallScript(progress: [.preparing, Self.half], result: .failure(.xcodeNotFound))
    let received = Mutex(0)

    await #expect(throws: RuntimeInstallError.xcodeNotFound) {
      try await fake.installDefaultIOSRuntime { _ in
        received.withLock { $0 += 1 }
      }
    }
    #expect(received.withLock { $0 } == 0)
    #expect(fake.calls == [.installDefaultIOSRuntime])
  }

  @Test("이미 취소된 Task 에서도 결과가 xcodeNotFound 면 cancelled 가 아니라 xcodeNotFound (Impl 처럼 Xcode 확인이 먼저)")
  func xcodeNotFoundBeforeCancellation() async {
    let fake = DevEnvironmentClientFake()
    fake.setInstallScript(progress: [.preparing], result: .failure(.xcodeNotFound))

    let install = Task {
      while !Task.isCancelled {
        await Task.yield()
      }
      return try await fake.installDefaultIOSRuntime { _ in }
    }
    install.cancel()

    await #expect(throws: RuntimeInstallError.xcodeNotFound) { try await install.value }
  }

  @Test("setDelay 를 줘도 진행과 결과는 같다")
  func delayed() async throws {
    let fake = DevEnvironmentClientFake()
    fake.setDelay(.milliseconds(1))
    fake.setInstallScript(progress: [.preparing, Self.half], result: .success(.installed))
    let received = Mutex<[RuntimeInstallProgress]>([])

    let outcome = try await fake.installDefaultIOSRuntime { progress in
      received.withLock { $0.append(progress) }
    }

    #expect(outcome == .installed)
    #expect(received.withLock { $0 } == [.preparing, Self.half])
  }
}

/// 조건이 참이 될 때까지 차례를 넘긴다. 10초 안에 참이 되지 않으면 실패를 기록하고 돌아온다.
private func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
  let deadline = ContinuousClock.now + .seconds(10)
  while !condition() {
    guard ContinuousClock.now < deadline else {
      Issue.record("10초 안에 조건이 참이 되지 않았다", sourceLocation: sourceLocation)
      return
    }
    await Task.yield()
  }
}
