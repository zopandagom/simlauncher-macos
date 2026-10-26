import SimulatorInterface
import Testing
@testable import SimulatorImpl

/// recordVideo 시작 실패 분류. 픽스처는 Xcode 27.1·iOS 27.0 에서 확인한 stderr 원문이다 (UDID·주소는 줄였다).
extension SimctlErrorClassifierTests {
  @Test(
    "recordVideo 실패를 domain·code 와 줄 머리로 분류한다",
    arguments: [
      AppCase(
        name: "같은 기기를 다른 녹화가 쓰는 중 (16)",
        exitCode: 16,
        stderr: RecordingStderr.busy,
        expected: .recordingInProgress
      ),
      AppCase(name: "--force 없이 있는 파일 (17)", exitCode: 17, stderr: RecordingStderr.exists, expected: .commandFailed),
      AppCase(
        name: "없는 폴더 (NSURLErrorDomain -3000)",
        exitCode: 72,
        stderr: RecordingStderr.noFolder,
        expected: .commandFailed
      ),
      AppCase(
        name: "쓸 수 없는 폴더 (NSCocoaErrorDomain 513)",
        exitCode: 1,
        stderr: RecordingStderr.noPermission,
        expected: .commandFailed
      ),
      AppCase(
        name: "없는 기기 (148)",
        exitCode: 148,
        stderr: "Invalid device: 00000000-0000-0000-0000-000000000000\n",
        expected: .deviceNotFound
      ),
      AppCase(
        name: "xcrun 오류",
        exitCode: 72,
        stderr: "xcrun: error: unable to find utility \"simctl\", not a developer tool or in PATH\n",
        expected: .developerToolsUnavailable
      ),
      AppCase(
        name: "경로에 Invalid device 가 든 기기 이름",
        exitCode: 1,
        stderr: RecordingStderr.pathWithKeywords,
        expected: .commandFailed
      ),
      AppCase(name: "아무 단서 없음", exitCode: 1, stderr: "", expected: .commandFailed),
    ]
  )
  func recordingError(testCase: AppCase) {
    #expect(SimctlErrorClassifier.recordingError(exitCode: testCase.exitCode, stderr: testCase.stderr) == testCase
      .expected)
  }
}

private enum RecordingStderr {
  static let prefix = "An error was encountered processing the command "
  static let note = "Note: No display specified. Defaulting to display: 11111111-2222-3333-4444-555555555555 "
    + "(screenID: 1, name: LCD)\n"

  static let busy = Self.note
    + "Error starting video recorder: Error Domain=NSPOSIXErrorDomain Code=16 \"Resource busy\" "
    + "UserInfo={NSLocalizedFailureReason=Host recording is already in progress}.\n"
    + Self.prefix + "(domain=NSPOSIXErrorDomain, code=16):\n"
    + "The operation couldn’t be completed. Host recording is already in progress\n"
    + "Host recording is already in progress\n"

  static let exists = Self.prefix + "(domain=NSPOSIXErrorDomain, code=17):\n"
    + "Error: cannot save recorded video output into a file that already exists (use -f to override).\n"
    + "File exists\n"

  static let noFolder = Self.note
    + "Error starting video recorder: Error Domain=NSURLErrorDomain Code=-3000 \"Cannot create file\" "
    + "UserInfo={NSLocalizedDescription=Cannot create file, NSUnderlyingError=0x0 "
    + "{Error Domain=NSOSStatusErrorDomain Code=-12143 \"(null)\"}}.\n"
    + Self.prefix + "(domain=NSURLErrorDomain, code=-3000):\n"
    + "Cannot create file\n"
    + "Underlying error (domain=NSOSStatusErrorDomain, code=-12143):\n"
    + "\tThe operation couldn’t be completed. (OSStatus error -12143.)\n"

  static let noPermission = Self.note
    + "Error starting video recorder: Error Domain=NSCocoaErrorDomain Code=513 "
    + "\"The file couldn’t be saved because you don’t have permission.\" "
    + "UserInfo={NSUnderlyingError=0x0 {Error Domain=NSOSStatusErrorDomain Code=-12204 \"(null)\"}}.\n"
    + Self.prefix + "(domain=NSCocoaErrorDomain, code=513):\n"
    + "The file couldn’t be saved because you don’t have permission.\n"
    + "You don’t have permission.\n"
    + "To view or change permissions, select the item in the Finder and choose File > Get Info.\n"
    + "Underlying error (domain=NSOSStatusErrorDomain, code=-12204):\n"
    + "\tThe operation couldn’t be completed. (OSStatus error -12204.)\n"

  /// 기기 이름이 경로에 들어간 경우. domain 줄은 없다.
  static let pathWithKeywords = Self.note
    + "Wrote video to: /m/Invalid device: x (iOS 27.0) 2026-10-26 13.41.00.mov\n"
}
