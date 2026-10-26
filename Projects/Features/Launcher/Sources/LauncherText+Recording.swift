import Core
import Foundation
import SimulatorInterface
import WorkspaceInterface

/// 녹화 문구. 키는 다른 문구와 같은 `Localizable.xcstrings` 에 있다.
extension LauncherText {
  // MARK: - 기기 행

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
  static func recordBlockReason(_ reason: ScreenshotBlockReason) -> String {
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

  // MARK: - 앱 종료 확인

  static var recordingTerminationTitle: String {
    String(localized: "녹화를 멈추고 저장한 뒤 종료할까요?", bundle: .module)
  }

  static var recordingTerminationMessage: String {
    String(localized: "녹화 중인 기기의 화면을 동영상 폴더의 SimLauncher 폴더에 저장하고 앱을 종료합니다.", bundle: .module)
  }

  static var saveAndQuitButton: String {
    String(localized: "저장하고 종료", bundle: .module)
  }

  // MARK: - 알림

  /// 녹화 알림의 제목. `rowTaskNoticeTitle(for:device:)` 가 녹화 네 케이스를 넘긴다.
  static func recordingNoticeTitle(for notice: LauncherNotice?, device: LauncherNotice.Device) -> String {
    switch notice {
    case .recordingFailed(_, .simulator(.recordingUnfinished)):
      // 실패로 단정하지 않는다: 기기를 끄면 서비스가 같은 파일에 마무리한다 (본문이 안내한다).
      String(localized: "“\(device.name)” (\(device.runtimeName)) 기기의 녹화 저장을 마치지 못했습니다", bundle: .module)
    case .recordingInterrupted:
      String(localized: "“\(device.name)” (\(device.runtimeName)) 기기의 녹화가 중간에 끝났습니다", bundle: .module)
    case .recordingStoppedByDevice:
      String(localized: "“\(device.name)” (\(device.runtimeName)) 기기가 꺼져 녹화를 멈추고 저장했습니다", bundle: .module)
    case .recordingRevealFailed:
      String(
        localized: "“\(device.name)” (\(device.runtimeName)) 기기의 녹화를 저장했지만 Finder 에서 보여 주지 못했습니다",
        bundle: .module
      )
    default:
      String(localized: "“\(device.name)” (\(device.runtimeName)) 기기의 화면을 녹화하지 못했습니다", bundle: .module)
    }
  }

  /// 녹화 알림의 본문. `message(for: LauncherNotice)` 가 녹화 네 케이스를 넘긴다 (녹화가 아닌 알림이면 빈 문자열, 쓰이지 않는다).
  static func recordingNoticeMessage(for notice: LauncherNotice) -> String {
    switch notice {
    case let .recordingFailed(_, failure):
      self.message(for: failure)
    case .recordingInterrupted:
      String(
        localized: """
        끝난 데까지 동영상 폴더의 SimLauncher 폴더에 저장했습니다. \
        디스크 공간이 남아 있는지, 기기가 켜져 있는지 확인한 뒤 다시 녹화하세요.
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
    case let .recordingRevealFailed(_, error):
      self.recordingMessage(for: error)
    default:
      ""
    }
  }

  static func message(for failure: RecordingFailure) -> String {
    switch failure {
    case let .workspace(error):
      self.recordingMessage(for: error)
    case .simulator(.deviceNotBooted):
      // 설치·실행 문구("앱 설치·실행이나…")가 아니라 녹화 문구로 알린다.
      String(localized: "기기가 켜져 있지 않아 녹화하지 못했습니다. 기기를 켠 뒤 다시 시도하세요.", bundle: .module)
    case .simulator(.commandFailed):
      // 원인이 폴더·디스크 쪽이라 "개발 환경 확인·Mac 재시동" 일반 문구를 쓰지 않는다.
      String(
        localized: """
        녹화를 시작하지 못했습니다. 동영상 폴더의 SimLauncher 폴더에 쓸 수 있는지, 디스크 공간이 남아 있는지 확인한 뒤 \
        다시 시도하세요. 계속 실패하면 기기를 껐다 켠 뒤 다시 시도하세요.
        """,
        bundle: .module
      )
    case let .simulator(error):
      self.message(for: error)
    }
  }

  /// 녹화 명령의 실패. 다른 분류면 nil. 설치·링크 같은 다른 문맥으로 새도 이 문구다.
  static func recordingMessage(for error: SimulatorError) -> String? {
    switch error {
    case .recordingInProgress:
      String(
        localized: """
        이 기기를 다른 도구(Xcode 등)가 이미 녹화하고 있습니다. 그 녹화를 멈춘 뒤 다시 시도하세요. \
        앞선 녹화가 제대로 끝나지 않았다면 기기를 껐다 켠 뒤 다시 시도하세요.
        """,
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
    case .recordingUnfinished:
      String(
        localized: """
        녹화 저장이 늦어져 끝나지 않았습니다. 기기를 끄면 그때까지 녹화한 화면이 동영상 폴더의 SimLauncher 폴더의 \
        같은 파일에 저장됩니다. 기기를 다시 켜면 다시 녹화할 수 있습니다. 녹화된 화면이 없었다면 빈 파일이 남습니다.
        """,
        bundle: .module
      )
    case .developerToolsUnavailable, .deviceNotFound, .deviceNotShutdown, .creationOptionUnavailable,
         .invalidDeviceName, .simulatorAppNotFound, .unexpectedOutput, .creationResultUnknown, .commandFailed,
         .deviceNotBooted, .appNotFound, .appInvalid, .appIncompatible, .appRequiresNewerOS, .appNotInstalled,
         .appLaunchFailed, .urlNotHandled, .invalidURL:
      nil
    }
  }

  /// 녹화 저장 폴더(동영상 폴더) 문구. 스크린샷의 `message(for: WorkspaceError)` 와 같은 원인이고 폴더·파일 이름만 다르다.
  static func recordingMessage(for error: WorkspaceError) -> String {
    switch error {
    case .folderUnavailable:
      String(
        localized: """
        동영상 폴더 안에 SimLauncher 폴더를 만들거나 그 안에 파일을 쓸 수 없습니다. \
        Finder 에서 동영상 폴더에 SimLauncher 라는 이름의 파일이 있지 않은지, 디스크 공간이 남아 있는지 확인한 뒤 다시 시도하세요.
        """,
        bundle: .module
      )
    case .fileNameUnavailable:
      String(
        localized: """
        같은 이름의 녹화 파일이 너무 많아 새 파일 이름을 정하지 못했습니다. \
        동영상 폴더의 SimLauncher 폴더에서 이전 녹화 파일을 다른 곳으로 옮긴 뒤 다시 시도하세요.
        """,
        bundle: .module
      )
    case .fileNotFound:
      String(
        localized: """
        저장한 녹화 파일을 찾지 못했습니다. 파일이 옮겨지거나 지워졌을 수 있습니다. \
        Finder 에서 동영상 폴더의 SimLauncher 폴더를 열어 확인하세요.
        """,
        bundle: .module
      )
    }
  }
}
