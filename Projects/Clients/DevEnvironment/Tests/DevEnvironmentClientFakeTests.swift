import Core
import DevEnvironmentInterface
import DevEnvironmentTesting
import Foundation
import Testing

struct DevEnvironmentClientFakeTests {
  @Test("기본은 .ready(.sample) 이고 호출을 기록한다")
  func defaults() async throws {
    let fake = DevEnvironmentClientFake()

    #expect(try await fake.checkEnvironment() == .ready(.sample))
    #expect(await fake.selectedXcode() == .sample)
    try await fake.openXcode()
    try await fake.openXcodeInAppStore()

    #expect(fake.calls == [.checkEnvironment, .selectedXcode, .openXcode, .openXcodeInAppStore])
  }

  @Test("selectedXcode 는 설정한 상태의 Xcode 다")
  func selectedFollowsStatus() async {
    let fake = DevEnvironmentClientFake(status: .licenseNotAccepted(.beta))
    #expect(await fake.selectedXcode() == .beta)

    fake.setStatus(.commandLineToolsOnly)
    #expect(await fake.selectedXcode() == nil)
  }

  @Test(
    "Xcode 가 없는 상태의 openXcode 는 xcodeNotFound",
    arguments: [DevEnvironmentStatus.xcodeNotInstalled, .commandLineToolsOnly]
  )
  func openWithoutXcode(status: DevEnvironmentStatus) async {
    let fake = DevEnvironmentClientFake(status: status)
    await #expect(throws: DevEnvironmentError.xcodeNotFound) { try await fake.openXcode() }
    #expect(fake.calls == [.openXcode])
  }

  @Test("설정한 에러를 던지고, nil 로 되돌리면 다시 성공한다")
  func errors() async throws {
    let fake = DevEnvironmentClientFake(status: .xcodeNotInstalled)
    fake.setCheckError(.checkFailed)
    fake.setOpenXcodeError(.openFailed)
    fake.setOpenAppStoreError(.openFailed)

    await #expect(throws: DevEnvironmentError.checkFailed) { try await fake.checkEnvironment() }
    await #expect(throws: DevEnvironmentError.openFailed) { try await fake.openXcode() }
    await #expect(throws: DevEnvironmentError.openFailed) { try await fake.openXcodeInAppStore() }

    fake.setCheckError(nil)
    fake.setOpenXcodeError(nil)
    fake.setOpenAppStoreError(nil)
    fake.setStatus(.firstLaunchRequired(.sample))

    #expect(try await fake.checkEnvironment() == .firstLaunchRequired(.sample))
    try await fake.openXcode()
    try await fake.openXcodeInAppStore()
  }

  @Test("suspendChecks 동안 checkEnvironment 는 기록된 뒤 기다리고, resumeChecks 뒤 그때의 상태로 끝난다")
  func suspendedCheck() async throws {
    let fake = DevEnvironmentClientFake(status: .xcodeNotInstalled)
    fake.suspendChecks()
    let check = Task { try await fake.checkEnvironment() }
    await waitUntil { fake.calls == [.checkEnvironment] }
    fake.setStatus(.ready(.sample))

    fake.resumeChecks()

    #expect(try await check.value == .ready(.sample))
    // 재개한 뒤의 호출은 기다리지 않는다.
    #expect(try await fake.checkEnvironment() == .ready(.sample))
    #expect(fake.calls == [.checkEnvironment, .checkEnvironment])
  }

  @Test("suspendOpens 동안 두 열기가 모두 기다리고, resumeOpens 로 함께 끝난다")
  func suspendedOpens() async throws {
    let fake = DevEnvironmentClientFake()
    fake.suspendOpens()
    let openXcode = Task { try await fake.openXcode() }
    let openAppStore = Task { try await fake.openXcodeInAppStore() }
    await waitUntil { fake.calls.count == 2 }
    #expect(Set(fake.calls) == [.openXcode, .openXcodeInAppStore])

    fake.resumeOpens()

    try await openXcode.value
    try await openAppStore.value
  }

  @Test("setDelay 를 줘도 호출은 기록되고 결과는 지연이 없을 때와 같다")
  func delayedCheck() async throws {
    let fake = DevEnvironmentClientFake(status: .firstLaunchRequired(.sample))
    fake.setDelay(.milliseconds(1))

    #expect(try await fake.checkEnvironment() == .firstLaunchRequired(.sample))
    try await fake.openXcode()
    try await fake.openXcodeInAppStore()
    #expect(fake.calls == [.checkEnvironment, .openXcode, .openXcodeInAppStore])
  }

  @Test(
    "이미 취소된 Task 의 checkEnvironment: Xcode 가 있으면 checkFailed, 설정한 에러가 있으면 그 에러",
    arguments: [nil, DevEnvironmentError.openFailed]
  )
  func cancelledCheck(configured: DevEnvironmentError?) async {
    let fake = DevEnvironmentClientFake()
    fake.setCheckError(configured)

    let result = await Self.checkInCancelledTask(fake)

    #expect(result == .failure(configured ?? .checkFailed))
    #expect(fake.calls == [.checkEnvironment])
  }

  @Test(
    "이미 취소된 Task 라도 Xcode 가 없는 상태면 그 상태를 돌려준다 (Impl 도 확인 명령을 실행하지 않는다)",
    arguments: [DevEnvironmentStatus.xcodeNotInstalled, .commandLineToolsOnly]
  )
  func cancelledCheckWithoutXcode(status: DevEnvironmentStatus) async {
    let fake = DevEnvironmentClientFake(status: status)

    let result = await Self.checkInCancelledTask(fake)

    #expect(result == .success(status))
  }

  /// 시작 전에 취소된 Task 에서 `checkEnvironment()` 를 부른다.
  private static func checkInCancelledTask(
    _ fake: DevEnvironmentClientFake
  ) async -> Result<DevEnvironmentStatus, DevEnvironmentError> {
    let check = Task { () async -> Result<DevEnvironmentStatus, DevEnvironmentError> in
      while !Task.isCancelled {
        await Task.yield()
      }
      do throws(DevEnvironmentError) {
        return try await .success(fake.checkEnvironment())
      } catch {
        return .failure(error)
      }
    }
    check.cancel()
    return await check.value
  }

  @Test("샘플 Xcode 의 경로와 버전")
  func samples() {
    #expect(XcodeInstallation.sample.bundleURL.path(percentEncoded: false) == "/Applications/Xcode.app/")
    #expect(XcodeInstallation.sample.version == OSVersion(major: 27, minor: 1))
    #expect(XcodeInstallation.beta.bundleURL.lastPathComponent == "Xcode-beta.app")
    #expect(XcodeInstallation.beta.version == OSVersion(major: 27, minor: 2))
  }
}

/// 조건이 참이 될 때까지 다른 작업에 차례를 넘긴다. 10초 안에 참이 되지 않으면 실패를 기록하고 돌아온다
/// (회귀가 있어도 테스트가 멈추지 않게).
private func waitUntil(
  _ condition: () -> Bool,
  sourceLocation: SourceLocation = #_sourceLocation
) async {
  let deadline = ContinuousClock.now + .seconds(10)
  while !condition() {
    guard ContinuousClock.now < deadline else {
      Issue.record("10초 안에 조건이 참이 되지 않았다", sourceLocation: sourceLocation)
      return
    }
    await Task.yield()
  }
}
