import Foundation
import Testing
@testable import Core

/// Android 테스트가 함께 쓰는 값.
enum AndroidFixture {
  static let repositoryBase = DownloadURL("https://dl.google.com/android/repository/")!
  static let systemImagesBase = DownloadURL("https://dl.google.com/android/repository/sys-img/google_apis/")!
  static let root = AndroidSDKRoot(
    url: URL(filePath: "/Users/u/Library/Android/sdk/", directoryHint: .isDirectory),
    isDefault: true
  )

  /// `Fixtures/<name>.xml`.
  static func xml(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "xml"))
    return try Data(contentsOf: url)
  }

  static func repository(_ name: String) throws -> AndroidRepository {
    try AndroidRepository(xmlData: self.xml(name))
  }

  static func path(_ raw: String) -> AndroidPackagePath {
    AndroidPackagePath(raw)!
  }

  static func sha1(_ seed: Character = "a") -> ArchiveChecksum {
    ArchiveChecksum(algorithm: .sha1, hex: String(repeating: seed, count: 40))!
  }

  static func archive(
    _ fileName: String,
    hostOS: String? = "macosx",
    arch: String? = nil,
    size: Int64 = 100
  ) -> AndroidArchive {
    AndroidArchive(hostOS: hostOS, hostArch: arch, size: size, checksum: self.sha1(), fileName: fileName)
  }

  static func tool(
    _ path: String,
    _ revision: AndroidRevision,
    channel: AndroidChannel = .stable,
    obsolete: Bool = false,
    license: String? = "android-sdk-license",
    archives: [AndroidArchive]
  ) -> AndroidRemotePackage {
    AndroidRemotePackage(
      path: self.path(path),
      revision: revision,
      displayName: path,
      licenseID: license,
      channel: channel,
      obsolete: obsolete,
      systemImage: nil,
      dependencies: [],
      archives: archives
    )
  }

  static func image(
    api: String,
    abi: String = "arm64-v8a",
    tags: [String] = ["google_apis"],
    codename: String? = nil,
    baseExtension: Bool? = true,
    revision: AndroidRevision = AndroidRevision(major: 1),
    channel: AndroidChannel = .stable,
    obsolete: Bool = false,
    emulator: AndroidRevision? = nil,
    license: String? = "android-sdk-arm-dbt-license",
    pathTag: String? = nil,
    archives: [AndroidArchive]? = nil
  ) -> AndroidRemotePackage {
    let path = "system-images;android-\(api);\(pathTag ?? tags.joined(separator: "_"));\(abi)"
    return AndroidRemotePackage(
      path: self.path(path),
      revision: revision,
      displayName: path,
      licenseID: license,
      channel: channel,
      obsolete: obsolete,
      systemImage: AndroidSystemImageDetails(
        apiLevel: api,
        codename: codename,
        tags: tags,
        abi: abi,
        baseExtension: baseExtension
      ),
      dependencies: emulator.map { [AndroidPackageDependency(path: self.path("emulator"), minRevision: $0)] } ?? [],
      archives: archives ?? [self.archive("\(abi)-\(api)_r\(revision.major).zip", hostOS: nil)]
    )
  }

  static let sdkLicense = AndroidLicense(id: "android-sdk-license", text: "SDK license")
  static let armLicense = AndroidLicense(id: "android-sdk-arm-dbt-license", text: "ARM license")

  static func repository(
    _ packages: [AndroidRemotePackage],
    licenses: [AndroidLicense] = [Self.sdkLicense, Self.armLicense]
  ) -> AndroidRepository {
    AndroidRepository(licenses: Dictionary(uniqueKeysWithValues: licenses.map { ($0.id, $0) }), packages: packages)
  }

  /// 기본 인자로 고른 계획.
  static func plan(
    tools: [AndroidRemotePackage],
    images: [AndroidRemotePackage],
    toolLicenses: [AndroidLicense] = [Self.sdkLicense, Self.armLicense],
    imageLicenses: [AndroidLicense] = [Self.sdkLicense, Self.armLicense],
    host: AndroidHostArchitecture = .aarch64,
    missing: Set<AndroidSDKComponent> = Set(AndroidSDKComponent.allCases),
    installedEmulator: AndroidRevision? = nil
  ) -> Result<AndroidSDKInstallPlan, AndroidSDKPlanProblem> {
    let input = AndroidSDKSelection.Input(
      repository: self.repository(tools, licenses: toolLicenses),
      repositoryBase: self.repositoryBase,
      systemImages: self.repository(images, licenses: imageLicenses),
      systemImagesBase: self.systemImagesBase,
      host: host,
      missing: missing,
      installedEmulator: installedEmulator
    )
    return AndroidSDKSelection.plan(
      input,
      root: self.root,
      sdkVolumeName: "Macintosh HD",
      sameVolumeAsDownloads: true
    )
  }
}

extension AndroidRevision {
  /// 테스트 편의: `"37.2.12"`.
  static func v(_ raw: String) -> AndroidRevision {
    AndroidRevision(raw)!
  }
}
