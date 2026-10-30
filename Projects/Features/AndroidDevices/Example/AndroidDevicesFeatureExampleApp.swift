import AndroidDevicesFeature
import AndroidEmulatorInterface
import AndroidEmulatorTesting
import AndroidPackageInterface
import AndroidPackageTesting
import Core
import DownloadInterface
import DownloadTesting
import Foundation
import PreferencesTesting
import SwiftUI

/// App 없이 Android 기기 목록 화면만 띄우는 데모 앱. Preview 도 여기에 둔다.
/// 실제 emulator·adb·`~/.android` 대신 Testing 모듈의 `AndroidEmulatorClientFake`(호출마다 1초 지연)를, apk 검사 대신
/// `AndroidPackageClientFake`(1초 지연, 고른 파일과 관계없이 샘플 apk 정보)를 주입한다.
/// URL·카탈로그에서 설치는 네트워크 대신 `DownloadClientFake`(진행 사이 0.3초 지연)를, 등록 카탈로그는 `PreferencesClientFake`
/// (v2 카탈로그·v1 카탈로그·iOS 앱만 있는 v2 카탈로그, 장면에 따라 받지 못하는 주소)를 주입한다.
/// 파일·명령·네트워크를 쓰지 않으므로 아무것도 켜거나 만들거나 설치하지 않는다 (Fake 의 목록만 바뀐다).
/// 앱 설치(파일·URL·카탈로그)·실행·링크 열기는 켜진 기기("Pixel Tablet")에서 해 본다.
/// 왼쪽 목록에서 상태를 고른다. "Android 도구" 버튼은 App 이 도구 화면을 여는 대신 아래 줄에 누른 횟수를 보인다.
@main
struct AndroidDevicesFeatureExampleApp: App {
  @State private var scenario: DemoScenario = .normal
  @State private var setupRequests = SetupRequestCounter()
  @State private var models: [DemoScenario: DemoModels] = [:]

  var body: some Scene {
    WindowGroup {
      NavigationSplitView {
        List(DemoScenario.allCases, id: \.self, selection: Binding(
          get: { Optional(self.scenario) },
          set: { self.scenario = $0 ?? .normal }
        )) { scenario in
          Text(verbatim: scenario.rawValue)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 240)
      } detail: {
        VStack(spacing: 0) {
          if let models = self.models[self.scenario] {
            AndroidDevicesView(
              model: models.devices,
              downloadModel: models.downloadInstall,
              appSheetsModel: models.appSheets
            )
            .id(self.scenario)
          }
          Divider()
          Text(verbatim: "Android 도구 버튼을 누른 횟수: \(self.setupRequests.count)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .task {
        // 상태마다 Model 하나를 만들어 두고 다시 고르면 그대로 쓴다 (App 이 Model 을 소유하는 것과 같다).
        guard self.models.isEmpty else { return }
        let counter = self.setupRequests
        self.models = Dictionary(uniqueKeysWithValues: DemoScenario.allCases.map { scenario in
          (scenario, scenario.makeModel { counter.count += 1 })
        })
      }
    }
  }
}

/// 장면 하나의 Model 셋 (App 이 셋을 만들어 `installRequested`·`launchRequested` 등으로 잇는 것과 같다).
@MainActor
struct DemoModels {
  let devices: AndroidDevicesModel
  let downloadInstall: AndroidDownloadInstallModel
  let appSheets: AndroidAppSheetsModel
}

/// 기기 목록 Model 의 `appSheetPresented` 가 뒤에 만든 시트 Model 을 읽게 넘기는 상자 (App 과 같다).
@MainActor
final class DemoAppSheetsBox {
  weak var model: AndroidAppSheetsModel?
}

/// "Android 도구" 버튼을 누른 횟수 (App 이 도구 화면을 여는 자리).
@MainActor
@Observable
final class SetupRequestCounter {
  var count = 0
}

/// 데모 상태. 원시값이 목록에 보이는 이름이다.
enum DemoScenario: String, CaseIterable, Hashable {
  case normal = "정상 (꺼짐·켜짐·쓸 수 없음)"
  case empty = "빈 상태 (기기 없음)"
  case noImage = "만들 이미지 없음"
  case noImageWithDevices = "만들 이미지 없음 (기기 있음)"
  case outsideBooting = "앱 밖에서 켜는 중"
  case slowBoot = "켜기 오래 걸림 (켜는 중 유지)"
  case bootFailure = "실패: 켜기 시간 초과"
  case shutdownFailure = "실패: 끄기 (adb)"
  case createFailure = "실패: 만들기 (이름 충돌)"
  case folderKept = "삭제: 폴더 남김 (정보 알림)"
  case eraseUnsafe = "실패: 초기화 (기기 폴더 위치)"
  case sdkUnavailable = "목록 실패: Android 도구 없음"
  case avdFolderUnavailable = "목록 실패: 기기 폴더 읽기"
  case slowInstall = "앱 설치 오래 걸림 (설치 중 유지)"
  case inspectFailure = "설치 실패: 검사 (.aab)"
  case rejected = "설치 실패: 판정 (API 낮음)"
  case installFailure = "설치 실패: 서명이 다른 같은 앱"
  case launchAfterInstallFailure = "설치 후 실행 실패: 화면 없음"
  case noInstalledPackages = "앱 실행: 설치한 앱 없음"
  case packageListFailure = "앱 실행: 목록 읽기 실패"
  case launchFailure = "앱 실행 실패: 설치 안 됨"
  case urlNotHandled = "링크 열기 실패: 받을 앱 없음"
  case slowDownload = "URL·카탈로그: 받는 중 유지 (취소)"
  case unknownSizeDownload = "URL·카탈로그: 크기 모름 받는 중"
  case downloadFailure = "URL·카탈로그 실패: 받기 (404)"
  case webPage = "URL·카탈로그 실패: 웹 페이지를 받음"
  case catalogFailure = "카탈로그: 받지 못한 카탈로그 있음"
  case catalogLocked = "카탈로그: 잠김 (관리자 설정)"
  case catalogEmpty = "카탈로그: 등록 없음"

  private static let allDevices = AndroidDeviceInventory(
    devices: [
      .phoneSample, .bootedTabletSample, .unsupportedNameSample, .missingImageSample,
      AndroidVirtualDevice(
        id: AndroidVirtualDevice.ID("Intel_Phone"),
        displayName: "Intel Phone",
        systemImage: AndroidSystemImageRef(apiFolder: "android-34", tag: "google_apis", abi: "x86_64"),
        formFactor: .phone,
        state: .shutdown,
        availability: .unavailable(.unsupportedABI("x86_64"))
      ),
    ],
    creationOptions: .sample
  )

  @MainActor
  func makeModel(setupRequested: @escaping @MainActor () -> Void) -> DemoModels {
    let fake = AndroidEmulatorClientFake(inventory: self.inventory)
    fake.setDelay(.seconds(1))
    fake.setInstalledPackages(.success(Self.samplePackages))
    let package = AndroidPackageClientFake()
    package.setDelay(.seconds(1))
    let download = DownloadClientFake()
    download.setDelay(.milliseconds(300))
    download.setDownloadScript(progress: Self.downloadProgress, result: nil)
    self.configure(fake)
    self.configure(package)
    self.configure(download)
    let appSheetsBox = DemoAppSheetsBox()
    let devices = AndroidDevicesModel(
      emulator: fake,
      package: package,
      download: download,
      setupRequested: setupRequested,
      appSheetPresented: { appSheetsBox.model?.hasPresentedSheet ?? false }
    )
    let appSheets = AndroidAppSheetsModel(
      emulator: fake,
      target: { id, task in devices.appSheetTarget(id, for: task) },
      launchRequested: { request in await devices.launchAppRequested(request) },
      openURLRequested: { request in await devices.openURLRequested(request) }
    )
    appSheetsBox.model = appSheets
    let preferences = PreferencesClientFake(urls: self.catalogURLs, isLocked: self == .catalogLocked)
    let downloadInstall = AndroidDownloadInstallModel(
      preferences: preferences,
      download: download,
      installRequested: { request in await devices.downloadInstallRequested(request) }
    )
    return DemoModels(devices: devices, downloadInstall: downloadInstall, appSheets: appSheets)
  }

  /// 0 → 전체 1 MiB 까지 여덟 번 (행의 진행 막대가 보이도록).
  private static let downloadProgress = (0 ... 8).map {
    DownloadProgress(receivedBytes: Int64($0) * 131_072, expectedBytes: 1_048_576)
  }

  /// 등록 카탈로그. 받지 못하는 주소는 실패 장면에서만 넣는다.
  private var catalogURLs: [String] {
    switch self {
    case .catalogEmpty:
      []
    case .catalogFailure, .catalogLocked:
      DemoCatalog.urls + [DemoCatalog.missingURL.url.absoluteString]
    default:
      DemoCatalog.urls
    }
  }

  private func configure(_ download: DownloadClientFake) {
    download.setFetchResult(.success(DemoCatalog.catalogV2), for: DemoCatalog.v2URL)
    download.setFetchResult(.success(DemoCatalog.catalogV1), for: DemoCatalog.v1URL)
    download.setFetchResult(.success(DemoCatalog.iOSOnly), for: DemoCatalog.iOSOnlyURL)
    download.setFetchResult(.failure(.httpStatus(404)), for: DemoCatalog.missingURL)
    switch self {
    case .slowDownload:
      download.setDownloadScript(progress: Array(Self.downloadProgress.prefix(4)), result: nil)
      download.suspendDownloads()
    case .unknownSizeDownload:
      download.setDownloadScript(progress: DownloadProgress.unknownTotalSamples, result: nil)
      download.suspendDownloads()
    case .downloadFailure:
      download.setDownloadScript(progress: [], result: .failure(.httpStatus(404)))
    case .webPage:
      let folder = URL(filePath: "/tmp/SimLauncher-Download-Demo", directoryHint: .isDirectory)
      download.setDownloadScript(progress: DownloadProgress.unknownTotalSamples, result: .success(DownloadedFile(
        file: folder.appending(path: "download.apk", directoryHint: .notDirectory),
        folder: folder,
        byteCount: 4096,
        mimeType: "text/html"
      )))
    default:
      break
    }
  }

  /// 앱 실행 시트에 보일 설치 앱 (이름순).
  private static let samplePackages = ["com.example.sample", "org.example.shop"].compactMap(AndroidPackageName.init)

  private var inventory: AndroidDeviceInventory {
    switch self {
    case .empty:
      .emptySample
    case .noImage:
      AndroidDeviceInventory(devices: [], creationOptions: .emptySample)
    case .noImageWithDevices:
      AndroidDeviceInventory(devices: [.phoneSample], creationOptions: .emptySample)
    case .outsideBooting:
      AndroidDeviceInventory(devices: [.phoneSample, .bootingSample], creationOptions: .sample)
    default:
      Self.allDevices
    }
  }

  private func configure(_ fake: AndroidEmulatorClientFake) {
    switch self {
    case .slowBoot, .bootFailure, .shutdownFailure, .createFailure, .folderKept, .eraseUnsafe:
      self.configureDeviceOperations(fake)
    case .sdkUnavailable:
      fake.setFetchError(.sdkUnavailable)
    case .avdFolderUnavailable:
      fake.setFetchError(.avdFolderUnavailable)
    default:
      self.configureAppOperations(fake)
    }
  }

  private func configureDeviceOperations(_ fake: AndroidEmulatorClientFake) {
    switch self {
    case .slowBoot:
      fake.suspendBoots()
    case .bootFailure:
      fake.setBootError(.bootTimedOut)
    case .shutdownFailure:
      fake.setShutdownError(.adbUnavailable)
    case .createFailure:
      fake.setCreateError(.nameUnavailable)
    case .folderKept:
      fake.setDeleteResult(.success(.folderKept(URL(
        filePath: "/Users/me/Documents/My Phone/",
        directoryHint: .isDirectory
      ))))
    case .eraseUnsafe:
      fake.setEraseError(.unsafeDeviceFolder(URL(filePath: "/Users/me/avd-link", directoryHint: .isDirectory)))
    default:
      break
    }
  }

  private func configureAppOperations(_ fake: AndroidEmulatorClientFake) {
    switch self {
    case .slowInstall:
      fake.suspendInstalls()
    case .installFailure:
      fake.setInstallError(.installFailed(.updateIncompatible))
    case .launchAfterInstallFailure:
      fake.setLaunchError(.launchFailed(.noLauncherActivity))
    case .noInstalledPackages:
      fake.setInstalledPackages(.success([]))
    case .packageListFailure:
      fake.setInstalledPackages(.failure(.deviceNotBooted))
    case .launchFailure:
      fake.setLaunchError(.launchFailed(.notInstalled))
    case .urlNotHandled:
      fake.setOpenURLError(.urlNotHandled)
    default:
      break
    }
  }

  private func configure(_ package: AndroidPackageClientFake) {
    switch self {
    case .inspectFailure:
      package.setResult(.failure(.appBundle))
    case .rejected:
      package.setResult(.success(.sample(minSDK: .level(99))))
    case .webPage:
      package.setResult(.failure(.unreadable))
    default:
      break
    }
  }
}

/// 카탈로그 받기가 돌려줄 내용 (docs/CATALOG.md). v2 는 iOS·Android 앱이 같은 id 를 쓴다 (Android 시트에는 Android 앱만 보인다).
enum DemoCatalog {
  static let v2URL = DownloadURL("https://builds.example.com/catalog.json")!
  static let v1URL = DownloadURL("https://builds.example.com/ios-only/catalog-v1.json")!
  static let iOSOnlyURL = DownloadURL("https://cdn.example.org/team/catalog.json")!
  static let missingURL = DownloadURL("https://cdn.example.org/missing/catalog.json")!
  static let urls = [v2URL, v1URL, iOSOnlyURL].map(\.url.absoluteString)

  static let catalogV2 = Data("""
  {
    "schemaVersion": 2,
    "apps": [
      {
        "id": "com.example.sample", "name": "Sample", "platform": "ios",
        "versions": [{ "id": "ios-42", "name": "1.3.0 (42)", "createdAt": "2026-10-21T04:08:49Z",
                       "buildURL": "https://builds.example.com/Sample-42.zip" }]
      },
      {
        "id": "com.example.sample", "name": "Sample", "platform": "android",
        "versions": [
          { "id": "android-43", "name": "1.3.0 beta (43)", "branch": "feature/login", "buildNumber": "43",
            "createdAt": "2026-10-22T09:30:00Z", "buildURL": "https://builds.example.com/Sample-43.apk" },
          { "id": "android-42", "name": "1.3.0 (42)", "tag": "v1.3.0", "buildNumber": "42",
            "createdAt": "2026-10-21T04:08:49Z", "buildURL": "https://builds.example.com/Sample-42.apk" }
        ]
      },
      { "id": "com.example.empty", "name": "Empty", "platform": "android", "versions": [] }
    ]
  }
  """.utf8)

  static let catalogV1 = Data("""
  {
    "schemaVersion": 1,
    "apps": [
      { "id": "com.example.sample", "name": "Sample", "versions": [] }
    ]
  }
  """.utf8)

  static let iOSOnly = Data("""
  {
    "schemaVersion": 2,
    "apps": [
      { "id": "com.example.tool", "name": "Tool", "platform": "ios", "versions": [] }
    ]
  }
  """.utf8)
}

@MainActor
private func demoPreview(_ scenario: DemoScenario) -> some View {
  let models = scenario.makeModel {}
  return AndroidDevicesView(
    model: models.devices,
    downloadModel: models.downloadInstall,
    appSheetsModel: models.appSheets
  )
  .frame(width: 720, height: 480)
}

#Preview("정상") {
  demoPreview(.normal)
}

#Preview("빈 상태") {
  demoPreview(.empty)
}

#Preview("만들 이미지 없음") {
  demoPreview(.noImage)
}

#Preview("앱 밖에서 켜는 중") {
  demoPreview(.outsideBooting)
}

#Preview("목록 실패") {
  demoPreview(.sdkUnavailable)
}

#Preview("받는 중") {
  demoPreview(.slowDownload)
}
