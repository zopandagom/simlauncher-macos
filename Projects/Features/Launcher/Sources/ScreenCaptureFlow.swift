import Core
import Foundation
import SimulatorInterface
import WorkspaceInterface

/// 화면 캡처 흐름(스크린샷·녹화): 파일 이름 만들기 → 저장 파일 예약 → 찍기·녹화 → (실패면 빈 예약 파일 지우기·알림·다시 읽기)
/// → Finder 에서 보이기.
/// `LauncherModel` 이 `private` 으로 소유하고, 기기별 캡처 기록(`screenshots`·`recordings`)을 시작한 Model 메서드(녹화는 그 메서드가
/// 만들어 Model 이 소유한 Task) 안에서만 부른다.
/// Model 상태를 직접 바꾸지 않는다. Client 는 직접 부르고, Model 상태에는 부를 때 넘겨받는 `Host` 창구로만 닿는다.
/// 모든 실패가 안에서 알림으로 끝나 던지지 않는다.
/// 녹화를 멈추는 것은 녹화 Task 취소이고, 취소에 반응하는 곳은 `recordVideo` 안뿐이다. 예약·지우기·Finder 보이기·다시 읽기는
/// 취소를 보지 않아 멈춘 뒤에도 저장 뒤 정리가 끝까지 돈다. 그래서 이 흐름에 취소를 보는 await(`Task.sleep`·
/// `Task.checkCancellation`)를 넣지 않는다.
@MainActor
struct ScreenCaptureFlow {
  /// Model 이 부를 때마다 만들어 넘기는 창구. Model 을 잡으므로 저장하지 않는다.
  struct Host {
    /// 알림을 쌓는다.
    let enqueue: @MainActor (LauncherNotice) -> Void
    /// 목록을 다시 읽는다 (읽는 중이면 그 읽기에 합쳐진다).
    let reload: @MainActor () async -> Void
    /// 녹화 시작 신호를 받은 시각을 기록한다 (Simulator Client 의 `onStarted` 에서 부르므로 Sendable).
    let recordingStarted: @MainActor @Sendable (VirtualDevice.ID, Date) -> Void
    /// 그 기기의 녹화를 멈춘 이유 (부르는 순간의 값). 흐름 끝에서 알림을 고른다.
    let recordingStopReason: @MainActor (VirtualDevice.ID) -> RecordingStopReason?
  }

  let simulator: any SimulatorClient
  /// 저장 폴더 준비·이름 예약과 Finder 에서 보이기.
  let workspace: any WorkspaceClient
  /// 파일 이름의 시각과 녹화 시작 신호를 받은 시각(행 경과 시간의 기준). 테스트가 고정한다.
  let now: @Sendable () -> Date

  /// 켜진 기기 화면을 사진 폴더의 SimLauncher 폴더에 PNG 로 저장하고 Finder 에서 선택해 보인다.
  /// 촬영 명령이 실패하면 예약한 빈 파일을 지우고 알림 뒤 다시 읽는다 (예약 실패는 명령 전이라 다시 읽지 않는다).
  func takeScreenshot(of device: VirtualDevice, label: LauncherNotice.Device, host: Host) async {
    let name = ScreenshotFileName(
      deviceName: device.name, runtimeName: device.runtime.name, takenAt: self.now(), timeZone: .current
    )
    let file: URL
    do throws(WorkspaceError) {
      file = try await self.workspace.reserveScreenshotFile(name)
    } catch {
      host.enqueue(.screenshotFailed(label, .workspace(error)))
      return
    }
    // 기기가 그사이 꺼졌거나 사라졌으면 Client 가 실행 직전 목록으로 확인해 `.deviceNotBooted`·`.deviceNotFound` 로 끝난다.
    do throws(SimulatorError) {
      try await self.simulator.screenshot(on: device.id, to: file)
    } catch {
      await self.workspace.removeReservedFile(file)
      host.enqueue(.screenshotFailed(label, .simulator(error)))
      await host.reload()
      return
    }
    do throws(WorkspaceError) {
      try await self.workspace.revealInFinder(file)
    } catch {
      host.enqueue(.screenshotRevealFailed(label, error))
    }
  }

  /// 켜진 기기 화면을 동영상 폴더의 SimLauncher 폴더에 `.mov` 로 녹화하고, 멈추거나(호출한 Task 취소) 녹화가 스스로 끝나면 저장해
  /// Finder 에서 선택해 보인다.
  /// 저장되면 멈춘 이유가 기기 꺼짐일 때 정보 알림을 함께 띄운다. 시작 신호 전에 멈추면 알림 없이 빈 예약 파일을 지운다.
  /// simctl 이 스스로 실패로 끝났어도 화면이 남았으면 지우지 않고 보이며 알림 뒤 다시 읽는다. 그 밖의 실패는 빈 예약 파일을
  /// 지우고 알림 뒤 다시 읽는다 (`.recordingUnfinished` 는 기기를 끄면 서비스가 같은 파일에 마무리하므로 지우지 않는다).
  /// 예약 실패는 명령 전이라 다시 읽지 않는다.
  func record(_ device: VirtualDevice, label: LauncherNotice.Device, host: Host) async {
    let name = RecordingFileName(
      deviceName: device.name, runtimeName: device.runtime.name, startedAt: self.now(), timeZone: .current
    )
    let file: URL
    do throws(WorkspaceError) {
      file = try await self.workspace.reserveRecordingFile(name)
    } catch {
      host.enqueue(.recordingFailed(label, .workspace(error)))
      return
    }
    // Host 를 통째로 Sendable 클로저에 잡지 않고 필요한 창구와 값만 잡는다.
    let started = host.recordingStarted
    let now = self.now
    let id = device.id
    let result: ScreenRecordingResult
    do throws(SimulatorError) {
      result = try await self.simulator.recordVideo(on: id, to: file) { await started(id, now()) }
    } catch {
      if error != .recordingUnfinished {
        await self.workspace.removeReservedFile(file)
      }
      host.enqueue(.recordingFailed(label, .simulator(error)))
      await host.reload()
      return
    }
    switch result {
    case .saved:
      await self.reveal(file, label: label, host: host)
      if host.recordingStopReason(id) == .deviceStopped {
        host.enqueue(.recordingStoppedByDevice(label))
      }
    case .savedAfterFailure:
      await self.reveal(file, label: label, host: host)
      host.enqueue(.recordingInterrupted(label))
      await host.reload()
    case .stoppedBeforeStart:
      await self.workspace.removeReservedFile(file)
    }
  }

  /// 저장한 녹화 파일을 Finder 에서 보인다. 실패하면 알림만 띄운다 (파일은 지우지 않는다).
  private func reveal(_ file: URL, label: LauncherNotice.Device, host: Host) async {
    do throws(WorkspaceError) {
      try await self.workspace.revealInFinder(file)
    } catch {
      host.enqueue(.recordingRevealFailed(label, error))
    }
  }
}
