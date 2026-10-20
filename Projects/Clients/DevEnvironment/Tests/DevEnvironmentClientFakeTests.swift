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

  @Test("샘플 Xcode 의 경로와 버전")
  func samples() {
    #expect(XcodeInstallation.sample.bundleURL.path(percentEncoded: false) == "/Applications/Xcode.app/")
    #expect(XcodeInstallation.sample.version == OSVersion(major: 27, minor: 1))
    #expect(XcodeInstallation.beta.bundleURL.lastPathComponent == "Xcode-beta.app")
    #expect(XcodeInstallation.beta.version == OSVersion(major: 27, minor: 2))
  }
}
