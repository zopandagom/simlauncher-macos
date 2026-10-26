import SimulatorInterface
import Testing
@testable import SimulatorImpl

/// screenshot 분류. 픽스처는 Xcode 27.1 에서 확인한 stderr 원문이다 (UDID·경로는 줄였다).
extension SimctlErrorClassifierTests {
  @Test(
    "screenshot 실패를 domain·code 와 줄 머리로 분류한다",
    arguments: [
      AppCase(name: "꺼진 기기 (60)", exitCode: 60, stderr: ScreenshotStderr.timeout, expected: .deviceNotBooted),
      AppCase(name: "없는 상위 폴더 (4)", exitCode: 4, stderr: ScreenshotStderr.noFolder, expected: .commandFailed),
      AppCase(name: "쓸 수 없는 폴더 (513)", exitCode: 1, stderr: ScreenshotStderr.noPermission, expected: .commandFailed),
      AppCase(
        name: "없는 기기 (148)",
        exitCode: 148,
        stderr: "Invalid device: 00000000-0000-0000-0000-000000000000\n",
        expected: .deviceNotFound
      ),
      AppCase(
        name: "xcrun 오류",
        exitCode: 1,
        stderr: "xcrun: error: missing DEVELOPER_DIR path: /nonexistent\n",
        expected: .developerToolsUnavailable
      ),
      AppCase(
        name: "앞 공백 뒤 xcrun 오류",
        exitCode: 1,
        stderr: "\n  xcrun: error: unable to find utility \"simctl\"\n",
        expected: .developerToolsUnavailable
      ),
      AppCase(name: "경로 줄 안의 가짜 domain 문구", exitCode: 1, stderr: ScreenshotStderr.fakeDomain, expected: .commandFailed),
      AppCase(
        name: "경로에 Incompatible device·Invalid device 가 든 기기 이름",
        exitCode: 1,
        stderr: ScreenshotStderr.pathWithKeywords,
        expected: .commandFailed
      ),
      AppCase(name: "아무 단서 없음", exitCode: 1, stderr: "", expected: .commandFailed),
    ]
  )
  func screenshotError(testCase: AppCase) {
    #expect(SimctlErrorClassifier.screenshotError(exitCode: testCase.exitCode, stderr: testCase.stderr) == testCase
      .expected)
  }
}

private enum ScreenshotStderr {
  static let prefix = "An error was encountered processing the command "
  static let note = "Note: No display specified. Defaulting to display: 11111111-2222-3333-4444-555555555555 "
    + "(screenID: 1, name: LCD)\n"

  static let timeout = Self.note + Self.prefix + "(domain=NSPOSIXErrorDomain, code=60):\n"
    + "Timeout waiting for screen surfaces\n"

  static let noFolder = Self.prefix + "(domain=NSCocoaErrorDomain, code=4):\n"
    + "The folder “x.png” doesn’t exist.\n"

  static let noPermission = Self.prefix + "(domain=NSCocoaErrorDomain, code=513):\n"
    + "You don’t have permission to save the file “x.png” in the folder “SimLauncher”.\n"

  /// domain 줄이 아니라 경로 줄이 domain 문구를 품고 있다.
  static let fakeDomain = Self.note
    + "Wrote screenshot to: /x/" + Self.prefix + "(domain=NSPOSIXErrorDomain, code=60):\n"

  /// 기기 이름이 파일 이름에 들어간 경우. domain 줄은 없다.
  static let pathWithKeywords = Self.note
    + "Wrote screenshot to: /p/Invalid device: Incompatible device (iOS 26.5) 2026-10-25 14.21.33.png\n"
}
