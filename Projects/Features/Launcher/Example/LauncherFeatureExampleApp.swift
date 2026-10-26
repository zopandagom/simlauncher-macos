import AppBundleTesting
import Core
import DownloadInterface
import DownloadTesting
import Foundation
import LauncherFeature
import PreferencesInterface
import PreferencesTesting
import SimulatorTesting
import SwiftUI
import WorkspaceTesting

/// App 없이 Launcher 화면만 띄우는 데모 앱. Preview 도 여기에 둔다.
/// 실제 시뮬레이터 대신 Testing 모듈의 `SimulatorClientFake`(샘플 목록, 호출마다 1초 지연, 링크는 켜진 기기면
/// 어떤 링크든 열린 것으로 끝난다)와 `AppBundleClientFake`(어떤 파일을 골라도 샘플 앱, zip 도 1초 풀기 뒤 샘플 앱,
/// 1초 지연), `DownloadClientFake`(어떤 주소든 0.3초마다 48 MB 까지 진행을 알린 뒤 zip 을 받은 것으로 끝나고,
/// `AppBundleClientFake` 가 그 zip 을 샘플 앱으로 푼다)를 주입한다. Setup 화면이 없으므로 Setup 진입 버튼("개발 환경"·"iOS 설치"·"다른 iOS 버전 설치"·
/// "개발 환경 열기")은 눌러도 아무 일도 하지 않는다.
/// "카탈로그에서…" 시트는 `PreferencesClientFake`(카탈로그 2개 + http 주소 + 앞 항목과 같은 카탈로그)와 카탈로그 전용
/// `DownloadClientFake`(주소별 카탈로그 내용, 1초 지연)로 읽고, 고른 버전은 같은 `LauncherModel` 이 받아 설치한다.
/// "스크린샷" 은 `WorkspaceClientFake`(파일을 만들지 않고 가짜 폴더 이름만 예약한다)와 `SimulatorClientFake`(켜진 기기면 1초 뒤
/// 찍은 것으로 끝난다)로 돌아, 사진 폴더에 파일이 생기지 않고 Finder 도 열리지 않는다.
/// Example 에는 Settings 씬이 없다(설정 창은 App 에서 확인한다).
@main
struct LauncherFeatureExampleApp: App {
  @State private var model: LauncherModel
  @State private var catalogModel: CatalogInstallModel

  init() {
    let launcher = Self.makeModel()
    self._model = State(initialValue: launcher)
    self._catalogModel = State(initialValue: makeCatalogModel(.exampleCatalogs, installingWith: launcher))
  }

  var body: some Scene {
    WindowGroup {
      LauncherView(model: self.model, catalogModel: self.catalogModel)
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
    return LauncherModel(simulator: fake, appBundle: appBundle, download: download, workspace: WorkspaceClientFake())
  }
}

extension DownloadProgress {
  /// 48 MB 를 4.8 MB 씩 받는 진행 (Example·프리뷰가 행의 바이트·진행 막대를 보이게).
  static let example: [DownloadProgress] = (0 ... 10).map { (step: Int64) -> DownloadProgress in
    DownloadProgress(receivedBytes: step * 4_800_000, expectedBytes: 48_000_000)
  }
}

/// 카탈로그에서 설치 시트의 Model. 저장된 목록은 `setting`, 카탈로그 받기는 따로 만든 `DownloadClientFake`(1초 지연,
/// 주소별 내용: `ExampleCatalog.teamURL` 은 `team`, `otherURL` 은 `other`, 그 밖은 빈 Data)다.
/// 고른 버전은 `launcher` 가 URL 설치와 같은 경로로 받아 설치한다.
@MainActor
private func makeCatalogModel(
  _ setting: CatalogURLSetting,
  installingWith launcher: LauncherModel,
  catalogDownload configure: (DownloadClientFake) -> Void = { _ in }
) -> CatalogInstallModel {
  let preferences = PreferencesClientFake(urls: setting.urls, isLocked: setting.isLocked)
  let download = DownloadClientFake()
  download.setDelay(.seconds(1))
  download.setFetchResult(.success(ExampleCatalog.team), for: ExampleCatalog.teamURL)
  download.setFetchResult(.success(ExampleCatalog.other), for: ExampleCatalog.otherURL)
  configure(download)
  return CatalogInstallModel(
    preferences: preferences,
    download: download,
    installRequested: { request in await launcher.catalogInstallRequested(request) }
  )
}

/// Fake 를 만들어 설정한 뒤 화면을 만든다. 카탈로그 시트는 기본이 빈 목록이고, `catalogs`·`catalogDownload` 로 바꾼다.
/// 스크린샷 저장은 `workspace` 로 바꾼다 (기본: 늘 예약·보이기에 성공하는 Fake).
@MainActor
private func previewLauncher(
  _ inventory: DeviceInventory = .sample,
  configure: (SimulatorClientFake) -> Void = { _ in },
  appBundle configureAppBundle: (AppBundleClientFake) -> Void = { _ in },
  download configureDownload: (DownloadClientFake) -> Void = { _ in },
  workspace configureWorkspace: (WorkspaceClientFake) -> Void = { _ in },
  catalogs: CatalogURLSetting = CatalogURLSetting(urls: [], isLocked: false),
  catalogDownload configureCatalogDownload: (DownloadClientFake) -> Void = { _ in }
) -> LauncherView {
  let fake = SimulatorClientFake(inventory: inventory)
  configure(fake)
  let appBundle = AppBundleClientFake()
  configureAppBundle(appBundle)
  let download = DownloadClientFake()
  download.setDownloadScript(progress: DownloadProgress.example, result: nil)
  download.setDelay(.milliseconds(300))
  configureDownload(download)
  let workspace = WorkspaceClientFake()
  configureWorkspace(workspace)
  let launcher = LauncherModel(simulator: fake, appBundle: appBundle, download: download, workspace: workspace)
  let catalogModel = makeCatalogModel(catalogs, installingWith: launcher, catalogDownload: configureCatalogDownload)
  return LauncherView(model: launcher, catalogModel: catalogModel)
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

/// 켜진 기기만 버튼이 활성이고, 꺼진·쓸 수 없는 기기는 비활성이며 툴팁이 이유를 보인다.
#Preview("스크린샷 (켜진 기기의 스크린샷)") {
  previewLauncher { $0.setDelay(.seconds(1)) }
}

#Preview("스크린샷 찍는 중 (켜진 기기의 스크린샷, 끝나지 않음)") {
  previewLauncher { $0.suspendScreenshots() }
}

#Preview("스크린샷 실패: 저장 폴더 (켜진 기기의 스크린샷)") {
  previewLauncher(workspace: { $0.setReserveError(.folderUnavailable) })
}

#Preview("스크린샷 실패: 기기 꺼짐 (켜진 기기의 스크린샷)") {
  previewLauncher { $0.setScreenshotError(.deviceNotBooted) }
}

#Preview("스크린샷 저장 뒤 Finder 실패 (켜진 기기의 스크린샷)") {
  previewLauncher(workspace: { $0.setRevealError(.fileNotFound) })
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

#Preview("카탈로그 목록 (앱 설치 → 카탈로그에서…, 쓸 수 없는 주소·같은 카탈로그 섞임)") {
  previewLauncher(catalogs: .exampleCatalogs)
}

#Preview("카탈로그 읽는 중 (앱 설치 → 카탈로그에서…, 한 카탈로그가 끝나지 않음)") {
  previewLauncher(catalogs: .exampleCatalogs, catalogDownload: { $0.suspendFetches(for: ExampleCatalog.otherURL) })
}

#Preview("한 카탈로그 실패: HTTP 404 (앱 설치 → 카탈로그에서…)") {
  previewLauncher(
    catalogs: .exampleCatalogs,
    catalogDownload: { $0.setFetchResult(.failure(.httpStatus(404)), for: ExampleCatalog.otherURL) }
  )
}

/// 관리자가 잠근 목록: 실패 이유의 주소 확인 안내와 쓸 수 없는 주소의 안내가 설정 창 대신 담당자를 가리킨다.
#Preview("잠긴 목록에서 404 (앱 설치 → 카탈로그에서…)") {
  previewLauncher(
    catalogs: CatalogURLSetting(urls: CatalogURLSetting.exampleCatalogs.urls, isLocked: true),
    catalogDownload: { $0.setFetchResult(.failure(.httpStatus(404)), for: ExampleCatalog.otherURL) }
  )
}

#Preview("카탈로그 형식 문제: 새 규격·버전 날짜 (앱 설치 → 카탈로그에서…)") {
  previewLauncher(catalogs: .exampleCatalogs, catalogDownload: {
    $0.setFetchResult(.success(ExampleCatalog.newerSchema), for: ExampleCatalog.teamURL)
    $0.setFetchResult(.success(ExampleCatalog.badCreatedAt), for: ExampleCatalog.otherURL)
  })
}

#Preview("등록된 카탈로그 없음 (앱 설치 → 카탈로그에서…, 설정 열기 버튼)") {
  previewLauncher()
}

#Preview("관리자가 정한 빈 목록 (앱 설치 → 카탈로그에서…)") {
  previewLauncher(catalogs: CatalogURLSetting(urls: [], isLocked: true))
}

#Preview("카탈로그 버전 받기 실패: HTTP 404 (카탈로그에서… → 받아서 설치)") {
  previewLauncher(
    download: { $0.setDownloadScript(progress: [], result: .failure(.httpStatus(404))) },
    catalogs: .exampleCatalogs
  )
}

#Preview("카탈로그 버전에서 웹 페이지를 받음 (카탈로그에서… → 받아서 설치)") {
  previewLauncher(
    appBundle: { $0.setExtractError(.zipUnreadable) },
    download: { $0.setDownloadScript(progress: DownloadProgress.example, result: .success(.loginPage)) },
    catalogs: .exampleCatalogs
  )
}

#Preview("카탈로그 버전의 zip 에 .app 없음 (카탈로그에서… → 받아서 설치)") {
  previewLauncher(appBundle: { $0.setExtractError(.zipWithoutApp) }, catalogs: .exampleCatalogs)
}

extension CatalogURLSetting {
  /// 카탈로그 2개, http 주소(쓸 수 없는 주소), 첫 카탈로그와 같은 카탈로그(한 번만 읽고 보이지 않는다).
  static let exampleCatalogs = CatalogURLSetting(
    urls: [
      "https://builds.example.com/ios/catalog.json",
      "https://cdn.example.org/team/catalog.json",
      "http://builds.example.com/ios/catalog.json",
      "HTTPS://BUILDS.EXAMPLE.COM:443/ios/catalog.json",
    ],
    isLocked: false
  )
}

/// 카탈로그 받기가 돌려줄 내용 (docs/CATALOG.md).
enum ExampleCatalog {
  static let teamURL = DownloadURL("https://builds.example.com/ios/catalog.json")!
  static let otherURL = DownloadURL("https://cdn.example.org/team/catalog.json")!

  /// 버전이 셋(태그·브랜치·빌드 번호를 섞음)인 앱과 버전이 없는 앱.
  static let team = Data("""
  {
    "schemaVersion": 1,
    "apps": [
      {
        "id": "sample-app",
        "name": "Sample",
        "versions": [
          {
            "id": "build-41",
            "name": "1.2.0 (41)",
            "tag": "v1.2.0",
            "buildNumber": "41",
            "createdAt": "2026-10-14T02:00:00Z",
            "buildURL": "https://builds.example.com/sample-41.zip"
          },
          {
            "id": "build-43",
            "name": "1.3.0 beta (43)",
            "branch": "feature/login",
            "buildNumber": "43",
            "createdAt": "2026-10-21T09:30:00Z",
            "buildURL": "https://builds.example.com/sample-43.zip"
          },
          {
            "id": "build-42",
            "name": "1.3.0 beta (42)",
            "branch": "main",
            "buildNumber": "42",
            "createdAt": "2026-10-21T04:08:49Z",
            "buildURL": "https://builds.example.com/sample-42.zip"
          }
        ]
      },
      { "id": "empty-app", "name": "Empty", "versions": [] }
    ]
  }
  """.utf8)

  /// 첫 카탈로그와 같은 앱 id 를 쓰는 다른 카탈로그 (합치지 않고 따로 보인다).
  static let other = Data("""
  {
    "schemaVersion": 1,
    "apps": [
      {
        "id": "sample-app",
        "name": "Sample (QA)",
        "versions": [
          {
            "id": "qa-7",
            "name": "1.3.0 QA 7",
            "tag": "qa-7",
            "createdAt": "2026-10-20T08:00:00+09:00",
            "buildURL": "https://cdn.example.org/team/sample-qa-7.zip"
          }
        ]
      },
      {
        "id": "tool-app",
        "name": "Tool",
        "versions": [
          {
            "id": "1",
            "name": "0.1",
            "createdAt": "2026-09-01T00:00:00Z",
            "buildURL": "https://cdn.example.org/team/tool-1.zip"
          }
        ]
      }
    ]
  }
  """.utf8)

  static let newerSchema = Data(#"{ "schemaVersion": 2, "apps": [] }"#.utf8)

  /// 첫 앱의 첫 버전 날짜에 시간대가 없다.
  static let badCreatedAt = Data("""
  {
    "schemaVersion": 1,
    "apps": [
      {
        "id": "sample-app",
        "name": "Sample",
        "versions": [
          {
            "id": "build-42",
            "name": "1.0 (42)",
            "createdAt": "2026-10-21T04:08:49",
            "buildURL": "https://builds.example.com/sample-42.zip"
          }
        ]
      }
    ]
  }
  """.utf8)
}
