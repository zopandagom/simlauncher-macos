import SimulatorInterface
import Testing
@testable import SimulatorImpl

struct SimctlErrorClassifierTests {
  struct Case: Sendable, CustomTestStringConvertible {
    let exitCode: Int32
    let stderr: String
    let expected: SimulatorError

    var testDescription: String {
      "\(self.exitCode) \(self.stderr.split(whereSeparator: \.isNewline).first?.prefix(40) ?? "")"
    }
  }

  @Test(
    "종료 코드·stderr 를 도메인 에러로 바꾼다",
    arguments: [
      Case(
        exitCode: 72,
        stderr: "xcrun: error: unable to find utility \"simctl\", not a developer tool or in PATH\n",
        expected: .developerToolsUnavailable
      ),
      Case(
        exitCode: 1,
        stderr: "xcrun: error: missing DEVELOPER_DIR path: /nonexistent/path\n",
        expected: .developerToolsUnavailable
      ),
      Case(
        exitCode: 1,
        stderr: "xcrun: error: invalid DEVELOPER_DIR path (/usr), missing xcrun at: /usr/usr/bin/xcrun\n",
        expected: .developerToolsUnavailable
      ),
      Case(
        exitCode: 1,
        stderr: "\nxcrun: error: missing DEVELOPER_DIR path: /nonexistent/path\n",
        expected: .developerToolsUnavailable
      ),
      Case(exitCode: 69, stderr: "xcrun: error: something new\n", expected: .developerToolsUnavailable),
      Case(
        exitCode: 148,
        stderr: "Invalid device or device pair: 00000000-0000-0000-0000-000000000001\n",
        expected: .deviceNotFound
      ),
      Case(exitCode: 148, stderr: "Invalid device: 00000000-0000-0000-0000-000000000001\n", expected: .deviceNotFound),
      Case(
        exitCode: 149,
        stderr: "An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=405):\n"
          + "Unable to boot device in current state: Booted\n",
        expected: .commandFailed
      ),
      Case(exitCode: 1, stderr: "Unrecognized subcommand: x\n", expected: .commandFailed),
      Case(exitCode: 1, stderr: "", expected: .commandFailed),
    ]
  )
  func classifies(testCase: Case) {
    #expect(SimctlErrorClassifier.error(exitCode: testCase.exitCode, stderr: testCase.stderr) == testCase.expected)
  }
}
