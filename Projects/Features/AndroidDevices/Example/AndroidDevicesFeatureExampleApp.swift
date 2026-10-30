import AndroidDevicesFeature
import AndroidEmulatorInterface
import AndroidEmulatorTesting
import AndroidPackageInterface
import AndroidPackageTesting
import Core
import Foundation
import SwiftUI

/// App 없이 Android 기기 목록 화면만 띄우는 데모 앱. Preview 도 여기에 둔다.
/// 실제 emulator·adb·`~/.android` 대신 Testing 모듈의 `AndroidEmulatorClientFake`(호출마다 1초 지연)를, apk 검사 대신
/// `AndroidPackageClientFake`(1초 지연, 고른 파일과 관계없이 샘플 apk 정보)를 주입한다.
/// 파일·명령을 쓰지 않으므로 아무것도 켜거나 만들거나 설치하지 않는다 (Fake 의 목록만 바뀐다).
/// 앱 설치·실행·링크 열기는 켜진 기기("Pixel Tablet")에서 해 본다.
/// 왼쪽 목록에서 상태를 고른다. "Android 도구" 버튼은 App 이 도구 화면을 여는 대신 아래 줄에 누른 횟수를 보인다.
@main
struct AndroidDevicesFeatureExampleApp: App {
  @State private var scenario: DemoScenario = .normal
  @State private var setupRequests = SetupRequestCounter()
  @State private var models: [DemoScenario: AndroidDevicesModel] = [:]

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
          if let model = self.models[self.scenario] {
            AndroidDevicesView(model: model)
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
  func makeModel(setupRequested: @escaping @MainActor () -> Void) -> AndroidDevicesModel {
    let fake = AndroidEmulatorClientFake(inventory: self.inventory)
    fake.setDelay(.seconds(1))
    fake.setInstalledPackages(.success(Self.samplePackages))
    let package = AndroidPackageClientFake()
    package.setDelay(.seconds(1))
    self.configure(fake)
    self.configure(package)
    return AndroidDevicesModel(emulator: fake, package: package, setupRequested: setupRequested)
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
    default:
      break
    }
  }
}

@MainActor
private func demoPreview(_ scenario: DemoScenario) -> some View {
  AndroidDevicesView(model: scenario.makeModel {})
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
