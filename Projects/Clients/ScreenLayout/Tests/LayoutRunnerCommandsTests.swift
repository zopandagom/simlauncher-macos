import CommandInterface
import Core
import DevEnvironmentTesting
import Foundation
import Testing
@testable import ScreenLayoutImpl

struct LayoutRunnerCommandsTests {
  static let udid = "C9B1FBEB-10D8-4DA6-A566-C7D778FF62CD"
  static let session = URL(filePath: "/Users/me/Library/Caches/app id/LayoutRunner/sessions/\(udid)/")

  @Test("xcodebuild 는 선택한 Xcode 의 Developer 아래, 환경은 기본 환경 + DEVELOPER_DIR")
  func xcodebuildAndEnvironment() {
    #expect(
      LayoutRunnerCommands.xcodebuild(.sample).path == "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"
    )
    let environment = LayoutRunnerCommands.environment(base: ["PATH": "/bin", "DEVELOPER_DIR": "/old"], xcode: .sample)
    #expect(environment == ["PATH": "/bin", "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer/"])
  }

  @Test("빌드 인자")
  func buildArguments() {
    let partial = URL(filePath: "/R/builds/27B52-abc.partial-1/")
    let arguments = LayoutRunnerCommands.buildArguments(
      sourceDirectory: partial.appending(path: "Source"),
      derivedData: partial.appending(path: "DerivedData")
    )
    #expect(arguments == [
      "build-for-testing",
      "-project", "/R/builds/27B52-abc.partial-1/Source/LayoutRunner.xcodeproj",
      "-scheme", "LayoutRunner",
      "-destination", "generic/platform=iOS Simulator",
      "-derivedDataPath", "/R/builds/27B52-abc.partial-1/DerivedData",
      "-quiet",
      "CODE_SIGNING_ALLOWED=NO",
    ])
  }

  @Test("상주 인자: xctestrun·기기·세션 폴더의 DerivedData·결과 번들, 시간 제한 끔 (공백 든 경로 그대로)")
  func testArguments() {
    let arguments = LayoutRunnerCommands.testArguments(
      xctestrun: URL(filePath: "/R/builds/K/Products/LayoutRunner_iphonesimulator27.2-arm64-x86_64.xctestrun"),
      udid: Self.udid,
      sessionDirectory: Self.session
    )
    #expect(arguments == [
      "test-without-building",
      "-xctestrun", "/R/builds/K/Products/LayoutRunner_iphonesimulator27.2-arm64-x86_64.xctestrun",
      "-destination", "id=\(Self.udid)",
      "-derivedDataPath", "/Users/me/Library/Caches/app id/LayoutRunner/sessions/\(Self.udid)/DerivedData",
      "-resultBundlePath", "/Users/me/Library/Caches/app id/LayoutRunner/sessions/\(Self.udid)/result.xcresult",
      "-test-timeouts-enabled", "NO",
    ])
  }

  @Test("상주 환경: 기본 환경 유지 + DEVELOPER_DIR + TEST_RUNNER_ 세 값")
  func testEnvironment() {
    let environment = LayoutRunnerCommands.testEnvironment(
      base: ["PATH": "/bin", "HOME": "/Users/me"],
      xcode: .beta,
      sessionDirectory: Self.session,
      token: "TOKEN",
      idleSeconds: 600
    )
    #expect(environment == [
      "PATH": "/bin",
      "HOME": "/Users/me",
      "DEVELOPER_DIR": "/Applications/Xcode-beta.app/Contents/Developer/",
      "TEST_RUNNER_SIMLAUNCHER_LAYOUT_DIR": "/Users/me/Library/Caches/app id/LayoutRunner/sessions/\(Self.udid)/",
      "TEST_RUNNER_SIMLAUNCHER_LAYOUT_SESSION": "TOKEN",
      "TEST_RUNNER_SIMLAUNCHER_LAYOUT_IDLE": "600",
    ])
  }

  @Test("ps 인자")
  func psArguments() {
    #expect(LayoutRunnerCommands.psExecutable.path == "/bin/ps")
    #expect(LayoutRunnerCommands.psArguments(pid: 4321) == ["-p", "4321", "-o", "comm="])
  }

  static let runnerPath = "/Users/me/Library/Developer/CoreSimulator/Devices/\(udid)/data/Containers/Bundle/"
    + "Application/0A/SimLauncherLayout-Runner.app/SimLauncherLayout-Runner\n"

  @Test(
    "생존 판정: 이 기기의 러너 실행 파일일 때만",
    arguments: [
      (Int32(0), runnerPath, true),
      (0, runnerPath.replacingOccurrences(of: udid, with: "00000000-0000-0000-0000-000000000001"), false),
      (0, runnerPath.replacingOccurrences(of: "SimLauncherLayout-Runner\n", with: "Other\n"), false),
      (0, "/usr/libexec/SimLauncherLayout-Runner", false),
      (1, runnerPath, false),
      (1, "", false),
      (0, "", false),
    ]
  )
  func alive(exitCode: Int32, output: String, expected: Bool) {
    let result = CommandResult(exitCode: exitCode, stdout: Data(output.utf8), stderr: Data())
    #expect(LayoutRunnerCommands.isRunnerAlive(result, udid: Self.udid) == expected)
  }

  static func plist(_ object: [String: Any]) -> Data {
    (try? PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)) ?? Data()
  }

  @Test("version.plist 의 ProductBuildVersion: 영숫자만, 없거나 plist 아니면 nil")
  func productBuildVersion() {
    #expect(LayoutRunnerCommands
      .productBuildVersion(fromVersionPlist: Self.plist(["ProductBuildVersion": "27B52"])) == "27B52")
    #expect(
      LayoutRunnerCommands.productBuildVersion(fromVersionPlist: Self.plist(["ProductBuildVersion": "27B52/../x"]))
        == "27B52x"
    )
    #expect(LayoutRunnerCommands
      .productBuildVersion(fromVersionPlist: Self.plist(["ProductBuildVersion": "/.-"])) == nil)
    #expect(LayoutRunnerCommands.productBuildVersion(fromVersionPlist: Self.plist(["CFBundleVersion": "1"])) == nil)
    #expect(LayoutRunnerCommands.productBuildVersion(fromVersionPlist: Data("not plist".utf8)) == nil)
    #expect(LayoutRunnerCommands.versionPlist(.sample).path == "/Applications/Xcode.app/Contents/version.plist")
  }

  @Test("빌드 키: <빌드 버전 또는 unknown>-<16자>, 소스·Xcode 경로가 바뀌면 다르다")
  func buildKey() {
    let key = LayoutRunnerCommands.buildKey(productBuildVersion: "27B52", sourceDigest: "abc", xcodePath: "/X.app/")
    #expect(key.hasPrefix("27B52-"))
    #expect(key.count == "27B52-".count + 16)
    #expect(key == LayoutRunnerCommands.buildKey(
      productBuildVersion: "27B52",
      sourceDigest: "abc",
      xcodePath: "/X.app/"
    ))
    #expect(key != LayoutRunnerCommands.buildKey(
      productBuildVersion: "27B52",
      sourceDigest: "abd",
      xcodePath: "/X.app/"
    ))
    #expect(key != LayoutRunnerCommands.buildKey(
      productBuildVersion: "27B52",
      sourceDigest: "abc",
      xcodePath: "/Y.app/"
    ))
    #expect(
      LayoutRunnerCommands.buildKey(productBuildVersion: nil, sourceDigest: "abc", xcodePath: "/X.app/")
        .hasPrefix("unknown-")
    )
  }

  @Test("UDID 형식")
  func udidFormat() {
    #expect(LayoutRunnerCommands.isUDID(Self.udid))
    #expect(!LayoutRunnerCommands.isUDID("ABC"))
    #expect(!LayoutRunnerCommands.isUDID("--help"))
    #expect(!LayoutRunnerCommands.isUDID(""))
  }
}
