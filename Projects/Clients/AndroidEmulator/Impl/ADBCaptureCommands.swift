import AndroidEmulatorInterface
import CommandInterface
import Foundation

/// 켜진 기기의 화면 캡처(스크린샷·녹화) adb 인자와 결과 판정 (순수). 원격 셸에 들어가는 값은 앱이 만든 경로(고정 접두어 +
/// UUID)와 `RecordingPIDReader` 가 숫자만 받은 pid 뿐이라 인용하지 않는다. 로컬 경로는 호스트 argv 라 인용하지 않는다.
enum ADBCaptureCommands {
  /// 기기 임시 녹화 파일 폴더 (shell 소유 0771, 쓰기·pull·`rm -f` 실측).
  static let remoteFolder = "/data/local/tmp"
  static let remotePrefix = "simlauncher-recording-"
  /// `--time-limit 0`(제한 없음)을 받는 가장 낮은 API. 그 아래는 기본 180초에 스스로 끝난다 (API 37 실측, 34 경계는 미확인).
  static let unlimitedAPILevel = 34
  static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
  /// 화면이 꺼진(잠든) 기기에서 screenrecord 가 시작하자마자 stderr 에 찍는 문구 (화면이 여럿인 AVD, 종료 코드 218, 실측).
  static let displayOffMarker = "UNASSIGNED_LAYER_STACK"

  /// `exec-out` 은 stdout 을 변환 없이 넘긴다 (`shell` 은 옛 adb·pty 에서 `\n`→`\r\n` 변환이 알려져 있다).
  /// 다만 기기 stderr 도 stdout 에 합치므로, 화면이 여럿인 AVD(폴더블)에서 screencap 이 찍는 경고가 PNG 앞에 붙는다(실측).
  /// 그래서 원격 셸에서 stderr 를 버린다 (원격 셸 문자열 하나, 고정 값이라 인용하지 않는다).
  static func screenshotArguments(serial: String) -> [String] {
    ["-s", serial, "exec-out", "screencap -p 2>/dev/null"]
  }

  /// 앞 8바이트가 PNG 시그니처다.
  static func isPNG(_ data: Data) -> Bool {
    data.prefix(self.pngSignature.count).elementsEqual(self.pngSignature)
  }

  static func recordingPath(id: UUID) -> String {
    "\(self.remoteFolder)/\(self.remotePrefix)\(id.uuidString.uppercased()).mp4"
  }

  /// 이 앱이 남긴 기기 임시 녹화 파일을 모두 지운다 (`*` 는 원격 셸이 펼친다. 없으면 아무것도 하지 않는다).
  static func cleanupArguments(serial: String) -> [String] {
    ["-s", serial, "shell", "rm", "-f", "\(self.remoteFolder)/\(self.remotePrefix)*.mp4"]
  }

  /// 원격 셸 문자열 하나: 셸 pid 를 찍고 screenrecord 로 바뀐다 (`exec` 라 첫 줄 pid = screenrecord pid, 실측).
  static func recordArguments(serial: String, path: String, apiLevel: Int) -> [String] {
    let limit = apiLevel >= self.unlimitedAPILevel ? " --time-limit 0" : ""
    return ["-s", serial, "shell", "echo $$; exec screenrecord\(limit) \(path)"]
  }

  /// 녹화 adb 가 실패로 끝났고(종료 코드 ≠ 0) stderr 에 화면 꺼짐 문구가 있다.
  static func isDisplayOff(_ result: CommandResult) -> Bool {
    guard result.exitCode != 0 else { return false }
    let stderr = String(bytes: result.stderr, encoding: .utf8) ?? ""
    return stderr.contains(self.displayOffMarker)
  }

  /// 기기 안 screenrecord 에 SIGINT: 파일을 마무리하고 녹화 adb 가 종료 코드 0 으로 끝난다 (실측 0.27~0.82초).
  static func stopArguments(serial: String, pid: String) -> [String] {
    ["-s", serial, "shell", "kill", "-2", pid]
  }

  static func pullArguments(serial: String, remote: String, local: URL) -> [String] {
    ["-s", serial, "pull", remote, FileFacts.path(local)]
  }

  static func removeArguments(serial: String, remote: String) -> [String] {
    ["-s", serial, "shell", "rm", "-f", remote]
  }
}

/// 녹화 adb 의 stdout 조각을 이어 첫 줄을 pid 로 읽는다 (앞뒤 공백·`\r` 제거, 숫자 1~10자리만). 첫 줄이 숫자가 아니면 시작 신호가 없다.
struct RecordingPIDReader {
  /// 줄바꿈 없이 이보다 길게 쌓이면 시작 신호가 아니다.
  static let maxLineLength = 64

  private var buffer = Data()
  private var finished = false
  private(set) var pid: String?

  /// 조각을 받아, 이 조각에서 처음 pid 를 읽었으면 true. 첫 줄을 본 뒤에는 늘 false 이고 더 쌓지 않는다.
  mutating func feed(_ data: Data) -> Bool {
    guard !self.finished else { return false }
    self.buffer.append(data)
    guard let newline = self.buffer.firstIndex(of: UInt8(ascii: "\n")) else {
      if self.buffer.count > Self.maxLineLength {
        self.finished = true
        self.buffer = Data()
      }
      return false
    }
    let line = String(bytes: self.buffer[self.buffer.startIndex ..< newline], encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    self.finished = true
    self.buffer = Data()
    guard let line, line.wholeMatch(of: /[0-9]{1,10}/) != nil else {
      return false
    }
    self.pid = line
    return true
  }
}

/// `adb pull` 결과 해석 (실측한 값만 쓴다: 원격 크기를 따로 읽지 않는다. 원격이 0바이트면 pull 이 성공하고 로컬 크기 0 이다).
enum ADBPullOutcome: Hashable {
  case pulled(localSize: Int)
  /// 종료 코드 ≠ 0 이고 `failed to stat remote object` (원격 파일 없음, 종료 코드 1, 로컬 파일을 만들지 않는다, 실측).
  case remoteMissing
  /// 그 밖의 실패이고 그 serial 이 adb 에서 `device` 가 아니다 (adb 가 답하지 않거나 실행되지 않은 경우 포함).
  case deviceGone
  /// 그 밖의 실패이고 그 serial 이 online 이다: Mac 쪽 쓰기 실패(디스크·폴더).
  case localWriteFailed
  /// 시간 제한을 넘었다 (원인을 모른다).
  case timedOut

  /// 기기 확인 없이 정할 수 있으면 그 값, 아니면 nil (`afterDeviceCheck` 로 가른다). `localSize` 는 성공일 때만 부른다.
  static func immediate(_ result: Result<CommandResult, CommandError>, localSize: () -> Int) -> ADBPullOutcome? {
    switch result {
    case let .success(result) where result.exitCode == 0:
      return .pulled(localSize: localSize())
    case let .success(result):
      let stderr = String(bytes: result.stderr, encoding: .utf8) ?? ""
      return stderr.contains("failed to stat remote object") ? .remoteMissing : nil
    case .failure(.timedOut):
      return .timedOut
    case .failure:
      return nil
    }
  }

  static func afterDeviceCheck(online: Bool) -> ADBPullOutcome {
    online ? .localWriteFailed : .deviceGone
  }
}

/// 끝난 녹화의 결과 판정 (순수). 원격 파일을 지울지 함께 정한다: 화면이 담긴 파일을 가져오지 못했으면 기기에 남긴다.
enum ADBRecordingOutcome {
  enum Ending: Hashable {
    /// 멈춤 요청(기기 안 `kill -2`)으로 녹화 adb 가 이 종료 코드로 끝났다.
    case stopped(exitCode: Int32)
    /// 멈춤 요청 뒤 끝나지 않아(또는 pid 를 몰라) 호스트에서 녹화 adb 를 대신 멈췄다. 마무리를 확인하지 못했다.
    case stoppedByHost
    /// 요청 없이 스스로 끝났다.
    case exited(code: Int32)
    /// 요청 없이 실패로 끝났고 화면 꺼짐 문구가 있었다 (`ADBCaptureCommands.isDisplayOff`).
    case displayOff(code: Int32)
    /// 녹화 adb 를 실행하지 못했다 (가져오지 않는다).
    case launchFailed
  }

  struct Decision: Equatable {
    let result: Result<AndroidScreenRecordingResult, AndroidEmulatorError>
    /// 기기 임시 파일을 지운다.
    let removesRemote: Bool
  }

  private static func stoppedResult(_ ending: Ending) -> AndroidScreenRecordingResult {
    ending == .stopped(exitCode: 0) ? .saved : .savedAfterFailure
  }

  private static func pulledSize(_ pull: ADBPullOutcome) -> Result<Int, AndroidEmulatorError> {
    switch pull {
    case .deviceGone: .failure(.recordingLost)
    case .localWriteFailed: .failure(.captureFileUnwritable)
    case .timedOut: .failure(.recordingTransferTimedOut)
    case .remoteMissing: .success(0)
    case let .pulled(localSize): .success(localSize)
    }
  }

  /// - Parameters:
  ///   - timeLimited: API 34 아래라 제한 인자 없이(기본 3분) 시작했다.
  ///   - sawStart: 시작 신호(pid 줄)를 받았다. 호스트가 대신 멈춘 경우만 본다 (pid 줄은 파일 생성보다 먼저 온다).
  ///     신호 전에 대신 멈췄어도 화면이 담긴 파일을 가져왔으면 숨기지 않고 `.saved` 다 (사용자가 멈췄으므로 실패로 알리지 않는다).
  ///   - pull: `launchFailed` 면 보지 않는다.
  static func decide(_ ending: Ending, timeLimited: Bool, sawStart: Bool, pull: ADBPullOutcome) -> Decision {
    if ending == .launchFailed {
      return Decision(result: .failure(.adbUnavailable), removesRemote: false)
    }
    let size: Int
    switch self.pulledSize(pull) {
    case let .success(value): size = value
    case let .failure(error): return Decision(result: .failure(error), removesRemote: false)
    }
    let result: Result<AndroidScreenRecordingResult, AndroidEmulatorError>
    switch ending {
    case .stoppedByHost where !sawStart:
      result = .success(size == 0 ? .stoppedBeforeStart : .saved)
    case .stopped, .stoppedByHost:
      // 요청으로 멈췄고 화면이 없으면 알리지 않는다.
      result = .success(size == 0 ? .stoppedBeforeStart : self.stoppedResult(ending))
    case let .exited(code) where size > 0:
      result = .success(code == 0 && timeLimited ? .savedAtTimeLimit : .savedAfterFailure)
    case .displayOff where size > 0:
      // 녹화 도중 잠들어 끝난 경우: 담긴 화면은 지금 규칙대로 저장한다.
      result = .success(.savedAfterFailure)
    case .displayOff:
      // 원인이 확정된 문구가 앞선다. 기기 파일이 없으면 지울 것도 없다.
      return Decision(result: .failure(.recordingDisplayOff), removesRemote: pull != .remoteMissing)
    case let .exited(code) where code != 0 && pull == .remoteMissing:
      return Decision(result: .failure(.recordingFailed), removesRemote: false)
    case .exited, .launchFailed:
      result = .failure(.recordingEmpty)
    }
    return Decision(result: result, removesRemote: true)
  }
}
