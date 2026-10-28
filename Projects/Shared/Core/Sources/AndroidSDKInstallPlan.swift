import Foundation

/// 앱이 설치하는 Android SDK 구성 요소. `allCases` 순서가 설치 순서다.
public enum AndroidSDKComponent: CaseIterable, Hashable, Sendable {
  case platformTools, emulator, systemImage

  /// SDK 루트 아래 맨 위 폴더 이름.
  public var folderName: String {
    switch self {
    case .platformTools: "platform-tools"
    case .emulator: "emulator"
    case .systemImage: "system-images"
    }
  }
}

/// 계획에 든 패키지 하나.
public struct AndroidSelectedPackage: Hashable, Sendable {
  public let component: AndroidSDKComponent
  public let path: AndroidPackagePath
  public let revision: AndroidRevision
  public let displayName: String
  /// 이 패키지가 있는 XML 의 `<license>` 원문.
  public let license: AndroidLicense
  public let archive: AndroidArchive
  /// archive 파일 이름을 XML 폴더 기준으로 붙인 https 주소.
  public let url: DownloadURL

  public init(
    component: AndroidSDKComponent,
    path: AndroidPackagePath,
    revision: AndroidRevision,
    displayName: String,
    license: AndroidLicense,
    archive: AndroidArchive,
    url: DownloadURL
  ) {
    self.component = component
    self.path = path
    self.revision = revision
    self.displayName = displayName
    self.license = license
    self.archive = archive
    self.url = url
  }
}

/// 없는 구성 요소를 설치할 계획. `install` 은 `root` 에 끝까지 설치한다 (도중에 위치가 바뀌어도 옮기지 않는다).
public struct AndroidSDKInstallPlan: Hashable, Sendable {
  /// 계획을 만들 때의 SDK 위치.
  public let root: AndroidSDKRoot
  /// SDK 위치(없으면 가장 가까운 있는 조상)의 볼륨 이름. 읽지 못하면 nil.
  public let sdkVolumeName: String?
  /// SDK 위치와 받기 임시 폴더가 같은 볼륨이다 (필요 공간을 한 줄로 보인다).
  public let sameVolumeAsDownloads: Bool
  /// 설치 순서 (`AndroidSDKComponent.allCases` 순서).
  public let packages: [AndroidSelectedPackage]
  /// 계획 패키지가 쓰는 원문. 지문이 같은 원문은 한 번만, 처음 나온 순서.
  public let licenses: [AndroidLicense]

  public init(
    root: AndroidSDKRoot,
    sdkVolumeName: String?,
    sameVolumeAsDownloads: Bool,
    packages: [AndroidSelectedPackage],
    licenses: [AndroidLicense]
  ) {
    self.root = root
    self.sdkVolumeName = sdkVolumeName
    self.sameVolumeAsDownloads = sameVolumeAsDownloads
    self.packages = packages
    self.licenses = licenses
  }

  /// archive 크기 합 (받을 바이트).
  public var downloadBytes: Int64 {
    self.packages.reduce(0) { $0 + $1.archive.size }
  }

  /// 설치 후 크기 어림: 받는 크기 × `installSizeFactor` (화면은 "약" 으로 보인다). install 의 미리 여유 확인과 같은 배율.
  public var estimatedInstallBytes: Int64 {
    self.packages.reduce(0) { $0 + $1.archive.size.multipliedClamped(by: Self.installSizeFactor) }
  }

  /// 풀린 크기 / 받는 크기 어림 배율 (실측 2.4~3.2).
  public static let installSizeFactor: Int64 = 3

  /// 설치할 패키지가 없다.
  public var isEmpty: Bool {
    self.packages.isEmpty
  }

  /// `licenses` 중 지문이 `accepted` 에 없는 원문, 순서 그대로.
  public func licensesToConfirm(accepted: Set<String>) -> [AndroidLicense] {
    self.licenses.filter { !accepted.contains($0.fingerprint) }
  }
}

/// 계획을 만들지 못한 이유. 구성 요소 순서로 첫 문제 하나.
public enum AndroidSDKPlanProblem: Error, Hashable, Sendable {
  /// 이 Mac 에 맞는 패키지(채널·OS·아키텍처·이미지 조건·emulator 의존)가 없다.
  case noCompatiblePackage(AndroidSDKComponent)
  /// 고른 패키지에 `<uses-license>` 가 없거나 그 id 의 원문이 그 XML 에 없다.
  case licenseMissing(AndroidSDKComponent)
}

extension Int64 {
  /// 곱이 넘치면 `Int64.max`.
  func multipliedClamped(by factor: Int64) -> Int64 {
    let (product, overflow) = self.multipliedReportingOverflow(by: factor)
    return overflow ? .max : product
  }

  /// 합이 넘치면 `Int64.max`.
  func addingClamped(_ other: Int64) -> Int64 {
    let (sum, overflow) = self.addingReportingOverflow(other)
    return overflow ? .max : sum
  }
}
