import Core
import Foundation

/// 테스트·Example 이 함께 쓰는 Android SDK 값. 경로는 실제로 읽지 않는 가짜 경로다.
public extension AndroidSDKRoot {
  /// 기본 위치 `/Users/fake/Library/Android/sdk/`.
  static let sample = AndroidSDKRoot(
    url: URL(filePath: "/Users/fake/Library/Android/sdk", directoryHint: .isDirectory),
    isDefault: true
  )

  /// 설정에서 고른 외장 디스크 폴더 `/Volumes/Tools/AndroidSDK/`.
  static let chosenSample = AndroidSDKRoot(
    url: URL(filePath: "/Volumes/Tools/AndroidSDK", directoryHint: .isDirectory),
    isDefault: false
  )
}

public extension AndroidLicense {
  /// `android-sdk-license` (platform-tools·emulator).
  static let sdkSample = AndroidLicense(
    id: "android-sdk-license",
    text: "Terms and Conditions\n\nThis is the Android Software Development Kit License Agreement (sample)."
  )

  /// `android-sdk-arm-dbt-license` (arm64 시스템 이미지).
  static let armDBTSample = AndroidLicense(
    id: "android-sdk-arm-dbt-license",
    text: "Terms and Conditions\n\nThis is the Android SDK ARM DBT License Agreement (sample)."
  )
}

public extension AndroidSelectedPackage {
  /// platform-tools 37.0.1, 16,110,554 B.
  static let platformToolsSample = SelectedPackageSample(
    component: .platformTools,
    path: "platform-tools",
    revision: AndroidRevision(major: 37, minor: 0, micro: 1),
    displayName: "Android SDK Platform-Tools",
    license: .sdkSample,
    size: 16_110_554,
    fileName: "platform-tools_r37.0.1-darwin.zip",
    folder: "https://dl.google.com/android/repository/"
  ).package

  /// emulator 37.2.12, 416,112,708 B.
  static let emulatorSample = SelectedPackageSample(
    component: .emulator,
    path: "emulator",
    revision: AndroidRevision(major: 37, minor: 2, micro: 12),
    displayName: "Android Emulator",
    license: .sdkSample,
    size: 416_112_708,
    fileName: "emulator-darwin_aarch64-16428233.zip",
    folder: "https://dl.google.com/android/repository/"
  ).package

  /// `system-images;android-37.0;google_apis;arm64-v8a` rev 8, 2,104,098,168 B.
  static let systemImageSample = SelectedPackageSample(
    component: .systemImage,
    path: "system-images;android-37.0;google_apis;arm64-v8a",
    revision: AndroidRevision(major: 8),
    displayName: "Google APIs ARM 64 v8a System Image",
    license: .armDBTSample,
    size: 2_104_098_168,
    fileName: "arm64-v8a-37.0_r08.zip",
    folder: "https://dl.google.com/android/repository/sys-img/google_apis/"
  ).package
}

/// `AndroidSelectedPackage` 샘플 하나의 값. archive 는 macosx·sha1 `0…0`, 주소는 `folder + fileName`.
private struct SelectedPackageSample {
  let component: AndroidSDKComponent
  let path: String
  let revision: AndroidRevision
  let displayName: String
  let license: AndroidLicense
  let size: Int64
  let fileName: String
  let folder: String

  var package: AndroidSelectedPackage {
    guard
      let packagePath = AndroidPackagePath(self.path),
      let checksum = ArchiveChecksum(algorithm: .sha1, hex: String(repeating: "0", count: 40)),
      let url = DownloadURL(self.folder + self.fileName)
    else {
      preconditionFailure("샘플 값이 규칙에 맞지 않는다")
    }
    return AndroidSelectedPackage(
      component: self.component,
      path: packagePath,
      revision: self.revision,
      displayName: self.displayName,
      license: self.license,
      archive: AndroidArchive(
        hostOS: "macosx",
        hostArch: nil,
        size: self.size,
        checksum: checksum,
        fileName: self.fileName
      ),
      url: url
    )
  }
}

public extension AndroidSDKInstallPlan {
  /// 셋 다 설치, 라이선스 두 개, 같은 볼륨 `Macintosh HD`.
  static let sample = AndroidSDKInstallPlan(
    root: .sample,
    sdkVolumeName: "Macintosh HD",
    sameVolumeAsDownloads: true,
    packages: [.platformToolsSample, .emulatorSample, .systemImageSample],
    licenses: [.sdkSample, .armDBTSample]
  )

  /// 시스템 이미지 하나, 라이선스 하나.
  static let systemImageOnly = AndroidSDKInstallPlan(
    root: .sample,
    sdkVolumeName: "Macintosh HD",
    sameVolumeAsDownloads: true,
    packages: [.systemImageSample],
    licenses: [.armDBTSample]
  )

  /// 고른 외장 볼륨에 셋 다 (필요 공간이 두 줄).
  static let externalVolumeSample = AndroidSDKInstallPlan(
    root: .chosenSample,
    sdkVolumeName: "Tools",
    sameVolumeAsDownloads: false,
    packages: [.platformToolsSample, .emulatorSample, .systemImageSample],
    licenses: [.sdkSample, .armDBTSample]
  )

  /// 설치할 것이 없다.
  static let emptySample = AndroidSDKInstallPlan(
    root: .sample,
    sdkVolumeName: "Macintosh HD",
    sameVolumeAsDownloads: true,
    packages: [],
    licenses: []
  )
}

public extension AndroidSDKStatus {
  /// 셋 다 설치됨 (기본 위치).
  static let readySample = AndroidSDKStatus(
    location: .folder(.sample, writable: true),
    components: [
      .platformTools: .installed(AndroidRevision(major: 37, minor: 0, micro: 1)),
      .emulator: .installed(AndroidRevision(major: 37, minor: 2, micro: 12)),
      .systemImage: .installed(AndroidRevision(major: 7)),
    ],
    installBlocker: nil,
    installedSystemImages: ["android-37.0"]
  )

  /// 기본 위치가 없다 (셋 다 없음, 설치 가능).
  static let absentSample = AndroidSDKStatus(
    location: .absent(.sample),
    components: [.platformTools: .missing, .emulator: .missing, .systemImage: .missing],
    installBlocker: nil,
    installedSystemImages: []
  )

  /// platform-tools 만 있다 (emulator 는 쓸 수 없음, 시스템 이미지는 없음).
  static let partialSample = AndroidSDKStatus(
    location: .folder(.sample, writable: true),
    components: [
      .platformTools: .installed(AndroidRevision(major: 37, minor: 0, micro: 1)),
      .emulator: .unusable(.executableMissing),
      .systemImage: .missing,
    ],
    installBlocker: nil,
    installedSystemImages: []
  )

  /// 고른 폴더를 찾을 수 없다.
  static let chosenMissingSample = AndroidSDKStatus(
    location: .unusable(.chosenSample, .missing),
    components: [:],
    installBlocker: nil,
    installedSystemImages: []
  )

  /// 쓸 수 없는 위치 (셋 다 없음, 설치 불가).
  static let notWritableSample = AndroidSDKStatus(
    location: .folder(.sample, writable: false),
    components: [.platformTools: .missing, .emulator: .missing, .systemImage: .missing],
    installBlocker: .notWritable(AndroidSDKRoot.sample.url),
    installedSystemImages: []
  )

  /// 지정한 위치 문제.
  static func unusableSample(_ problem: AndroidSDKLocationProblem) -> AndroidSDKStatus {
    AndroidSDKStatus(
      location: .unusable(problem == .invalidSetting ? nil : .sample, problem),
      components: [:],
      installBlocker: nil,
      installedSystemImages: []
    )
  }
}

public extension AndroidSDKInstallProgress {
  /// `plan` 의 `index`(1부터) 번째 패키지 단계. 바이트는 앞 패키지를 모두 받은 것으로 계산한다.
  static func sample(
    _ plan: AndroidSDKInstallPlan = .sample,
    index: Int,
    phase: Phase
  ) -> AndroidSDKInstallProgress {
    let packages = plan.packages
    let position = min(max(index, 1), max(packages.count, 1)) - 1
    let before = packages.prefix(position).reduce(Int64(0)) { $0 + $1.archive.size }
    let current: Int64 = switch phase {
    case let .downloading(received, _): received
    default: packages.indices.contains(position) ? packages[position].archive.size : 0
    }
    return AndroidSDKInstallProgress(
      packageIndex: index,
      packageCount: packages.count,
      component: packages.indices.contains(position) ? packages[position].component : .platformTools,
      phase: phase,
      completedBytes: before + current,
      totalBytes: plan.downloadBytes
    )
  }

  /// `.sample` 계획의 첫 알림 (platform-tools 받기 시작).
  static let firstSample = AndroidSDKInstallProgress.sample(
    index: 1,
    phase: .downloading(received: 0, expected: 16_110_554)
  )
}
