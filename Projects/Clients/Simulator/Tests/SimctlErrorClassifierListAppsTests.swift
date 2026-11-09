import SimulatorInterface
import Testing
@testable import SimulatorImpl

/// listapps 분류. 꺼진 기기·없는 기기는 Xcode 27·iOS 27 에서 확인한 stderr 원문이다.
extension SimctlErrorClassifierTests {
  @Test(
    "listapps 실패를 domain·code 로, domain 줄이 없으면 공통 규칙으로 분류한다",
    arguments: [
      AppCase(name: "꺼진 기기", exitCode: 149, stderr: ListAppsStderr.shutdown, expected: .deviceNotBooted),
      AppCase(
        name: "없는 기기",
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
      AppCase(name: "모르는 domain", exitCode: 1, stderr: ListAppsStderr.unknownDomain, expected: .commandFailed),
      AppCase(name: "SimError 의 다른 code", exitCode: 1, stderr: ListAppsStderr.otherSimError, expected: .commandFailed),
      AppCase(name: "domain 줄 없는 모르는 실패", exitCode: 1, stderr: "Something went wrong\n", expected: .commandFailed),
    ]
  )
  func listAppsError(testCase: AppCase) {
    #expect(
      SimctlErrorClassifier.listAppsError(exitCode: testCase.exitCode, stderr: testCase.stderr) == testCase.expected
    )
  }
}

private enum ListAppsStderr {
  static let prefix = "An error was encountered processing the command "

  static let shutdown = Self.prefix + "(domain=com.apple.CoreSimulator.SimError, code=405):\n"
    + "Unable to lookup in current state: Shutdown\n"

  static let unknownDomain = Self.prefix + "(domain=NSPOSIXErrorDomain, code=5):\n"
    + "Input/output error\n"

  static let otherSimError = Self.prefix + "(domain=com.apple.CoreSimulator.SimError, code=403):\n"
    + "Invalid device state\n"
}
