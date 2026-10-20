import CommandInterface
import CommandTesting
import Core
import Foundation
import Testing
@testable import DevEnvironmentImpl

struct XcodeCommandTests {
  private static let xcode = XcodeInstallation(
    bundleURL: URL(filePath: "/Applications/Xcode.app", directoryHint: .isDirectory),
    version: OSVersion(major: 27, minor: 1)
  )

  @Test("인자 배열: -license 와 check 는 두 원소다")
  func arguments() {
    #expect(XcodeCommand.printDeveloperDirectory() == ["-p"])
    #expect(XcodeCommand.checkFirstLaunchStatus() == ["-checkFirstLaunchStatus"])
    #expect(XcodeCommand.licenseCheck() == ["-license", "check"])
    #expect(XcodeCommand.openApp(bundlePath: "/Applications/Xcode.app/") == ["/Applications/Xcode.app/"])
    #expect(XcodeCommand.openAppStorePage() == ["macappstore://apps.apple.com/app/id497799835"])
    #expect(XcodeCommand.downloadPlatformIOS() == ["-downloadPlatform", "iOS"])
  }

  @Test("iOS Simulator SDK 의 SDKSettings·SystemVersion 경로는 고른 Xcode 안")
  func sdkPaths() {
    let sdk: [String] = [
      "/", "Applications", "Xcode.app", "Contents", "Developer",
      "Platforms", "iPhoneSimulator.platform", "Developer", "SDKs", "iPhoneSimulator.sdk",
    ]
    let settings: [String] = sdk + ["SDKSettings.plist"]
    let systemVersion: [String] = sdk + ["System", "Library", "CoreServices", "SystemVersion.plist"]
    #expect(XcodeCommand.iOSSimulatorSDKSettings(in: Self.xcode).pathComponents == settings)
    #expect(XcodeCommand.iOSSimulatorSDKSystemVersion(in: Self.xcode).pathComponents == systemVersion)
  }

  @Test("실행 파일: /usr/bin 의 xcode-select·open, 고른 Xcode 안의 xcodebuild (xcrun·xcodebuild shim 은 쓰지 않는다)")
  func executables() {
    #expect(XcodeCommand.xcodeSelect.path(percentEncoded: false) == "/usr/bin/xcode-select")
    #expect(XcodeCommand.open.path(percentEncoded: false) == "/usr/bin/open")
    #expect(
      XcodeCommand.xcodebuild(in: Self.xcode).pathComponents
        == ["/", "Applications", "Xcode.app", "Contents", "Developer", "usr", "bin", "xcodebuild"]
    )
  }

  @Test("환경: 개발자 디렉터리가 있으면 DEVELOPER_DIR 로 넣고 없으면 지운다, 나머지는 그대로")
  func environment() {
    let base = ["PATH": "/usr/bin", "DEVELOPER_DIR": "/nonexistent"]

    let cleared = XcodeCommand.environment(base: base, developerDirectory: nil)
    #expect(cleared == ["PATH": "/usr/bin"])

    let set = XcodeCommand.environment(base: base, developerDirectory: Self.xcode.developerDirectory)
    #expect(set == ["PATH": "/usr/bin", "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer/"])
  }

  @Test("xcode-select -p 출력은 앞뒤 공백·개행을 지운 절대 경로")
  func selectedDeveloperDirectory() {
    let result = CommandResult.success(Data("  /Applications/Xcode.app/Contents/Developer\n".utf8))
    let directory = XcodeCommand.selectedDeveloperDirectory(from: result)
    #expect(directory?.path(percentEncoded: false) == "/Applications/Xcode.app/Contents/Developer/")
  }

  @Test(
    "xcode-select -p 가 실패했거나 절대 경로가 아니면 nil",
    arguments: [
      CommandResult(exitCode: 2, stdout: Data("/Applications/Xcode.app/Contents/Developer\n".utf8), stderr: Data()),
      CommandResult.success(Data([0xFF, 0xFE])),
      CommandResult.success(Data()),
      CommandResult.success(Data(" \n".utf8)),
      CommandResult.success(Data("Xcode.app/Contents/Developer\n".utf8)),
    ]
  )
  func invalidSelection(result: CommandResult) {
    #expect(XcodeCommand.selectedDeveloperDirectory(from: result) == nil)
  }

  @Test(
    "개발자 디렉터리가 <X>.app/Contents/Developer 꼴이면 그 번들",
    arguments: [
      ("/A/Xcode.app/Contents/Developer", "/A/Xcode.app/"),
      ("/A/Xcode.app/Contents/Developer/", "/A/Xcode.app/"),
      ("/Applications/Xcode-beta.APP/Contents/Developer", "/Applications/Xcode-beta.APP/"),
      ("/A/B/../Xcode.app/Contents/Developer", "/A/Xcode.app/"),
    ]
  )
  func xcodeBundle(directory: String, expected: String) {
    let bundle = XcodeCommand.xcodeBundle(forDeveloperDirectory: URL(filePath: directory, directoryHint: .isDirectory))
    #expect(bundle?.path(percentEncoded: false) == expected)
  }

  @Test(
    "번들 안 Contents/Developer 가 아니면 번들이 아니다",
    arguments: [
      "/Library/Developer/CommandLineTools",
      "/usr",
      "/",
      "/A/Xcode.app/Contents",
      "/A/Xcode/Contents/Developer",
      "/A/Xcode.app/Contents/Developer/usr",
    ]
  )
  func notXcodeBundle(directory: String) {
    #expect(XcodeCommand
      .xcodeBundle(forDeveloperDirectory: URL(filePath: directory, directoryHint: .isDirectory)) == nil)
  }

  @Test(
    "Command Line Tools 경로와 그 아래는 끝 슬래시와 상관없이 CLT",
    arguments: [
      ("/Library/Developer/CommandLineTools", true),
      ("/Library/Developer/CommandLineTools/", true),
      ("/Library/Developer/CommandLineTools/usr", true),
      ("/Library/Developer/CommandLineToolsX", false),
      ("/Library/Developer", false),
      ("/Applications/Xcode.app/Contents/Developer", false),
    ]
  )
  func commandLineTools(path: String, expected: Bool) {
    #expect(XcodeCommand.isCommandLineTools(URL(filePath: path)) == expected)
  }

  @Test("확인 명령은 종료 코드 0 만 통과", arguments: [(Int32(0), true), (69, false), (1, false), (64, false)])
  func passed(exitCode: Int32, expected: Bool) {
    let result = CommandResult(exitCode: exitCode, stdout: Data(), stderr: Data())
    #expect(XcodeCommand.passed(result) == expected)
  }
}
