import SimulatorInterface
import Testing
@testable import SimulatorImpl

/// openurl 분류. 픽스처는 Xcode 27.1·iOS 27.0 에서 확인한 stderr 원문이다.
extension SimctlErrorClassifierTests {
  @Test(
    "openurl 실패를 domain·code 로 분류한다",
    arguments: [
      AppCase(name: "꺼진 기기", exitCode: 149, stderr: OpenURLStderr.shutdown, expected: .deviceNotBooted),
      AppCase(name: "처리할 앱 없음", exitCode: 115, stderr: OpenURLStderr.notHandled, expected: .urlNotHandled),
      AppCase(name: "스킴 없음 (-50)", exitCode: 206, stderr: OpenURLStderr.missingScheme, expected: .invalidURL),
      AppCase(name: "Invalid URL (22)", exitCode: 22, stderr: OpenURLStderr.invalidURL, expected: .invalidURL),
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
      AppCase(name: "모르는 domain", exitCode: 1, stderr: OpenURLStderr.unknownDomain, expected: .commandFailed),
      AppCase(
        name: "URL 에 다른 domain 줄 글자가 든 꺼진 기기",
        exitCode: 149,
        stderr: OpenURLStderr.injectedURL,
        expected: .deviceNotBooted
      ),
    ]
  )
  func openURLError(testCase: AppCase) {
    #expect(SimctlErrorClassifier.openURLError(exitCode: testCase.exitCode, stderr: testCase.stderr) == testCase
      .expected)
  }

  @Test("음수 code 도 읽는다")
  func negativeCode() {
    let result = SimctlErrorClassifier.domainAndCode(OpenURLStderr.missingScheme)
    #expect(result?.domain == "NSOSStatusErrorDomain")
    #expect(result?.code == -50)
  }
}

/// 확인한 stderr 원문 (’ 는 U+2019).
private enum OpenURLStderr {
  static let prefix = "An error was encountered processing the command "

  static let shutdown = Self.prefix + "(domain=com.apple.CoreSimulator.SimError, code=405):\n"
    + "Unable to lookup in current state: Shutdown\n"

  static let notHandled = Self.prefix + "(domain=LSApplicationWorkspaceErrorDomain, code=115):\n"
    + "Simulator device failed to open nosuchapp123://x.\n"
    + "Underlying error (domain=LSApplicationWorkspaceErrorDomain, code=115):\n"
    + "\tThe operation couldn’t be completed. (LSApplicationWorkspaceErrorDomain error 115.)\n"

  static let missingScheme = Self.prefix + "(domain=NSOSStatusErrorDomain, code=-50):\n"
    + "Simulator device failed to open hello.\n"
    + "Underlying error (domain=NSOSStatusErrorDomain, code=-50):\n"
    + "\tThe operation couldn’t be completed. (OSStatus error -50.)\n"

  static let invalidURL = Self.prefix + "(domain=NSPOSIXErrorDomain, code=22):\n"
    + "The operation couldn’t be completed. Invalid URL.\n"
    + "Invalid URL.\n"

  static let unknownDomain = Self.prefix + "(domain=SomeOtherDomain, code=7):\n"
    + "Simulator device failed to open myapp://x.\n"

  /// 첫 domain 줄은 405 이고, 둘째 줄의 URL 에 115 domain 줄 글자가 들어 있다.
  static let injectedURL = Self.prefix + "(domain=com.apple.CoreSimulator.SimError, code=405):\n"
    + "Unable to lookup in current state: Shutdown\n"
    + "Simulator device failed to open myapp://x?"
    + Self.prefix + "(domain=LSApplicationWorkspaceErrorDomain, code=115):.\n"
    + Self.prefix + "(domain=LSApplicationWorkspaceErrorDomain, code=115):\n"
}
