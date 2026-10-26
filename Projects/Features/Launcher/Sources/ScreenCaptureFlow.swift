import Core
import Foundation
import SimulatorInterface
import WorkspaceInterface

/// 화면 캡처 흐름(스크린샷): 파일 이름 만들기 → 저장 파일 예약 → 찍기 → (실패면 빈 예약 파일 지우기·알림·다시 읽기)
/// → Finder 에서 보이기.
/// `LauncherModel` 이 `private` 으로 소유하고, 기기별 캡처 기록(`screenshots`)을 시작한 Model 메서드 안에서만 부른다.
/// Model 상태를 직접 바꾸지 않는다. Client 는 직접 부르고, Model 상태에는 부를 때 넘겨받는 `Host` 창구로만 닿는다.
/// 모든 실패가 안에서 알림으로 끝나 던지지 않는다.
@MainActor
struct ScreenCaptureFlow {
  /// Model 이 부를 때마다 만들어 넘기는 창구. Model 을 잡으므로 저장하지 않는다.
  struct Host {
    /// 알림을 쌓는다.
    let enqueue: @MainActor (LauncherNotice) -> Void
    /// 목록을 다시 읽는다 (읽는 중이면 그 읽기에 합쳐진다).
    let reload: @MainActor () async -> Void
  }

  let simulator: any SimulatorClient
  /// 저장 폴더 준비·이름 예약과 Finder 에서 보이기.
  let workspace: any WorkspaceClient
  /// 파일 이름의 시각. 테스트가 고정한다.
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
}
