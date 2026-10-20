import Foundation
import Testing
@testable import Core

struct DevEnvironmentStatusTests {
  private static let xcode = XcodeInstallation(
    bundleURL: URL(filePath: "/Applications/Xcode.app", directoryHint: .isDirectory),
    version: OSVersion(major: 27, minor: 1)
  )

  private static let allChecks: [XcodeSetupChecks] = [
    .notRun,
    XcodeSetupChecks(licenseAccepted: true, firstLaunchComplete: false),
    XcodeSetupChecks(licenseAccepted: false, firstLaunchComplete: true),
    XcodeSetupChecks(licenseAccepted: true, firstLaunchComplete: true),
  ]

  @Test("Xcode 가 없고 Command Line Tools 가 선택돼 있으면 commandLineToolsOnly (확인 결과는 보지 않는다)", arguments: allChecks)
  func commandLineToolsOnly(checks: XcodeSetupChecks) {
    let status = DevEnvironmentStatus(xcode: nil, commandLineToolsSelected: true, checks: checks)
    #expect(status == .commandLineToolsOnly)
  }

  @Test("Xcode 가 없고 Command Line Tools 도 아니면 xcodeNotInstalled (확인 결과는 보지 않는다)", arguments: allChecks)
  func xcodeNotInstalled(checks: XcodeSetupChecks) {
    let status = DevEnvironmentStatus(xcode: nil, commandLineToolsSelected: false, checks: checks)
    #expect(status == .xcodeNotInstalled)
  }

  @Test("라이선스에 동의하지 않았으면 첫 실행 준비 결과와 상관없이 licenseNotAccepted", arguments: [false, true])
  func licenseNotAccepted(firstLaunchComplete: Bool) {
    let checks = XcodeSetupChecks(licenseAccepted: false, firstLaunchComplete: firstLaunchComplete)
    let status = DevEnvironmentStatus(xcode: Self.xcode, commandLineToolsSelected: false, checks: checks)
    #expect(status == .licenseNotAccepted(Self.xcode))
  }

  @Test("라이선스는 동의했고 첫 실행 준비가 남았으면 firstLaunchRequired")
  func firstLaunchRequired() {
    let checks = XcodeSetupChecks(licenseAccepted: true, firstLaunchComplete: false)
    let status = DevEnvironmentStatus(xcode: Self.xcode, commandLineToolsSelected: false, checks: checks)
    #expect(status == .firstLaunchRequired(Self.xcode))
  }

  @Test("둘 다 끝났으면 ready (Command Line Tools 선택 여부와 상관없다)", arguments: [false, true])
  func ready(commandLineToolsSelected: Bool) {
    let checks = XcodeSetupChecks(licenseAccepted: true, firstLaunchComplete: true)
    let status = DevEnvironmentStatus(
      xcode: Self.xcode,
      commandLineToolsSelected: commandLineToolsSelected,
      checks: checks
    )
    #expect(status == .ready(Self.xcode))
  }

  @Test(
    "xcode 는 상태가 가리키는 Xcode, isReady 는 ready 일 때만",
    arguments: [
      (DevEnvironmentStatus.xcodeNotInstalled, false, false),
      (.commandLineToolsOnly, false, false),
      (.licenseNotAccepted(xcode), true, false),
      (.firstLaunchRequired(xcode), true, false),
      (.ready(xcode), true, true),
    ]
  )
  func accessors(status: DevEnvironmentStatus, hasXcode: Bool, isReady: Bool) {
    #expect(status.xcode == (hasXcode ? Self.xcode : nil))
    #expect(status.isReady == isReady)
  }

  @Test("notRun 은 두 확인 모두 false")
  func notRun() {
    #expect(XcodeSetupChecks.notRun == XcodeSetupChecks(licenseAccepted: false, firstLaunchComplete: false))
  }
}
