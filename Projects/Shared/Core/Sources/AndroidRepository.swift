import CryptoKit
import Foundation

/// 저장소 XML 의 `<channel>` 이름. 패키지는 `<channelRef ref="channel-N"/>` 로 가리킨다.
public enum AndroidChannel: Hashable, Sendable {
  case stable, beta, dev, canary
  /// 모르는 이름이거나 가리키는 `<channel>` 이 없다.
  case unknown

  /// `<channel>` 의 text (대소문자 구분, 앞뒤 공백 무시).
  init(name: String) {
    switch name.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "stable": self = .stable
    case "beta": self = .beta
    case "dev": self = .dev
    case "canary": self = .canary
    default: self = .unknown
    }
  }
}

/// 저장소 XML 의 `<license id="…">원문</license>`.
public struct AndroidLicense: Hashable, Sendable, Identifiable {
  public let id: String
  /// XML 의 text 그대로 (앞뒤 공백·줄바꿈 포함). 화면은 보일 때 다듬는다.
  public let text: String

  public init(id: String, text: String) {
    self.id = id
    self.text = text
  }

  /// 원문 UTF-8 의 SHA-256 소문자 hex (64 자). 동의 기록(Preferences `AcceptedAndroidLicenses`)의 값이다.
  /// id 가 같아도 원문이 한 글자라도 다르면 다르다 (Google 이 원문을 바꾸면 다시 묻는다).
  public var fingerprint: String {
    SHA256.hash(data: Data(self.text.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

/// archive 의 `<checksum type="…">`. 값은 소문자로 둔다.
public struct ArchiveChecksum: Hashable, Sendable {
  public enum Algorithm: Hashable, Sendable {
    case sha1, sha256

    /// hex 글자 수.
    public var hexLength: Int {
      switch self {
      case .sha1: 40
      case .sha256: 64
      }
    }
  }

  public let algorithm: Algorithm
  /// 소문자 hex.
  public let hex: String

  /// 앞뒤 공백을 빼고 소문자로 바꾼 값이 알고리즘의 길이(40·64)만큼의 hex 글자일 때만 만들어진다.
  public init?(algorithm: Algorithm, hex: String) {
    let value = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard value.count == algorithm.hexLength, value.allSatisfy(\.isLowercaseHexDigit) else {
      return nil
    }
    self.algorithm = algorithm
    self.hex = value
  }
}

/// archive 하나 (`<archive>` 의 `<complete>`). 패치(`<patches>`)는 읽지 않는다.
public struct AndroidArchive: Hashable, Sendable {
  /// `macosx`·`linux`·`windows`. 없으면 모든 OS.
  public let hostOS: String?
  /// `aarch64`·`x64`·`x86`. 없으면 모든 아키텍처.
  public let hostArch: String?
  public let size: Int64
  public let checksum: ArchiveChecksum
  /// `<url>` 값 그대로 (실측은 모두 XML 폴더 기준 파일 이름). 받을 주소는 `AndroidSDKSelection` 이 검사해 만든다.
  public let fileName: String

  public init(hostOS: String?, hostArch: String?, size: Int64, checksum: ArchiveChecksum, fileName: String) {
    self.hostOS = hostOS
    self.hostArch = hostArch
    self.size = size
    self.checksum = checksum
    self.fileName = fileName
  }
}

/// 시스템 이미지의 `<type-details>` (`sysImgDetailsType`).
public struct AndroidSystemImageDetails: Hashable, Sendable {
  /// `<api-level>` 문자열 그대로 (`36`·`37.0`·`36.1`·`36x`).
  public let apiLevel: String
  /// 미리보기 이미지만 있다 (`CANARY`·`DEV`·`CinnamonBun`).
  public let codename: String?
  /// `<tag><id>` 들, 문서 순서.
  public let tags: [String]
  public let abi: String
  /// `<base-extension>` 이 `true`·`false` 면 그 값, 없거나 다른 값이면 nil.
  public let baseExtension: Bool?

  public init(apiLevel: String, codename: String?, tags: [String], abi: String, baseExtension: Bool?) {
    self.apiLevel = apiLevel
    self.codename = codename
    self.tags = tags
    self.abi = abi
    self.baseExtension = baseExtension
  }
}

/// `<dependencies><dependency path="…"><min-revision>…</min-revision></dependency></dependencies>`.
public struct AndroidPackageDependency: Hashable, Sendable {
  public let path: AndroidPackagePath
  /// 없거나 읽지 못하면 nil (어느 revision 이든 만족).
  public let minRevision: AndroidRevision?

  public init(path: AndroidPackagePath, minRevision: AndroidRevision?) {
    self.path = path
    self.minRevision = minRevision
  }
}

/// 저장소 XML 의 `<remotePackage>`.
public struct AndroidRemotePackage: Hashable, Sendable {
  public let path: AndroidPackagePath
  public let revision: AndroidRevision
  /// `<display-name>`. 없으면 path 그대로.
  public let displayName: String
  /// `<uses-license ref>`. 없으면 nil.
  public let licenseID: String?
  /// `<channelRef ref>` 가 가리키는 `<channel>` 이름. channelRef 가 없으면 `.stable` (sdkmanager 기본 channel-0).
  public let channel: AndroidChannel
  /// `obsolete="true"`.
  public let obsolete: Bool
  /// type-details 에 `<api-level>`·`<abi>` 가 모두 있으면 시스템 이미지.
  public let systemImage: AndroidSystemImageDetails?
  public let dependencies: [AndroidPackageDependency]
  /// 필수 값(size·checksum·url)을 모두 갖춘 archive 만, 문서 순서.
  public let archives: [AndroidArchive]

  public init(
    path: AndroidPackagePath,
    revision: AndroidRevision,
    displayName: String,
    licenseID: String?,
    channel: AndroidChannel,
    obsolete: Bool,
    systemImage: AndroidSystemImageDetails?,
    dependencies: [AndroidPackageDependency],
    archives: [AndroidArchive]
  ) {
    self.path = path
    self.revision = revision
    self.displayName = displayName
    self.licenseID = licenseID
    self.channel = channel
    self.obsolete = obsolete
    self.systemImage = systemImage
    self.dependencies = dependencies
    self.archives = archives
  }
}

/// 저장소 XML 해석 실패.
public enum AndroidRepositoryProblem: Error, Hashable, Sendable {
  /// XML 문법이 깨졌다.
  case malformedXML
  /// 루트 요소가 `sdk-repository`·`sdk-sys-img` 가 아니다 (로컬 이름, 접두 무시).
  case unexpectedRoot
  /// `maxByteCount` 를 넘는다.
  case tooLarge
}

/// Google Android SDK 저장소 XML 하나 (`repository2-3.xml` 또는 `sys-img/…/sys-img2-3.xml`).
public struct AndroidRepository: Hashable, Sendable {
  /// 받기·해석 상한. 실측 426 KB 의 약 10 배.
  public static let maxByteCount = 4 * 1024 * 1024

  /// id → 원문. 같은 id 가 여럿이면 처음 것.
  public let licenses: [String: AndroidLicense]
  /// 문서 순서. 필수 값(path·revision)이 없는 패키지는 뺐다.
  public let packages: [AndroidRemotePackage]

  public init(licenses: [String: AndroidLicense], packages: [AndroidRemotePackage]) {
    self.licenses = licenses
    self.packages = packages
  }

  /// 크기 상한 → XML 해석 (Foundation `XMLParser(data:)`, 외부 엔터티를 읽지 않는다). 요소 이름은 네임스페이스 접두를 떼고
  /// 로컬 이름으로 본다. 모르는 요소는 무시한다.
  public init(xmlData data: Data) throws(AndroidRepositoryProblem) {
    guard data.count <= Self.maxByteCount else {
      throw .tooLarge
    }
    self = try AndroidRepositoryReader.read(data)
  }

  /// `init(xmlData:)` 와 같다. 부른 액터(메인)를 막지 않게 `@concurrent` 로 메인 밖에서 돈다.
  @concurrent
  public static func decoded(from data: Data) async throws(AndroidRepositoryProblem) -> AndroidRepository {
    try AndroidRepository(xmlData: data)
  }
}

extension Character {
  /// `0`~`9`·`a`~`f`.
  var isLowercaseHexDigit: Bool {
    self.isASCIIDigit || ("a" ... "f").contains(self)
  }
}
