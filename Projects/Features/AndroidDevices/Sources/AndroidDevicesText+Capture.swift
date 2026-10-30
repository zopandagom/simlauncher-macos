import AndroidEmulatorInterface
import Core
import Foundation
import WorkspaceInterface

/// 스크린샷·녹화 문구. 키는 다른 문구와 같은 `Localizable.xcstrings` 에 있다.
/// 행의 버튼·진행·막힌 이유, 저장 폴더 실패, 꺼짐·Finder·기기 꺼짐 저장 문구는 iOS 기기 목록(Launcher)과 같은 키·값으로 둔다
/// (`LauncherTextSyncTests`). 알림 제목은 Android 기기 라벨(`label(_:)`)을 넣고, 기기 안에서 녹화해 가져오는 데서 생기는
/// 실패(시작·가져오기·3분 제한·기기 꺼짐)는 Android 문구다. 저장 폴더(사진·동영상) 실패 문구는 `AndroidDevicesText+CaptureFolder.swift`.
extension AndroidDevicesText {
  // MARK: - 기기 행: 스크린샷

  static var screenshotButton: String {
    String(localized: "스크린샷", bundle: .module)
  }

  static var screenshotHelp: String {
    String(localized: "기기 화면을 사진 폴더의 SimLauncher 폴더에 PNG 파일로 저장하고 Finder 에서 보여 줍니다", bundle: .module)
  }

  static var takingScreenshotLabel: String {
    String(localized: "스크린샷을 찍는 중…", bundle: .module)
  }

  /// 스크린샷 버튼이 막힌 이유 (툴팁).
  static func screenshotBlockReason(_ reason: AndroidAppActionBlockReason) -> String {
    switch reason {
    case .notBooted:
      String(localized: "켜진 기기에서만 스크린샷을 찍을 수 있습니다. 기기를 켠 뒤 다시 시도하세요", bundle: .module)
    case .unavailable:
      String(localized: "사용할 수 없는 기기에서는 스크린샷을 찍을 수 없습니다", bundle: .module)
    }
  }

  // MARK: - 기기 행: 녹화

  static var recordButton: String {
    String(localized: "녹화", bundle: .module)
  }

  static var recordHelp: String {
    String(localized: "기기 화면을 동영상 폴더의 SimLauncher 폴더에 녹화합니다. 중지하면 저장하고 Finder 에서 보여 줍니다", bundle: .module)
  }

  static var stopRecordingButton: String {
    String(localized: "중지", bundle: .module)
  }

  static var startingRecordingLabel: String {
    String(localized: "녹화를 시작하는 중…", bundle: .module)
  }

  static var recordingLabel: String {
    String(localized: "녹화 중", bundle: .module)
  }

  static var stoppingRecordingLabel: String {
    String(localized: "녹화를 저장하는 중…", bundle: .module)
  }

  /// 녹화 버튼이 막힌 이유 (툴팁). 기기 규칙은 스크린샷과 같다.
  static func recordBlockReason(_ reason: AndroidAppActionBlockReason) -> String {
    switch reason {
    case .notBooted:
      String(localized: "켜진 기기에서만 녹화할 수 있습니다. 기기를 켠 뒤 다시 시도하세요", bundle: .module)
    case .unavailable:
      String(localized: "사용할 수 없는 기기에서는 녹화할 수 없습니다", bundle: .module)
    }
  }

  /// 녹화 중 끄기 버튼 도움말.
  static var stopRecordingFirstHelp: String {
    String(localized: "녹화를 먼저 멈추세요", bundle: .module)
  }

  /// 녹화 중 기기 작업 메뉴 맨 위에 보일 이유.
  static var recordingBlocksDeviceActions: String {
    String(localized: "녹화 중에는 끄거나 초기화·삭제할 수 없습니다. 녹화를 먼저 멈추세요", bundle: .module)
  }

  // MARK: - 알림

  /// 스크린샷·녹화 알림의 제목. `title(for:)` 가 일곱 케이스를 한 줄로 넘긴다 (다른 알림이면 빈 문자열, 쓰이지 않는다).
  static func captureNoticeTitle(for notice: AndroidDevicesNotice?) -> String {
    switch notice {
    case let .screenshotFailed(device, _):
      let label = self.label(device)
      return String(localized: "\(label) 기기의 스크린샷을 저장하지 못했습니다", bundle: .module)
    case let .screenshotRevealFailed(device, _):
      let label = self.label(device)
      return String(localized: "\(label) 기기의 스크린샷을 저장했지만 Finder 에서 보여 주지 못했습니다", bundle: .module)
    case let .recordingFailed(device, .emulator(.recordingLost)):
      let label = self.label(device)
      return String(localized: "\(label) 기기가 꺼지거나 연결이 끊겨 녹화를 저장하지 못했습니다", bundle: .module)
    case let .recordingFailed(device, _):
      let label = self.label(device)
      return String(localized: "\(label) 기기의 화면을 녹화하지 못했습니다", bundle: .module)
    case let .recordingInterrupted(device):
      let label = self.label(device)
      return String(localized: "\(label) 기기의 녹화가 중간에 끝났습니다", bundle: .module)
    case let .recordingStoppedByDevice(device):
      let label = self.label(device)
      return String(localized: "\(label) 기기가 꺼져 녹화를 멈추고 저장했습니다", bundle: .module)
    case let .recordingAtTimeLimit(device):
      let label = self.label(device)
      return String(localized: "\(label) 기기의 녹화가 3분 제한에 닿아 멈추고 저장했습니다", bundle: .module)
    case let .recordingRevealFailed(device, _):
      let label = self.label(device)
      return String(localized: "\(label) 기기의 녹화를 저장했지만 Finder 에서 보여 주지 못했습니다", bundle: .module)
    default:
      return ""
    }
  }

  /// 스크린샷·녹화 알림의 본문. `message(for:)` 가 일곱 케이스를 한 줄로 넘긴다 (다른 알림이면 빈 문자열, 쓰이지 않는다).
  static func captureNoticeMessage(for notice: AndroidDevicesNotice) -> String {
    switch notice {
    case let .screenshotFailed(_, failure):
      self.screenshotMessage(for: failure)
    case let .screenshotRevealFailed(_, error):
      self.screenshotMessage(for: error)
    case let .recordingFailed(_, failure):
      self.recordingMessage(for: failure)
    case .recordingInterrupted:
      String(
        localized: """
        끝난 데까지 동영상 폴더의 SimLauncher 폴더에 저장했습니다. \
        기기의 저장 공간이 남아 있는지, 기기가 켜져 있는지 확인한 뒤 다시 녹화하세요.
        """,
        bundle: .module
      )
    case .recordingStoppedByDevice:
      String(
        localized: """
        꺼지기 전까지 녹화한 화면을 동영상 폴더의 SimLauncher 폴더에 저장했습니다. \
        다시 녹화하려면 기기를 켠 뒤 녹화를 누르세요.
        """,
        bundle: .module
      )
    case .recordingAtTimeLimit:
      String(
        localized: """
        이 기기의 Android 버전은 한 번에 3분까지만 녹화할 수 있어 그때까지 녹화한 화면을 동영상 폴더의 SimLauncher 폴더에 \
        저장했습니다. 이어서 녹화하려면 녹화를 다시 누르세요.
        """,
        bundle: .module
      )
    case let .recordingRevealFailed(_, error):
      self.recordingMessage(for: error)
    default:
      ""
    }
  }

  static func screenshotMessage(for failure: AndroidCaptureFailure) -> String {
    switch failure {
    case let .workspace(error):
      self.screenshotMessage(for: error)
    case .emulator(.deviceNotBooted):
      // 앱 작업 문구("…하지 못했습니다")가 아니라 스크린샷 문구로 알린다.
      String(localized: "기기가 켜져 있지 않아 스크린샷을 찍지 못했습니다. 기기를 켠 뒤 다시 시도하세요.", bundle: .module)
    case let .emulator(error):
      self.message(for: error) ?? ""
    }
  }

  static func recordingMessage(for failure: AndroidCaptureFailure) -> String {
    switch failure {
    case let .workspace(error):
      self.recordingMessage(for: error)
    case .emulator(.deviceNotBooted):
      // 앱 작업 문구가 아니라 녹화 문구로 알린다.
      String(localized: "기기가 켜져 있지 않아 녹화하지 못했습니다. 기기를 켠 뒤 다시 시도하세요.", bundle: .module)
    case .emulator(.captureFileUnwritable):
      // 녹화는 기기 안에 남아 있다가 그 기기에서 다음 녹화를 시작할 때 지워진다 (AndroidEmulator Client).
      String(
        localized: """
        동영상 폴더의 SimLauncher 폴더에 녹화 파일을 쓰지 못했습니다. Mac 의 디스크 공간이 남아 있는지 확인한 뒤 다시 녹화하세요. \
        이번 녹화는 기기 안에 남아 있다가 이 기기에서 다음에 녹화를 시작할 때 지워집니다.
        """,
        bundle: .module
      )
    case let .emulator(error):
      self.message(for: error) ?? ""
    }
  }

  /// 스크린샷·녹화 명령의 실패 본문. 다른 분류면 nil. `message(for: AndroidEmulatorError)` 가 넘긴다.
  /// 예약 파일에 쓰지 못한 것(`.captureFileUnwritable`)은 스크린샷 문구이고, 녹화는 `recordingMessage(for:)` 가 따로 고른다.
  static func captureMessage(for error: AndroidEmulatorError) -> String? {
    switch error {
    case .captureFailed:
      String(
        localized: "기기 화면을 읽지 못했습니다. 기기가 켜져 있는지 확인하고, 계속 실패하면 기기를 껐다 켠 뒤 다시 시도하세요.",
        bundle: .module
      )
    case .captureFileUnwritable:
      String(
        localized: "사진 폴더의 SimLauncher 폴더에 스크린샷 파일을 쓰지 못했습니다. 디스크 공간이 남아 있는지 확인한 뒤 다시 시도하세요.",
        bundle: .module
      )
    case .recordingFailed:
      String(
        localized: "녹화를 시작하지 못했습니다. 기기의 저장 공간이 남아 있는지 확인하고, 계속 실패하면 기기를 껐다 켠 뒤 다시 시도하세요.",
        bundle: .module
      )
    case .recordingEmpty:
      String(
        localized: """
        녹화된 화면이 없어 파일을 저장하지 못했습니다. \
        기기가 켜져 있는지 확인하고, 계속 실패하면 기기를 껐다 켠 뒤 다시 시도하세요.
        """,
        bundle: .module
      )
    case .recordingLost:
      String(
        localized: "녹화 중에 기기가 꺼지거나 연결이 끊겨 녹화한 화면을 가져오지 못했습니다. 다시 녹화하려면 기기를 켠 뒤 녹화를 누르세요.",
        bundle: .module
      )
    case .recordingTransferTimedOut:
      String(
        localized: """
        녹화 파일을 가져오는 데 너무 오래 걸려 멈췄습니다. 기기가 켜져 있는지, Mac 의 디스크 공간이 남아 있는지 확인한 뒤 \
        다시 녹화하세요. 이번 녹화는 기기 안에 남아 있다가 이 기기에서 다음에 녹화를 시작할 때 지워집니다.
        """,
        bundle: .module
      )
    default:
      nil
    }
  }
}
