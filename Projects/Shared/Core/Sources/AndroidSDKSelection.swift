import Foundation

/// 저장소 XML 두 개에서 없는 구성 요소마다 설치할 패키지를 고른다.
/// - platform-tools·emulator: path 가 정확히 `platform-tools`·`emulator`, stable 채널, obsolete·미리보기 아님, 이 Mac 에 맞는
///   archive(아래)가 있는 것 중 가장 높은 revision.
/// - 시스템 이미지: tag 가 정확히 `[google_apis]` 하나, codename 없음, base-extension true, abi = 호스트, 숫자 API
///   (`major[.minor]`), path 가 `system-images;android-…;google_apis;<호스트 abi>` 모양, stable·obsolete·미리보기 아님.
///   같은 path 면 높은 revision 하나만 두고 API 가 높은 것부터 본다.
///   emulator 의존(min-revision)이 이번에 설치할 emulator(없으면 설치된 revision, 모르면 만족)보다 높으면 다음 API 로 내려간다.
/// - archive: host-os 가 없거나 `macosx`, host-arch 가 없거나 호스트와 같다 (같은 것을 먼저). 파일 이름이
///   `^[A-Za-z0-9_][A-Za-z0-9._-]*$` 인 것만 XML 폴더 기준 https 주소로 만든다 (경로·절대 주소·숨김 이름은 거절).
/// - 라이선스: 패키지가 있는 XML 의 `<license>` 원문. 계획의 원문은 지문 기준으로 중복을 빼고 처음 나온 순서.
public enum AndroidSDKSelection {
  /// 고르는 데 쓰는 값.
  public struct Input: Sendable {
    public let repository: AndroidRepository
    /// XML 이 있는 폴더 주소 (archive 파일 이름을 붙인다).
    public let repositoryBase: DownloadURL
    public let systemImages: AndroidRepository
    /// XML 이 있는 폴더 주소 (archive 파일 이름을 붙인다).
    public let systemImagesBase: DownloadURL
    public let host: AndroidHostArchitecture
    /// 설치할 구성 요소. 없는 구성 요소는 계획에서 빠진다.
    public let missing: Set<AndroidSDKComponent>
    /// 이미 설치된 emulator 의 revision (모르면 nil).
    public let installedEmulator: AndroidRevision?

    public init(
      repository: AndroidRepository,
      repositoryBase: DownloadURL,
      systemImages: AndroidRepository,
      systemImagesBase: DownloadURL,
      host: AndroidHostArchitecture,
      missing: Set<AndroidSDKComponent>,
      installedEmulator: AndroidRevision?
    ) {
      self.repository = repository
      self.repositoryBase = repositoryBase
      self.systemImages = systemImages
      self.systemImagesBase = systemImagesBase
      self.host = host
      self.missing = missing
      self.installedEmulator = installedEmulator
    }
  }

  /// - Parameters:
  ///   - root·sdkVolumeName·sameVolumeAsDownloads: 계획에 그대로 담는다.
  /// - Returns: 구성 요소 순서로 첫 문제 하나.
  public static func plan(
    _ input: Input,
    root: AndroidSDKRoot,
    sdkVolumeName: String?,
    sameVolumeAsDownloads: Bool
  ) -> Result<AndroidSDKInstallPlan, AndroidSDKPlanProblem> {
    var packages: [AndroidSelectedPackage] = []
    var emulatorForImage = input.installedEmulator
    for component in AndroidSDKComponent.allCases where input.missing.contains(component) {
      let candidate: Candidate? = switch component {
      case .platformTools, .emulator:
        Self.tool(component, in: input.repository, base: input.repositoryBase, host: input.host)
      case .systemImage:
        Self.systemImage(
          in: input.systemImages,
          base: input.systemImagesBase,
          host: input.host,
          emulator: emulatorForImage
        )
      }
      guard let candidate else {
        return .failure(.noCompatiblePackage(component))
      }
      guard
        let licenseID = candidate.package.licenseID,
        let license = candidate.repository.licenses[licenseID]
      else {
        return .failure(.licenseMissing(component))
      }
      if component == .emulator {
        emulatorForImage = candidate.package.revision
      }
      packages.append(AndroidSelectedPackage(
        component: component,
        path: candidate.package.path,
        revision: candidate.package.revision,
        displayName: candidate.package.displayName,
        license: license,
        archive: candidate.archive,
        url: candidate.url
      ))
    }
    var fingerprints: Set<String> = []
    var licenses: [AndroidLicense] = []
    for package in packages where fingerprints.insert(package.license.fingerprint).inserted {
      licenses.append(package.license)
    }
    return .success(AndroidSDKInstallPlan(
      root: root,
      sdkVolumeName: sdkVolumeName,
      sameVolumeAsDownloads: sameVolumeAsDownloads,
      packages: packages,
      licenses: licenses
    ))
  }

  /// archive 파일 이름을 XML 폴더 주소에 붙인 주소. 이름이 규칙에 맞지 않으면 nil.
  public static func archiveURL(fileName: String, base: DownloadURL) -> DownloadURL? {
    guard fileName.wholeMatch(of: /[A-Za-z0-9_][A-Za-z0-9._-]*/) != nil else {
      return nil
    }
    let folder = base.url.absoluteString.hasSuffix("/") ? base.url.absoluteString : base.url.absoluteString + "/"
    return DownloadURL(folder + fileName)
  }

  private struct Candidate {
    let package: AndroidRemotePackage
    let archive: AndroidArchive
    let url: DownloadURL
    let repository: AndroidRepository
  }

  private static func tool(
    _ component: AndroidSDKComponent,
    in repository: AndroidRepository,
    base: DownloadURL,
    host: AndroidHostArchitecture
  ) -> Candidate? {
    let path = component.folderName
    var best: Candidate?
    for package in repository.packages
      where package.path.raw == path && Self.isStableRelease(package)
    {
      guard let (archive, url) = Self.archive(for: package, base: base, host: host, requiresMacOS: true) else {
        continue
      }
      if best.map({ package.revision > $0.package.revision }) ?? true {
        best = Candidate(package: package, archive: archive, url: url, repository: repository)
      }
    }
    return best
  }

  private static func systemImage(
    in repository: AndroidRepository,
    base: DownloadURL,
    host: AndroidHostArchitecture,
    emulator: AndroidRevision?
  ) -> Candidate? {
    var byPath: [String: (candidate: Candidate, api: APILevel)] = [:]
    for package in repository.packages where Self.isStableRelease(package) {
      guard
        let details = package.systemImage,
        details.tags == ["google_apis"],
        details.codename == nil,
        details.baseExtension == true,
        details.abi == host.systemImageABI,
        Self.isSystemImagePath(package.path, abi: host.systemImageABI),
        let api = APILevel(details.apiLevel),
        let (archive, url) = Self.archive(for: package, base: base, host: host, requiresMacOS: false)
      else {
        continue
      }
      if let existing = byPath[package.path.raw], existing.candidate.package.revision >= package.revision {
        continue
      }
      byPath[package.path.raw] = (Candidate(package: package, archive: archive, url: url, repository: repository), api)
    }
    let ordered = byPath.values.sorted {
      $0.api != $1.api ? $0.api > $1.api : $0.candidate.package.path.raw < $1.candidate.package.path.raw
    }
    return ordered.first { Self.satisfiesEmulator($0.candidate.package, emulator: emulator) }?.candidate
  }

  /// emulator 의존이 없거나, 비교할 revision 을 모르거나, revision 이 min 이상.
  private static func satisfiesEmulator(_ package: AndroidRemotePackage, emulator: AndroidRevision?) -> Bool {
    guard let emulator else {
      return true
    }
    return package.dependencies.allSatisfy { dependency in
      guard dependency.path.raw == "emulator", let minimum = dependency.minRevision else {
        return true
      }
      return emulator >= minimum
    }
  }

  private static func isStableRelease(_ package: AndroidRemotePackage) -> Bool {
    package.channel == .stable && !package.obsolete && package.revision.preview == nil
  }

  /// path 가 그대로 설치 경로가 되므로, 고른 tag·abi 와 같은 `system-images;android-…;google_apis;<abi>` 모양만 고른다
  /// (그 밖의 모양이면 SDK 안 엉뚱한 곳에 설치된다. 상태 판정은 `system-images/<API 폴더>/<tag>/<abi>` 를 본다).
  private static func isSystemImagePath(_ path: AndroidPackagePath, abi: String) -> Bool {
    let components = path.components
    // 둘째 칸(API 폴더)은 `android-` 로 시작해야 한다: 상태 판정은 숨김(`.` 으로 시작하는) API 폴더를 건너뛴다.
    return components.count == 4 && components[0] == "system-images" && components[1].hasPrefix("android-")
      && components[2] == "google_apis" && components[3] == abi
  }

  /// 이 Mac 에 맞는 archive 중 host-arch 가 정확히 같은 것을 먼저, 그다음 host-arch 없는 것. 같은 순위면 문서 순서.
  /// `requiresMacOS` 면 host-os 가 `macosx` 여야 하고, 아니면 없거나 `macosx`.
  private static func archive(
    for package: AndroidRemotePackage,
    base: DownloadURL,
    host: AndroidHostArchitecture,
    requiresMacOS: Bool
  ) -> (AndroidArchive, DownloadURL)? {
    var fallback: (AndroidArchive, DownloadURL)?
    for archive in package.archives {
      let osMatches = requiresMacOS ? archive.hostOS == "macosx" : (archive.hostOS == nil || archive.hostOS == "macosx")
      guard
        osMatches,
        archive.hostArch == nil || archive.hostArch == host.archiveHostArch,
        let url = Self.archiveURL(fileName: archive.fileName, base: base)
      else {
        continue
      }
      if archive.hostArch != nil {
        return (archive, url)
      }
      if fallback == nil {
        fallback = (archive, url)
      }
    }
    return fallback
  }
}

/// 시스템 이미지의 숫자 API (`36`·`37.0`·`36.1`). `36x` 같은 확장·미리보기 표기는 nil.
struct APILevel: Comparable {
  let major: Int
  let minor: Int

  init?(_ raw: String) {
    guard let match = raw.wholeMatch(of: /(\d+)(?:\.(\d+))?/), let major = Int(match.output.1) else {
      return nil
    }
    self.major = major
    self.minor = match.output.2.flatMap { Int($0) } ?? 0
  }

  static func < (lhs: APILevel, rhs: APILevel) -> Bool {
    (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
  }
}
