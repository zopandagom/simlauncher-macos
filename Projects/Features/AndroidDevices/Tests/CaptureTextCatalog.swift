import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Foundation
import WorkspaceInterface
@testable import AndroidDevicesFeature

/// 스크린샷·녹화 문구(`AndroidDevicesText+Capture.swift`)의 String Catalog 키. `DownloadTextCatalog` 와 같은 방식으로
/// `AndroidDevicesResourcesTests` 는 이 모듈의 컴파일된 표로 모든 키를, `LauncherTextSyncTests` 는 Launcher 원본 표로 공유 키를 본다.
enum CaptureTextCatalog {
  typealias Check = DownloadTextCatalog.Check

  static let device = AndroidDeviceLabel(.bootedTabletSample)

  /// iOS 기기 목록(Launcher)의 `LauncherText+Screenshot`·`+Recording` 과 같은 키·값으로 둔 문구.
  static func sharedChecks(_ table: [String: String]) -> [Check] {
    var pairs: [(String, String)] = [
      ("스크린샷", AndroidDevicesText.screenshotButton),
      ("기기 화면을 사진 폴더의 SimLauncher 폴더에 PNG 파일로 저장하고 Finder 에서 보여 줍니다", AndroidDevicesText.screenshotHelp),
      ("스크린샷을 찍는 중…", AndroidDevicesText.takingScreenshotLabel),
      (
        "켜진 기기에서만 스크린샷을 찍을 수 있습니다. 기기를 켠 뒤 다시 시도하세요",
        AndroidDevicesText.screenshotBlockReason(.notBooted)
      ),
      ("사용할 수 없는 기기에서는 스크린샷을 찍을 수 없습니다", AndroidDevicesText.screenshotBlockReason(.unavailable)),
      ("녹화", AndroidDevicesText.recordButton),
      ("기기 화면을 동영상 폴더의 SimLauncher 폴더에 녹화합니다. 중지하면 저장하고 Finder 에서 보여 줍니다", AndroidDevicesText.recordHelp),
      ("중지", AndroidDevicesText.stopRecordingButton),
      ("녹화를 시작하는 중…", AndroidDevicesText.startingRecordingLabel),
      ("녹화 중", AndroidDevicesText.recordingLabel),
      ("녹화를 저장하는 중…", AndroidDevicesText.stoppingRecordingLabel),
      ("켜진 기기에서만 녹화할 수 있습니다. 기기를 켠 뒤 다시 시도하세요", AndroidDevicesText.recordBlockReason(.notBooted)),
      ("사용할 수 없는 기기에서는 녹화할 수 없습니다", AndroidDevicesText.recordBlockReason(.unavailable)),
      ("녹화를 먼저 멈추세요", AndroidDevicesText.stopRecordingFirstHelp),
      ("녹화 중에는 끄거나 초기화·삭제할 수 없습니다. 녹화를 먼저 멈추세요", AndroidDevicesText.recordingBlocksDeviceActions),
      (
        "기기가 켜져 있지 않아 스크린샷을 찍지 못했습니다. 기기를 켠 뒤 다시 시도하세요.",
        AndroidDevicesText.screenshotMessage(for: .emulator(.deviceNotBooted))
      ),
      (
        "기기가 켜져 있지 않아 녹화하지 못했습니다. 기기를 켠 뒤 다시 시도하세요.",
        AndroidDevicesText.recordingMessage(for: .emulator(.deviceNotBooted))
      ),
      (
        "녹화된 화면이 없어 파일을 저장하지 못했습니다. 기기가 켜져 있는지 확인하고, 계속 실패하면 기기를 껐다 켠 뒤 다시 시도하세요.",
        AndroidDevicesText.captureMessage(for: .recordingEmpty) ?? ""
      ),
      (
        "꺼지기 전까지 녹화한 화면을 동영상 폴더의 SimLauncher 폴더에 저장했습니다. 다시 녹화하려면 기기를 켠 뒤 녹화를 누르세요.",
        AndroidDevicesText.message(for: .recordingStoppedByDevice(self.device))
      ),
    ]
    pairs += self.folderPairs
    return pairs.map { DownloadTextCatalog.check(table, $0.0, $0.1) }
  }

  /// 저장 폴더(사진·동영상) 실패 문구 여섯.
  private static var folderPairs: [(String, String)] {
    [
      (
        """
        사진 폴더 안에 SimLauncher 폴더를 만들거나 그 안에 파일을 쓸 수 없습니다. \
        Finder 에서 사진 폴더에 SimLauncher 라는 이름의 파일이 있지 않은지, 디스크 공간이 남아 있는지 확인한 뒤 다시 시도하세요.
        """,
        AndroidDevicesText.screenshotMessage(for: WorkspaceError.folderUnavailable)
      ),
      (
        """
        같은 이름의 스크린샷이 너무 많아 새 파일 이름을 정하지 못했습니다. \
        사진 폴더의 SimLauncher 폴더에서 이전 스크린샷을 다른 곳으로 옮긴 뒤 다시 시도하세요.
        """,
        AndroidDevicesText.screenshotMessage(for: WorkspaceError.fileNameUnavailable)
      ),
      (
        """
        저장한 스크린샷 파일을 찾지 못했습니다. 파일이 옮겨지거나 지워졌을 수 있습니다. \
        Finder 에서 사진 폴더의 SimLauncher 폴더를 열어 확인하세요.
        """,
        AndroidDevicesText.screenshotMessage(for: WorkspaceError.fileNotFound)
      ),
      (
        """
        동영상 폴더 안에 SimLauncher 폴더를 만들거나 그 안에 파일을 쓸 수 없습니다. \
        Finder 에서 동영상 폴더에 SimLauncher 라는 이름의 파일이 있지 않은지, 디스크 공간이 남아 있는지 확인한 뒤 다시 시도하세요.
        """,
        AndroidDevicesText.recordingMessage(for: WorkspaceError.folderUnavailable)
      ),
      (
        """
        같은 이름의 녹화 파일이 너무 많아 새 파일 이름을 정하지 못했습니다. \
        동영상 폴더의 SimLauncher 폴더에서 이전 녹화 파일을 다른 곳으로 옮긴 뒤 다시 시도하세요.
        """,
        AndroidDevicesText.recordingMessage(for: WorkspaceError.fileNameUnavailable)
      ),
      (
        """
        저장한 녹화 파일을 찾지 못했습니다. 파일이 옮겨지거나 지워졌을 수 있습니다. \
        Finder 에서 동영상 폴더의 SimLauncher 폴더를 열어 확인하세요.
        """,
        AndroidDevicesText.recordingMessage(for: WorkspaceError.fileNotFound)
      ),
    ]
  }

  /// Android 문장 (기기 라벨을 넣는 알림 제목 여덟, 기기 안에서 녹화해 가져오는 데서 생기는 실패·정보 본문).
  static func androidChecks(_ table: [String: String]) -> [Check] {
    let displayOff = [
      "기기 화면이 꺼져 있어 녹화를 시작하지 못했습니다. ",
      "에뮬레이터 창에서 전원 버튼으로 화면을 켜거나, 접힌 기기는 펼친 뒤 다시 녹화하세요.",
    ].joined()
    let unwritable = [
      "동영상 폴더의 SimLauncher 폴더에 녹화 파일을 쓰지 못했습니다. Mac 의 디스크 공간이 남아 있는지 확인한 뒤 다시 녹화하세요. ",
      "이번 녹화는 기기 안에 남아 있다가 이 기기에서 다음에 녹화를 시작할 때 지워집니다.",
    ].joined()
    let timedOut = [
      "녹화 파일을 가져오는 데 너무 오래 걸려 멈췄습니다. 기기가 켜져 있는지, Mac 의 디스크 공간이 남아 있는지 확인한 뒤 ",
      "다시 녹화하세요. 이번 녹화는 기기 안에 남아 있다가 이 기기에서 다음에 녹화를 시작할 때 지워집니다.",
    ].joined()
    let timeLimit = [
      "이 기기의 Android 버전은 한 번에 3분까지만 녹화할 수 있어 그때까지 녹화한 화면을 동영상 폴더의 SimLauncher 폴더에 ",
      "저장했습니다. 이어서 녹화하려면 녹화를 다시 누르세요.",
    ].joined()
    let bodies: [(String, String)] = [
      (
        "기기 화면을 읽지 못했습니다. 기기가 켜져 있는지 확인하고, 계속 실패하면 기기를 껐다 켠 뒤 다시 시도하세요.",
        AndroidDevicesText.screenshotMessage(for: .emulator(.captureFailed))
      ),
      (
        "사진 폴더의 SimLauncher 폴더에 스크린샷 파일을 쓰지 못했습니다. 디스크 공간이 남아 있는지 확인한 뒤 다시 시도하세요.",
        AndroidDevicesText.screenshotMessage(for: .emulator(.captureFileUnwritable))
      ),
      (
        "녹화를 시작하지 못했습니다. 기기의 저장 공간이 남아 있는지 확인하고, 계속 실패하면 기기를 껐다 켠 뒤 다시 시도하세요.",
        AndroidDevicesText.recordingMessage(for: .emulator(.recordingFailed))
      ),
      (
        "녹화 중에 기기가 꺼지거나 연결이 끊겨 녹화한 화면을 가져오지 못했습니다. 다시 녹화하려면 기기를 켠 뒤 녹화를 누르세요.",
        AndroidDevicesText.recordingMessage(for: .emulator(.recordingLost))
      ),
      (displayOff, AndroidDevicesText.recordingMessage(for: .emulator(.recordingDisplayOff))),
      (unwritable, AndroidDevicesText.recordingMessage(for: .emulator(.captureFileUnwritable))),
      (timedOut, AndroidDevicesText.recordingMessage(for: .emulator(.recordingTransferTimedOut))),
      (timeLimit, AndroidDevicesText.message(for: .recordingAtTimeLimit(self.device))),
      (
        "끝난 데까지 동영상 폴더의 SimLauncher 폴더에 저장했습니다. 기기의 저장 공간이 남아 있는지, 기기가 켜져 있는지 확인한 뒤 다시 녹화하세요.",
        AndroidDevicesText.message(for: .recordingInterrupted(self.device))
      ),
    ]
    return self.androidTitleChecks(table) + bodies.map { DownloadTextCatalog.check(table, $0.0, $0.1) }
  }

  /// Android 알림 제목 여덟 (기기 라벨을 넣는다).
  private static func androidTitleChecks(_ table: [String: String]) -> [Check] {
    let label = AndroidDevicesText.label(self.device)
    let titles: [(String, AndroidDevicesNotice)] = [
      ("%@ 기기의 스크린샷을 저장하지 못했습니다", .screenshotFailed(self.device, .emulator(.captureFailed))),
      ("%@ 기기의 스크린샷을 저장했지만 Finder 에서 보여 주지 못했습니다", .screenshotRevealFailed(self.device, .fileNotFound)),
      ("%@ 기기가 꺼지거나 연결이 끊겨 녹화를 저장하지 못했습니다", .recordingFailed(self.device, .emulator(.recordingLost))),
      ("%@ 기기의 화면을 녹화하지 못했습니다", .recordingFailed(self.device, .emulator(.recordingFailed))),
      ("%@ 기기의 녹화가 중간에 끝났습니다", .recordingInterrupted(self.device)),
      ("%@ 기기가 꺼져 녹화를 멈추고 저장했습니다", .recordingStoppedByDevice(self.device)),
      ("%@ 기기의 녹화가 3분 제한에 닿아 멈추고 저장했습니다", .recordingAtTimeLimit(self.device)),
      ("%@ 기기의 녹화를 저장했지만 Finder 에서 보여 주지 못했습니다", .recordingRevealFailed(self.device, .fileNotFound)),
    ]
    return titles.map { DownloadTextCatalog.check(table, $0.0, AndroidDevicesText.title(for: $0.1), label) }
  }
}
