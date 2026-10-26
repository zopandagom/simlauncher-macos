import Core
import Foundation
import SimulatorInterface
import Testing
import WorkspaceInterface
@testable import LauncherFeature

/// 녹화 문구.
struct RecordingTextTests {
  static let device = LauncherNotice.Device(name: "iPhone 17", runtimeName: "iOS 26.0")

  @Test("녹화 알림 제목에 기기 이름과 런타임 이름이 들어가고, 케이스마다 녹화 제목을 고른다")
  func noticeTitles() {
    #expect(
      LauncherText.title(for: .recordingFailed(Self.device, .workspace(.folderUnavailable)))
        == "“iPhone 17” (iOS 26.0) 기기의 화면을 녹화하지 못했습니다"
    )
    #expect(
      LauncherText.title(for: .recordingFailed(Self.device, .simulator(.recordingInProgress)))
        == "“iPhone 17” (iOS 26.0) 기기의 화면을 녹화하지 못했습니다"
    )
    #expect(
      LauncherText.title(for: .recordingFailed(Self.device, .simulator(.recordingUnfinished)))
        == "“iPhone 17” (iOS 26.0) 기기의 녹화 저장을 마치지 못했습니다"
    )
    #expect(
      LauncherText.title(for: .recordingInterrupted(Self.device)) == "“iPhone 17” (iOS 26.0) 기기의 녹화가 중간에 끝났습니다"
    )
    #expect(
      LauncherText.title(for: .recordingStoppedByDevice(Self.device))
        == "“iPhone 17” (iOS 26.0) 기기가 꺼져 녹화를 멈추고 저장했습니다"
    )
    #expect(
      LauncherText.title(for: .recordingRevealFailed(Self.device, .fileNotFound))
        == "“iPhone 17” (iOS 26.0) 기기의 녹화를 저장했지만 Finder 에서 보여 주지 못했습니다"
    )
  }

  @Test("녹화 오류 본문: 다른 녹화가 있음·저장된 화면 없음·저장을 마치지 못함은 녹화 분류 문구다")
  func recordingErrorMessages() {
    let inProgress = LauncherText.message(for: RecordingFailure.simulator(.recordingInProgress))
    #expect(inProgress.contains("다른 도구(Xcode 등)가 이미 녹화하고 있습니다"))
    #expect(inProgress == LauncherText.message(for: SimulatorError.recordingInProgress))
    let empty = LauncherText.message(for: RecordingFailure.simulator(.recordingEmpty))
    #expect(empty.contains("녹화된 화면이 없어"))
    let unfinished = LauncherText.message(for: RecordingFailure.simulator(.recordingUnfinished))
    #expect(unfinished.contains("기기를 끄면 그때까지 녹화한 화면이"))
    // 다른 문맥(설치)으로 새도 같은 문구다.
    #expect(LauncherText.message(for: AppInstallFailure.simulator(.recordingEmpty)) == empty)
  }

  @Test("꺼진 기기·명령 실패 본문은 설치·일반 문구가 아니라 녹화 문구이고, 그 밖의 오류는 오류 분류 문구다")
  func contextualSimulatorMessages() {
    let notBooted = LauncherText.message(for: RecordingFailure.simulator(.deviceNotBooted))
    #expect(notBooted == "기기가 켜져 있지 않아 녹화하지 못했습니다. 기기를 켠 뒤 다시 시도하세요.")
    #expect(notBooted != LauncherText.message(for: SimulatorError.deviceNotBooted))
    let commandFailed = LauncherText.message(for: RecordingFailure.simulator(.commandFailed))
    #expect(commandFailed.hasPrefix("녹화를 시작하지 못했습니다."))
    #expect(commandFailed != LauncherText.message(for: SimulatorError.commandFailed))
    for error in LauncherTextCatalog.errors where error != .deviceNotBooted && error != .commandFailed {
      #expect(
        LauncherText.message(for: RecordingFailure.simulator(error)) == LauncherText.message(for: error),
        "\(error)"
      )
    }
  }

  @Test("저장 폴더 본문은 동영상 폴더 문구이고 스크린샷(사진 폴더) 문구와 다르며, 알림 본문도 같다")
  func workspaceFailureMessages() {
    for error in LauncherTextCatalog.workspaceErrors {
      let message = LauncherText.recordingMessage(for: error)
      #expect(message.contains("동영상 폴더"), "\(error)")
      #expect(!message.contains("사진 폴더"), "\(error)")
      #expect(message != LauncherText.message(for: error), "\(error)")
      #expect(LauncherText.message(for: RecordingFailure.workspace(error)) == message)
      #expect(LauncherText.message(for: .recordingFailed(Self.device, .workspace(error))) == message)
      #expect(LauncherText.message(for: .recordingRevealFailed(Self.device, error)) == message)
    }
  }

  @Test("중간에 끝남·기기 꺼짐 본문은 저장했다고 알리고 다음 할 일을 안내한다")
  func savedNoticeMessages() {
    let interrupted = LauncherText.message(for: .recordingInterrupted(Self.device))
    #expect(interrupted.hasPrefix("끝난 데까지 동영상 폴더의 SimLauncher 폴더에 저장했습니다."))
    let stopped = LauncherText.message(for: .recordingStoppedByDevice(Self.device))
    #expect(stopped.hasPrefix("꺼지기 전까지 녹화한 화면을 동영상 폴더의 SimLauncher 폴더에 저장했습니다."))
    #expect(interrupted != stopped)
  }

  @Test("행·종료 확인 문구가 서로 다르고 비어 있지 않다")
  func rowAndTerminationTexts() {
    var texts = [
      LauncherText.recordButton, LauncherText.recordHelp, LauncherText.stopRecordingButton,
      LauncherText.startingRecordingLabel, LauncherText.recordingLabel, LauncherText.stoppingRecordingLabel,
      LauncherText.stopRecordingFirstHelp, LauncherText.recordingBlocksDeviceActions,
      LauncherText.recordingTerminationTitle, LauncherText.recordingTerminationMessage, LauncherText.saveAndQuitButton,
    ]
    texts += LauncherTextCatalog.screenshotBlockReasons.map { LauncherText.recordBlockReason($0) }
    #expect(Set(texts).count == texts.count)
    for text in texts {
      #expect(!text.isEmpty)
    }
    // 녹화 버튼이 막힌 이유는 스크린샷 문구가 아니다.
    for reason in LauncherTextCatalog.screenshotBlockReasons {
      #expect(LauncherText.recordBlockReason(reason) != LauncherText.screenshotBlockReason(reason))
    }
  }
}
