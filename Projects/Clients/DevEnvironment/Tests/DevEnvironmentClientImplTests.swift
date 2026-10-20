import CommandInterface
import CommandTesting
import Core
import DevEnvironmentInterface
import Foundation
import Testing
@testable import DevEnvironmentImpl

struct DevEnvironmentClientImplTests {
  private static func client(
    _ command: CommandClientFake,
    _ tmp: TemporaryDirectory,
    applications: URL? = nil,
    environment: [String: String] = ["PATH": "/usr/bin"]
  ) -> DevEnvironmentClientImpl {
    DevEnvironmentClientImpl(
      command: command,
      applicationsDirectory: applications ?? tmp.applications,
      baseEnvironment: environment
    )
  }

  // MARK: - 고르기

  @Test("앱 폴더에 Xcode 가 없고 xcode-select 가 CLT 면 commandLineToolsOnly, 실행은 xcode-select 한 번뿐")
  func commandLineToolsOnly() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let command = Responder.command(select: Responder.commandLineTools)

    let status = try await Self.client(command, tmp).checkEnvironment()

    #expect(status == .commandLineToolsOnly)
    #expect(command.executables == ["xcode-select"])
    #expect(command.invocations.first?.arguments == ["-p"])
  }

  @Test("Xcode 가 없고 xcode-select 가 실패하면 xcodeNotInstalled, 실행은 xcode-select 한 번뿐")
  func xcodeNotInstalled() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let command = Responder.command(select: .exit(2))

    let status = try await Self.client(command, tmp).checkEnvironment()

    #expect(status == .xcodeNotInstalled)
    #expect(command.executables == ["xcode-select"])
  }

  @Test("xcode-select 를 시작하지 못해도 앱 폴더의 Xcode 를 고른다")
  func selectLaunchFailed() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let bundle = try tmp.makeXcode()
    let command = Responder.command(select: .launchFailed)

    #expect(try await Self.client(command, tmp).selectedXcode() == tmp.installation(bundle, 27, 1))
  }

  @Test("xcode-select 가 앱 폴더 밖 Xcode 를 가리키면 앱 폴더에 더 높은 버전이 있어도 그것")
  func selectedOutsideApplications() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let outside = try tmp.makeXcode("Xcode-26.app", in: tmp.elsewhere, version: "26.0")
    try tmp.makeXcode("Xcode-beta.app", version: "27.2")
    let command = Responder.command(select: Responder.selecting(outside.appending(path: "Contents/Developer")))

    #expect(try await Self.client(command, tmp).selectedXcode() == tmp.installation(outside, 26))
  }

  @Test("xcode-select 가 CLT 면 앱 폴더의 가장 높은 버전, xcodebuild 는 그 번들 안에서 그 DEVELOPER_DIR 로")
  func commandLineToolsWithInstalledXcodes() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    try tmp.makeXcode("Xcode.app", version: "27.1")
    let beta = try tmp.makeXcode("Xcode-beta.app", version: "27.2", format: .binary)
    let command = Responder.command(select: Responder.commandLineTools)
    let expected = try tmp.installation(beta, 27, 2)

    let status = try await Self.client(command, tmp).checkEnvironment()

    #expect(status == .ready(expected))
    let xcodebuild = try #require(command.invocations.last)
    #expect(xcodebuild.executable == XcodeCommand.xcodebuild(in: expected))
    #expect(xcodebuild.executable.path(percentEncoded: false).hasPrefix(expected.bundleURL.path(percentEncoded: false)))
    #expect(xcodebuild.environment["DEVELOPER_DIR"] == expected.developerDirectory.path(percentEncoded: false))
  }

  @Test("물려받은 DEVELOPER_DIR 는 xcode-select·open 실행 환경에서 지운다")
  func clearsInheritedDeveloperDirectory() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    try tmp.makeXcode()
    let command = Responder.command(select: Responder.commandLineTools)
    let client = Self.client(command, tmp, environment: ["PATH": "/usr/bin", "DEVELOPER_DIR": "/nonexistent"])

    try await client.openXcode()

    #expect(command.executables == ["xcode-select", "open"])
    for invocation in command.invocations {
      #expect(invocation.environment == ["PATH": "/usr/bin"])
    }
  }

  @Test(
    "식별자가 다른 .app, Info.plist 없는 .app, xcodebuild 없는 Xcode 는 고르지 않는다",
    arguments: [
      Broken.otherIdentifier, .noInfoPlist, .noXcodebuild, .badVersion,
    ]
  )
  func skipsBrokenBundles(broken: Broken) async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    try broken.make(tmp, "Xcode-broken.app", in: tmp.applications)
    let command = Responder.command(select: .exit(2))

    #expect(try await Self.client(command, tmp).checkEnvironment() == .xcodeNotInstalled)
    #expect(command.executables == ["xcode-select"])
  }

  @Test(
    "xcode-select 가 가리키는 번들이 깨졌으면 앱 폴더의 Xcode 를 고른다",
    arguments: [Broken.otherIdentifier, .noInfoPlist, .noXcodebuild, .badVersion]
  )
  func brokenSelectedFallsBack(broken: Broken) async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let selected = try broken.make(tmp, "Xcode.app", in: tmp.elsewhere)
    let installed = try tmp.makeXcode("Xcode-26.app", version: "26.0")
    let command = Responder.command(select: Responder.selecting(selected.appending(path: "Contents/Developer")))

    #expect(try await Self.client(command, tmp).selectedXcode() == tmp.installation(installed, 26))
  }

  @Test(
    "xcode-select 가 가리키는 번들이 깨지고 앱 폴더에도 없으면 xcodeNotInstalled (CLT 아님), xcodebuild 실행 없음",
    arguments: [Broken.otherIdentifier, .noInfoPlist, .noXcodebuild, .badVersion]
  )
  func brokenSelectedWithoutInstalled(broken: Broken) async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let selected = try broken.make(tmp, "Xcode.app", in: tmp.elsewhere)
    let command = Responder.command(select: Responder.selecting(selected.appending(path: "Contents/Developer")))

    #expect(try await Self.client(command, tmp).checkEnvironment() == .xcodeNotInstalled)
    #expect(command.executables == ["xcode-select"])
  }

  @Test("앱 폴더의 링크 Xcode.app → Xcode-27.1.app 은 하나로 합쳐지고 bundleURL 은 실제 경로")
  func symlinkedBundleIsMerged() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let real = try tmp.makeXcode("Xcode-27.1.app", version: "27.1")
    let link = try tmp.link("Xcode.app", to: real)
    let command = Responder.command(select: .exit(2))
    let client = Self.client(command, tmp)

    let chosen = try #require(await client.selectedXcode())

    #expect(try chosen == tmp.installation(real, 27, 1))
    #expect(chosen.bundleURL.lastPathComponent == "Xcode-27.1.app")
    #expect(DevEnvironmentClientImpl.canonicalBundleURL(link) == chosen.bundleURL)
  }

  @Test("xcode-select 의 Xcode 가 유효하면 앱 폴더를 보지 않는다 (앱 폴더가 없어도 그것, 실행은 xcode-select 한 번)")
  func validSelectedSkipsApplications() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let selected = try tmp.makeXcode("Xcode.app", in: tmp.elsewhere, version: "26.0")
    let missing = tmp.url.appending(path: "NoSuchFolder", directoryHint: .isDirectory)
    let expected = try tmp.installation(selected, 26)

    let selectCommand = Responder.command(select: Responder.selecting(selected.appending(path: "Contents/Developer")))
    #expect(await Self.client(selectCommand, tmp, applications: missing).selectedXcode() == expected)
    #expect(selectCommand.executables == ["xcode-select"])

    let checkCommand = Responder.command(select: Responder.selecting(selected.appending(path: "Contents/Developer")))
    #expect(try await Self.client(checkCommand, tmp, applications: missing).checkEnvironment() == .ready(expected))
    #expect(checkCommand.executables == ["xcode-select", "xcodebuild"])
  }

  @Test("selectedXcode 는 xcodebuild 를 실행하지 않는다")
  func selectedXcodeRunsOnlyXcodeSelect() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    try tmp.makeXcode()
    let command = Responder.command(select: Responder.commandLineTools)

    #expect(await Self.client(command, tmp).selectedXcode() != nil)
    #expect(command.executables == ["xcode-select"])
  }

  // MARK: - 준비 상태

  @Test("-checkFirstLaunchStatus 가 0 이면 ready, -license check 는 실행하지 않는다")
  func readyWithoutLicenseCheck() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let bundle = try tmp.makeXcode()
    let command = Responder.command(select: Responder.selecting(bundle.appending(path: "Contents/Developer")))

    #expect(try await Self.client(command, tmp).checkEnvironment() == .ready(tmp.installation(bundle, 27, 1)))
    #expect(command.invocations.map(\.arguments) == [["-p"], ["-checkFirstLaunchStatus"]])
  }

  @Test(
    "-checkFirstLaunchStatus 가 0 이 아니면 -license check 로 나눈다",
    arguments: [(Int32(0), false), (69, true), (64, true)]
  )
  func licenseOrFirstLaunch(licenseExit: Int32, licenseRequired: Bool) async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let bundle = try tmp.makeXcode()
    let command = Responder.command(
      select: Responder.selecting(bundle.appending(path: "Contents/Developer")),
      firstLaunch: .exit(69),
      license: .exit(licenseExit)
    )
    let xcode = try tmp.installation(bundle, 27, 1)

    let status = try await Self.client(command, tmp).checkEnvironment()

    #expect(status == (licenseRequired ? .licenseNotAccepted(xcode) : .firstLaunchRequired(xcode)))
    #expect(command.invocations.map(\.arguments) == [["-p"], ["-checkFirstLaunchStatus"], ["-license", "check"]])
    #expect(command.invocations.dropFirst().allSatisfy { $0.executable == XcodeCommand.xcodebuild(in: xcode) })
  }

  @Test("xcodebuild 를 시작하지 못하면 checkFailed (두 단계 각각)", arguments: [false, true])
  func checkLaunchFailed(atLicense: Bool) async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    try tmp.makeXcode()
    let command = Responder.command(
      select: Responder.commandLineTools,
      firstLaunch: atLicense ? .exit(69) : .launchFailed,
      license: .launchFailed
    )

    await #expect(throws: DevEnvironmentError.checkFailed) {
      try await Self.client(command, tmp).checkEnvironment()
    }
    #expect(command.invocations.count == (atLicense ? 3 : 2))
  }

  // MARK: - 열기

  @Test("openXcode 는 고른 번들의 절대 경로로 /usr/bin/open")
  func openXcode() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let bundle = try tmp.makeXcode()
    let command = Responder.command(select: Responder.commandLineTools)

    try await Self.client(command, tmp).openXcode()

    let open = try #require(command.invocations.last)
    #expect(open.executable == XcodeCommand.open)
    #expect(try open.arguments == [tmp.installation(bundle, 27, 1).bundleURL.path(percentEncoded: false)])
    #expect(open.arguments.first?.hasPrefix("/") == true)
  }

  @Test("Xcode 가 없으면 openXcode 는 xcodeNotFound, open 실행 없음")
  func openXcodeNotFound() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let command = Responder.command(select: Responder.commandLineTools)

    await #expect(throws: DevEnvironmentError.xcodeNotFound) {
      try await Self.client(command, tmp).openXcode()
    }
    #expect(command.executables == ["xcode-select"])
  }

  @Test("open 이 0 이 아니거나 시작하지 못하면 openFailed", arguments: [Responder.Outcome.exit(1), .launchFailed])
  func openFailed(outcome: Responder.Outcome) async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    try tmp.makeXcode()
    let command = Responder.command(select: Responder.commandLineTools, open: outcome)
    let client = Self.client(command, tmp)

    await #expect(throws: DevEnvironmentError.openFailed) { try await client.openXcode() }
    await #expect(throws: DevEnvironmentError.openFailed) { try await client.openXcodeInAppStore() }
  }

  @Test("openXcodeInAppStore 는 App Store 의 Xcode 페이지를 연다 (xcode-select 실행 없음)")
  func openAppStore() async throws {
    let tmp = try TemporaryDirectory()
    defer { tmp.remove() }
    let command = Responder.command(select: .launchFailed)

    try await Self.client(command, tmp).openXcodeInAppStore()

    #expect(command.invocations.map(\.executable) == [XcodeCommand.open])
    #expect(command.invocations.map(\.arguments) == [["macappstore://apps.apple.com/app/id497799835"]])
  }
}

/// 깨진 Xcode 번들 종류.
enum Broken: CaseIterable, Sendable {
  case otherIdentifier, noInfoPlist, noXcodebuild, badVersion

  @discardableResult
  func make(_ tmp: TemporaryDirectory, _ name: String, in folder: URL) throws -> URL {
    switch self {
    case .otherIdentifier:
      try tmp.makeXcode(name, in: folder, identifier: "com.example.notxcode")
    case .noInfoPlist:
      try tmp.makeXcode(name, in: folder, infoPlist: false)
    case .noXcodebuild:
      try tmp.makeXcode(name, in: folder, xcodebuild: false)
    case .badVersion:
      try tmp.makeXcode(name, in: folder, version: "beta")
    }
  }
}
