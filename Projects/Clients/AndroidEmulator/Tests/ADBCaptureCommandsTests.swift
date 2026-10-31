import AndroidEmulatorInterface
import CommandInterface
import Foundation
import Testing
@testable import AndroidEmulatorImpl

/// 화면 캡처 adb 인자와 pid 줄·pull·녹화 결과 판정 (순수).
struct ADBCaptureCommandsTests {
  static let serial = "emulator-5554"
  static let remote = "/data/local/tmp/simlauncher-recording-0E5B0B4C-1C1F-4B9A-9F4E-2D3C4B5A6978.mp4"

  // MARK: - 인자

  @Test("스크린샷·정리·녹화·멈춤·가져오기·지우기 인자")
  func arguments() throws {
    let serial = Self.serial
    // 화면이 여럿인 AVD 의 경고(기기 stderr)가 PNG 앞에 붙지 않게 원격 셸에서 버린다.
    #expect(ADBCaptureCommands.screenshotArguments(serial: "emulator-5556") == [
      "-s", "emulator-5556", "exec-out", "screencap -p 2>/dev/null",
    ])
    let id = try #require(UUID(uuidString: "0e5b0b4c-1c1f-4b9a-9f4e-2d3c4b5a6978"))
    #expect(ADBCaptureCommands.recordingPath(id: id) == Self.remote)
    #expect(ADBCaptureCommands.cleanupArguments(serial: serial) == [
      "-s", serial, "shell", "rm", "-f", "/data/local/tmp/simlauncher-recording-*.mp4",
    ])
    #expect(ADBCaptureCommands.stopArguments(serial: serial, pid: "4242") == [
      "-s",
      serial,
      "shell",
      "kill",
      "-2",
      "4242",
    ])
    let local = URL(filePath: "/Users/tester/Movies/SimLauncher/Pixel (API 37.0) 2026-10-30 12.30.00.mp4")
    #expect(ADBCaptureCommands.pullArguments(serial: serial, remote: Self.remote, local: local) == [
      "-s", serial, "pull", Self.remote, "/Users/tester/Movies/SimLauncher/Pixel (API 37.0) 2026-10-30 12.30.00.mp4",
    ])
    #expect(ADBCaptureCommands.removeArguments(serial: serial, remote: Self.remote) == [
      "-s", serial, "shell", "rm", "-f", Self.remote,
    ])
  }

  @Test("녹화 인자: API 34 이상만 --time-limit 0, 원격 셸 문자열 하나로 pid 를 찍고 exec")
  func recordArguments() {
    let serial = Self.serial
    #expect(ADBCaptureCommands.recordArguments(serial: serial, path: Self.remote, apiLevel: 33) == [
      "-s", serial, "shell", "echo $$; exec screenrecord \(Self.remote)",
    ])
    for level in [34, 37] {
      #expect(ADBCaptureCommands.recordArguments(serial: serial, path: Self.remote, apiLevel: level) == [
        "-s", serial, "shell", "echo $$; exec screenrecord --time-limit 0 \(Self.remote)",
      ])
    }
  }

  @Test("PNG: 앞 8바이트 시그니처만 본다")
  func isPNG() {
    let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    #expect(ADBCaptureCommands.isPNG(Data(signature + [0x00, 0x00, 0x00, 0x0D])))
    #expect(ADBCaptureCommands.isPNG(Data(signature)))
    #expect(!ADBCaptureCommands.isPNG(Data()))
    #expect(!ADBCaptureCommands.isPNG(Data(signature.prefix(7))))
    #expect(!ADBCaptureCommands.isPNG(Data("error: device 'emulator-5999' not found\n".utf8)))
    // CRLF 로 바뀐 PNG (옛 adb·pty 의 `shell`)는 PNG 가 아니다.
    #expect(!ADBCaptureCommands.isPNG(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0D, 0x0A, 0x1A])))
  }

  // MARK: - pid 줄

  @Test("pid 줄: 조각 경계를 이어 첫 줄만, CRLF·공백 제거, 한 번만 true")
  func pidReader() {
    var reader = RecordingPIDReader()
    let first = reader.feed(Data("74".utf8))
    #expect(!first)
    #expect(reader.pid == nil)
    let second = reader.feed(Data("45\r\nmore".utf8))
    #expect(second)
    #expect(reader.pid == "7445")
    let third = reader.feed(Data("\n9999\n".utf8))
    #expect(!third)
    #expect(reader.pid == "7445")

    var spaced = RecordingPIDReader()
    let spacedFed = spaced.feed(Data("  12 \n".utf8))
    #expect(spacedFed)
    #expect(spaced.pid == "12")
  }

  @Test("pid 줄: 숫자가 아니거나 11자리 이상이거나 줄바꿈 없이 길면 시작 신호가 아니고 다음 줄도 보지 않는다")
  func pidReaderRejects() {
    for line in ["abc\n", "12; rm -rf /\n", "12345678901\n", "\n", "-1\n", "1 2\n"] {
      var reader = RecordingPIDReader()
      let rejected = reader.feed(Data(line.utf8))
      #expect(!rejected, "\(line)")
      let next = reader.feed(Data("4242\n".utf8))
      #expect(!next, "\(line)")
      #expect(reader.pid == nil, "\(line)")
    }
    var long = RecordingPIDReader()
    let longFed = long.feed(Data(String(repeating: "1", count: 65).utf8))
    #expect(!longFed)
    let longNext = long.feed(Data("\n4242\n".utf8))
    #expect(!longNext)
    #expect(long.pid == nil)
  }

  // MARK: - pull 결과

  static func result(_ code: Int32, stderr: String = "") -> Result<CommandResult, CommandError> {
    .success(CommandResult(exitCode: code, stdout: Data(), stderr: Data(stderr.utf8)))
  }

  @Test("pull: 성공은 로컬 크기, 원격 없음 문구, 시간 초과, 그 밖은 기기 확인으로 가른다")
  func pullOutcome() {
    #expect(ADBPullOutcome.immediate(Self.result(0), localSize: { 123 }) == .pulled(localSize: 123))
    #expect(ADBPullOutcome.immediate(Self.result(0), localSize: { 0 }) == .pulled(localSize: 0))
    let missing = "adb: error: failed to stat remote object '\(Self.remote)': No such file or directory\n"
    #expect(ADBPullOutcome.immediate(Self.result(1, stderr: missing), localSize: { 9 }) == .remoteMissing)
    #expect(ADBPullOutcome.immediate(.failure(.timedOut), localSize: { 9 }) == .timedOut)
    let other = "adb: error: cannot create '/Users/tester/Movies/x.mp4': No space left on device\n"
    #expect(ADBPullOutcome.immediate(Self.result(1, stderr: other), localSize: { 9 }) == nil)
    #expect(ADBPullOutcome.immediate(.failure(.launchFailed), localSize: { 9 }) == nil)
    #expect(ADBPullOutcome.afterDeviceCheck(online: true) == .localWriteFailed)
    #expect(ADBPullOutcome.afterDeviceCheck(online: false) == .deviceGone)
  }

  // MARK: - 녹화 결과 판정

  static func decide(
    _ ending: ADBRecordingOutcome.Ending,
    _ pull: ADBPullOutcome,
    timeLimited: Bool = false,
    sawStart: Bool = true
  ) -> ADBRecordingOutcome.Decision {
    ADBRecordingOutcome.decide(ending, timeLimited: timeLimited, sawStart: sawStart, pull: pull)
  }

  static func kept(_ error: AndroidEmulatorError) -> ADBRecordingOutcome.Decision {
    .init(result: .failure(error), removesRemote: false)
  }

  static func removed(_ result: AndroidScreenRecordingResult) -> ADBRecordingOutcome.Decision {
    .init(result: .success(result), removesRemote: true)
  }

  @Test("실행 실패는 adbUnavailable, 가져오지 못한 경우는 기기 파일을 남긴다 (어떻게 끝났든)")
  func decideFailures() {
    #expect(Self.decide(.launchFailed, .remoteMissing) == Self.kept(.adbUnavailable))
    let endings: [ADBRecordingOutcome.Ending] = [
      .stopped(exitCode: 0),
      .stoppedByHost,
      .exited(code: 0),
      .exited(code: 1),
    ]
    for ending in endings + [.displayOff(code: 218)] {
      #expect(Self.decide(ending, .deviceGone) == Self.kept(.recordingLost), "\(ending)")
      #expect(Self.decide(ending, .localWriteFailed) == Self.kept(.captureFileUnwritable), "\(ending)")
      #expect(Self.decide(ending, .timedOut) == Self.kept(.recordingTransferTimedOut), "\(ending)")
    }
  }

  @Test("멈춤 요청: 종료 코드 0 + 화면은 saved, 그 밖 + 화면은 savedAfterFailure, 화면 없음은 알림 없이 끝")
  func decideStopped() {
    #expect(Self.decide(.stopped(exitCode: 0), .pulled(localSize: 10)) == Self.removed(.saved))
    #expect(Self.decide(.stopped(exitCode: 130), .pulled(localSize: 10)) == Self.removed(.savedAfterFailure))
    #expect(Self.decide(.stoppedByHost, .pulled(localSize: 10)) == Self.removed(.savedAfterFailure))
    for ending in [ADBRecordingOutcome.Ending.stopped(exitCode: 0), .stopped(exitCode: 1), .stoppedByHost] {
      #expect(Self.decide(ending, .remoteMissing) == Self.removed(.stoppedBeforeStart), "\(ending)")
      #expect(Self.decide(ending, .pulled(localSize: 0)) == Self.removed(.stoppedBeforeStart), "\(ending)")
    }
    // 시작 신호 전에 호스트가 대신 멈췄으면 실패로 알리지 않는다: 화면을 가져왔으면 saved, 없으면 알림 없이 끝.
    #expect(Self.decide(.stoppedByHost, .pulled(localSize: 10), sawStart: false) == Self.removed(.saved))
    #expect(Self.decide(.stoppedByHost, .pulled(localSize: 0), sawStart: false) == Self.removed(.stoppedBeforeStart))
    #expect(Self.decide(.stoppedByHost, .remoteMissing, sawStart: false) == Self.removed(.stoppedBeforeStart))
    // 요청 멈춤은 시작 신호와 관계없이 크기로 정한다 (pid 줄은 파일 생성보다 먼저 온다).
    #expect(Self.decide(.stopped(exitCode: 0), .pulled(localSize: 10), sawStart: false) == Self.removed(.saved))
  }

  @Test("스스로 끝남: 3분 제한(API 33 이하)만 savedAtTimeLimit, 시작 실패·빈 파일 구분")
  func decideExited() {
    #expect(Self.decide(.exited(code: 0), .pulled(localSize: 10), timeLimited: true) == Self.removed(.savedAtTimeLimit))
    #expect(Self.decide(.exited(code: 0), .pulled(localSize: 10), timeLimited: false) == Self
      .removed(.savedAfterFailure))
    #expect(Self.decide(.exited(code: 1), .pulled(localSize: 10), timeLimited: true) == Self
      .removed(.savedAfterFailure))
    #expect(Self.decide(.exited(code: 1), .remoteMissing) == Self.kept(.recordingFailed))
    #expect(Self.decide(.exited(code: 0), .remoteMissing, timeLimited: true) == .init(
      result: .failure(.recordingEmpty),
      removesRemote: true
    ))
    #expect(Self.decide(.exited(code: 0), .pulled(localSize: 0)) == .init(
      result: .failure(.recordingEmpty),
      removesRemote: true
    ))
    #expect(Self.decide(.exited(code: 1), .pulled(localSize: 0)) == .init(
      result: .failure(.recordingEmpty),
      removesRemote: true
    ))
  }

  @Test("화면 꺼짐: 실패로 끝났고 stderr 에 UNASSIGNED_LAYER_STACK 이 있을 때만")
  func isDisplayOff() {
    func result(_ code: Int32, stdout: String = "", stderr: String = "") -> CommandResult {
      CommandResult(exitCode: code, stdout: Data(stdout.utf8), stderr: Data(stderr.utf8))
    }
    let message = "ERROR: UNASSIGNED_LAYER_STACK, please check your display state.\n"
    #expect(ADBCaptureCommands.isDisplayOff(result(218, stdout: "2750\n", stderr: message)))
    #expect(ADBCaptureCommands.isDisplayOff(result(1, stderr: message)))
    #expect(!ADBCaptureCommands.isDisplayOff(result(0, stderr: message)))
    #expect(!ADBCaptureCommands.isDisplayOff(result(218, stdout: message)))
    #expect(!ADBCaptureCommands.isDisplayOff(result(218, stderr: "Unable to open '/data/local/tmp/x.mp4'\n")))
    #expect(!ADBCaptureCommands.isDisplayOff(result(218)))
  }

  @Test("화면 꺼짐으로 끝남: 화면 없음·기기 파일 없음은 recordingDisplayOff, 화면이 담겼으면 savedAfterFailure")
  func decideDisplayOff() {
    let ending = ADBRecordingOutcome.Ending.displayOff(code: 218)
    #expect(Self.decide(ending, .pulled(localSize: 0)) == .init(
      result: .failure(.recordingDisplayOff),
      removesRemote: true
    ))
    #expect(Self.decide(ending, .remoteMissing) == Self.kept(.recordingDisplayOff))
    #expect(Self.decide(ending, .pulled(localSize: 10)) == Self.removed(.savedAfterFailure))
    #expect(Self.decide(ending, .pulled(localSize: 10), timeLimited: true) == Self.removed(.savedAfterFailure))
    // 문구 없이 같은 종료 코드면 지금 규칙 그대로.
    #expect(Self.decide(.exited(code: 218), .pulled(localSize: 0)) == .init(
      result: .failure(.recordingEmpty),
      removesRemote: true
    ))
    #expect(Self.decide(.exited(code: 218), .remoteMissing) == Self.kept(.recordingFailed))
  }
}
