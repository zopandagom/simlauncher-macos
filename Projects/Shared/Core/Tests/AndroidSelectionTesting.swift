import Foundation
import Testing
@testable import Core

/// `AndroidSDKSelection` 테스트가 함께 쓰는 패키지 목록과 계획 헬퍼.
protocol AndroidSelectionTesting {}

extension AndroidSelectionTesting {
  typealias Fixture = AndroidFixture

  static var platformTools: [AndroidRemotePackage] {
    [
      Fixture.tool("platform-tools", .v("37.0.1"), archives: [
        Fixture.archive("pt-37-linux.zip", hostOS: "linux"),
        Fixture.archive("pt-37-darwin.zip"),
      ]),
      Fixture.tool("platform-tools", .v("36.0.0"), archives: [Fixture.archive("pt-36-darwin.zip")]),
      Fixture.tool("platform-tools", .v("38.0.0"), channel: .canary, archives: [Fixture.archive("pt-38-darwin.zip")]),
    ]
  }

  static var emulators: [AndroidRemotePackage] {
    [
      Fixture.tool("emulator", .v("37.2.12"), archives: [
        Fixture.archive("emu-x64.zip", arch: "x64"),
        Fixture.archive("emu-aarch64.zip", arch: "aarch64"),
      ]),
      Fixture.tool("emulator", .v("37.3.5"), channel: .dev, archives: [
        Fixture.archive("emu-dev-x64.zip", arch: "x64"),
        Fixture.archive("emu-dev-aarch64.zip", arch: "aarch64"),
      ]),
    ]
  }

  static var images: [AndroidRemotePackage] {
    [
      Fixture.image(api: "37.0", revision: .v("8"), emulator: .v("37.2.11")),
      Fixture.image(
        api: "37.0",
        abi: "x86_64",
        revision: .v("8"),
        emulator: .v("37.2.11"),
        license: "android-sdk-license"
      ),
      Fixture.image(api: "36.1", revision: .v("3")),
      Fixture.image(api: "36", revision: .v("7")),
    ]
  }

  static func plan(
    tools: [AndroidRemotePackage] = Self.platformTools + Self.emulators,
    images: [AndroidRemotePackage] = Self.images,
    host: AndroidHostArchitecture = .aarch64,
    missing: Set<AndroidSDKComponent> = Set(AndroidSDKComponent.allCases),
    installedEmulator: AndroidRevision? = nil
  ) throws -> AndroidSDKInstallPlan {
    try Fixture.plan(tools: tools, images: images, host: host, missing: missing, installedEmulator: installedEmulator)
      .get()
  }

  static func problem(
    tools: [AndroidRemotePackage] = Self.platformTools + Self.emulators,
    images: [AndroidRemotePackage] = Self.images,
    toolLicenses: [AndroidLicense] = [Fixture.sdkLicense, Fixture.armLicense],
    imageLicenses: [AndroidLicense] = [Fixture.sdkLicense, Fixture.armLicense],
    host: AndroidHostArchitecture = .aarch64,
    missing: Set<AndroidSDKComponent> = Set(AndroidSDKComponent.allCases),
    installedEmulator: AndroidRevision? = nil
  ) -> AndroidSDKPlanProblem? {
    let result = Fixture.plan(
      tools: tools,
      images: images,
      toolLicenses: toolLicenses,
      imageLicenses: imageLicenses,
      host: host,
      missing: missing,
      installedEmulator: installedEmulator
    )
    guard case let .failure(problem) = result else {
      return nil
    }
    return problem
  }
}
