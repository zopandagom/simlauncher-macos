import AppBundleTesting
import Core
import DownloadInterface
import DownloadTesting
import LauncherFeature
import SimulatorTesting
import SwiftUI

/// App 없이 Launcher 화면만 띄우는 데모 앱. Preview 도 여기에 둔다.
/// 실제 시뮬레이터 대신 Testing 모듈의 `SimulatorClientFake`(샘플 목록, 호출마다 1초 지연, 링크는 켜진 기기면
/// 어떤 링크든 열린 것으로 끝난다)와 `AppBundleClientFake`(어떤 파일을 골라도 샘플 앱, zip 도 1초 풀기 뒤 샘플 앱,
/// 1초 지연), `DownloadClientFake`(어떤 주소든 0.3초마다 48 MB 까지 진행을 알린 뒤 zip 을 받은 것으로 끝나고,
/// `AppBundleClientFake` 가 그 zip 을 샘플 앱으로 푼다)를 주입한다. Setup 화면이 없으므로 Setup 진입 버튼("개발 환경"·"iOS 설치"·"다른 iOS 버전 설치"·
/// "개발 환경 열기")은 눌러도 아무 일도 하지 않는다.
@main
struct LauncherFeatureExampleApp: App {
  @State private var model = Self.makeModel()

  var body: some Scene {
    WindowGroup {
      LauncherView(model: self.model)
    }
  }

  private static func makeModel() -> LauncherModel {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.setDelay(.seconds(1))
    let appBundle = AppBundleClientFake()
    appBundle.setDelay(.seconds(1))
    let download = DownloadClientFake()
    download.setDownloadScript(progress: DownloadProgress.example, result: nil)
    download.setDelay(.milliseconds(300))
    return LauncherModel(simulator: fake, appBundle: appBundle, download: download)
  }
}

extension DownloadProgress {
  /// 48 MB 를 4.8 MB 씩 받는 진행 (Example·프리뷰가 행의 바이트·진행 막대를 보이게).
  static let example: [DownloadProgress] = (0 ... 10).map { (step: Int64) -> DownloadProgress in
    DownloadProgress(receivedBytes: step * 4_800_000, expectedBytes: 48_000_000)
  }
}

/// Fake 를 만들어 설정한 뒤 화면을 만든다.
@MainActor
private func previewLauncher(
  _ inventory: DeviceInventory = .sample,
  configure: (SimulatorClientFake) -> Void = { _ in },
  appBundle configureAppBundle: (AppBundleClientFake) -> Void = { _ in },
  download configureDownload: (DownloadClientFake) -> Void = { _ in }
) -> LauncherView {
  let fake = SimulatorClientFake(inventory: inventory)
  configure(fake)
  let appBundle = AppBundleClientFake()
  configureAppBundle(appBundle)
  let download = DownloadClientFake()
  download.setDownloadScript(progress: DownloadProgress.example, result: nil)
  download.setDelay(.milliseconds(300))
  configureDownload(download)
  return LauncherView(model: LauncherModel(simulator: fake, appBundle: appBundle, download: download))
}

#Preview("목록") {
  previewLauncher()
}

#Preview("불러오는 중") {
  previewLauncher { $0.suspendFetches() }
}

#Preview("불러오기 실패 (다시 시도·개발 환경 열기 버튼)") {
  previewLauncher { $0.setFetchError(.developerToolsUnavailable) }
}

#Preview("런타임 없음 (iOS 설치 버튼)") {
  previewLauncher(.noRuntime)
}

#Preview("기기 없음") {
  previewLauncher(.noDevices)
}

#Preview("만들 수 있는 기기 종류 없음 (다른 iOS 버전 설치 버튼)") {
  previewLauncher(.noCreatableDeviceType)
}

#Preview("기기는 있지만 만들 수 없음 (안내 줄의 다른 iOS 버전 설치 버튼)") {
  previewLauncher(
    DeviceInventory(devices: DeviceInventory.sample.devices, runtimes: DeviceInventory.sample.runtimes, deviceTypes: [])
  )
}

#Preview("켜기 실패 (꺼진 기기의 켜기를 누른다)") {
  previewLauncher { $0.setBootError(.commandFailed) }
}

/// 켜기 한 번으로 알림 두 개(켜기 실패 → 다시 읽기 실패)가 쌓인다.
/// 첫 목록을 읽은 뒤 1초가 지나면 목록 읽기도 실패하게 바꾼다.
#Preview("실패 알림 두 개 (1초 뒤 꺼진 기기의 켜기를 한 번 누른다)") {
  previewLauncher { fake in
    fake.setBootError(.commandFailed)
    Task {
      try? await Task.sleep(for: .seconds(1))
      fake.setFetchError(.commandFailed)
    }
  }
}

#Preview("실패 알림 두 개 (2초 안에 켜기와 끄기를 누른다)") {
  previewLauncher {
    $0.setBootError(.commandFailed)
    $0.setShutdownError(.deviceNotFound)
    $0.setDelay(.seconds(2))
  }
}

#Preview("만들기 실패 (+ → 만들기)") {
  previewLauncher { $0.setCreateError(.creationOptionUnavailable) }
}

#Preview("만드는 중 (+ → 만들기, 끝나지 않음)") {
  previewLauncher { $0.suspendCreates() }
}

#Preview("삭제 실패 (꺼진 기기의 … → 삭제…)") {
  previewLauncher { $0.setDeleteError(.deviceNotShutdown) }
}

#Preview("초기화 실패 (꺼진 기기의 … → 초기화…)") {
  previewLauncher { $0.setEraseError(.commandFailed) }
}

#Preview("앱 설치 (꺼진 기기의 앱 설치 → 파일에서 고르기…)") {
  previewLauncher { $0.setDelay(.seconds(1)) }
}

#Preview("설치 중 (앱 설치 → 파일에서 고르기…, 끝나지 않음)") {
  previewLauncher { $0.suspendInstalls() }
}

#Preview("거절: 기기용 빌드 (앱 설치 → 파일에서 고르기…)") {
  previewLauncher(appBundle: { $0.setInfo(.deviceBuild) })
}

#Preview("거절: 높은 iOS 필요 (앱 설치 → 파일에서 고르기…)") {
  previewLauncher(appBundle: { $0.setInfo(.requiring(OSVersion(major: 99))) })
}

#Preview("zip 에 .app 없음 (앱 설치 → 파일에서 고르기… → zip)") {
  previewLauncher(appBundle: { $0.setExtractError(.zipWithoutApp) })
}

#Preview("실행 실패 (앱 설치 → 파일에서 고르기…)") {
  previewLauncher { $0.setLaunchError(.appLaunchFailed) }
}

#Preview("링크 열기 (켜진·꺼진 기기의 링크 열기…)") {
  previewLauncher { $0.setDelay(.seconds(1)) }
}

#Preview("링크 여는 중 (링크 열기… → 열기, 끝나지 않음)") {
  previewLauncher { $0.suspendOpenURLs() }
}

#Preview("링크 열 앱 없음 (링크 열기… → 열기)") {
  previewLauncher { $0.setOpenURLError(.urlNotHandled) }
}

/// 설치가 3초 걸려 실패하는 동안 다른 기기의 링크 시트를 열어, 설치 실패 알림과 링크 시트가 함께 나와도 깨지지 않는지 본다.
#Preview("설치 실패 중 링크 시트 (한 기기의 앱 설치 → 파일에서 고르기… 뒤 다른 기기의 링크 열기…)") {
  previewLauncher {
    $0.setDelay(.seconds(3))
    $0.setInstallError(.appIncompatible)
  }
}

#Preview("URL 에서 설치 (앱 설치 → URL 에서… → 받아서 설치)") {
  previewLauncher()
}

/// 48 MB 중 19.2 MB 까지 진행을 알린 뒤 멈춰, 행의 받은 바이트·진행 막대와 취소 버튼이 남는다. 취소를 누르면 알림 없이 돌아온다.
#Preview("받는 중 (앱 설치 → URL 에서… → 받아서 설치, 끝나지 않음)") {
  previewLauncher(download: {
    $0.setDownloadScript(progress: Array(DownloadProgress.example.prefix(5)), result: nil)
    $0.suspendDownloads()
  })
}

#Preview("받기 실패: 파일 없음 404 (앱 설치 → URL 에서…)") {
  previewLauncher(download: { $0.setDownloadScript(progress: [], result: .failure(.httpStatus(404))) })
}

#Preview("받기 실패: 프록시 인증 407 (앱 설치 → URL 에서…)") {
  previewLauncher(download: { $0.setDownloadScript(progress: [], result: .failure(.httpStatus(407))) })
}

#Preview("받기 실패: 오프라인 (앱 설치 → URL 에서…)") {
  previewLauncher(download: { $0.setDownloadScript(progress: [], result: .failure(.offline)) })
}

/// 서버가 zip 대신 로그인 페이지(HTML)를 200 으로 준 경우: 풀기가 zip 으로 읽지 못하고, MIME 형식으로 웹 페이지 안내를 고른다.
#Preview("로그인 페이지를 받음 (앱 설치 → URL 에서…)") {
  previewLauncher(
    appBundle: { $0.setExtractError(.zipUnreadable) },
    download: { $0.setDownloadScript(progress: DownloadProgress.example, result: .success(.loginPage)) }
  )
}

#Preview("받은 zip 에 .app 없음 (앱 설치 → URL 에서…)") {
  previewLauncher(appBundle: { $0.setExtractError(.zipWithoutApp) })
}

extension DownloadedFile {
  /// 로그인 페이지 HTML 을 받은 결과. 파일은 만들지 않는다 (Fake 는 읽지 않는다).
  static let loginPage: DownloadedFile = {
    let folder = URL(filePath: "/tmp/SimLauncher-Download-Example-Login", directoryHint: .isDirectory)
    return DownloadedFile(
      file: folder.appending(path: "download", directoryHint: .notDirectory),
      folder: folder,
      byteCount: 2048,
      mimeType: "text/html"
    )
  }()
}
