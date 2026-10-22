import Foundation

/// 사용자가 등록한 빌드 카탈로그(`catalog.json`, 규격 docs/CATALOG.md) 하나를 해석한 값.
public struct BuildCatalog: Hashable, Sendable {
  /// 이 앱이 읽는 규격 버전.
  public static let supportedSchemaVersion = 1
  /// 카탈로그 파일 크기 상한 (5 MiB). 받는 쪽(Settings 의 등록 확인·4-E)이 `DownloadClient.fetchData` 의 `maxBytes` 로 넘긴다.
  public static let maxByteCount = 5 * 1024 * 1024

  /// 파일 순서.
  public let apps: [App]

  /// Preview·테스트용. 검증·정렬은 `init(jsonData:)` 만 한다.
  public init(apps: [App]) {
    self.apps = apps
  }

  /// 규격대로 해석한다. 문서 순서(docs/CATALOG.md "앱이 거절하는 경우")로 처음 만난 문제 하나를 던진다.
  /// 5 MiB 에서 약 0.3초 걸리는 동기 함수라 메인 액터 밖에서 부른다.
  public init(jsonData: Data) throws(BuildCatalogProblem) {
    let root: CatalogJSON
    do {
      root = try JSONDecoder().decode(CatalogJSON.self, from: jsonData)
    } catch {
      throw .notJSONObject
    }
    self = try BuildCatalogReader.catalog(from: root)
  }
}

public extension BuildCatalog {
  /// 앱 id. 형식은 docs/CATALOG.md "id 형식". `App` 안에 두면 SwiftLint nesting(1단계까지)에 걸려 여기에 둔다.
  struct AppID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }
  }

  /// 버전 id. 같은 앱 안에서만 유일하다.
  struct VersionID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
      self.rawValue = rawValue
    }
  }

  /// 카탈로그의 앱 하나.
  struct App: Identifiable, Hashable, Sendable {
    public let id: BuildCatalog.AppID
    /// 앞뒤 공백을 뺀 이름.
    public let name: String
    /// 생성 시각 최신순, 같으면 id 오름차순.
    public let versions: [Version]

    /// Preview·테스트용. 정렬하지 않는다.
    public init(id: BuildCatalog.AppID, name: String, versions: [Version]) {
      self.id = id
      self.name = name
      self.versions = versions
    }
  }

  /// 앱의 빌드 하나. 문자열은 앞뒤 공백을 뺀 값이고, 선택 필드는 없거나 비면 nil.
  struct Version: Identifiable, Hashable, Sendable {
    public let id: BuildCatalog.VersionID
    public let name: String
    public let branch: String?
    public let tag: String?
    public let buildNumber: String?
    public let createdAt: Date
    /// 검사를 통과한 https 주소. 그대로 `DownloadClient.download` 에 넘긴다.
    public let buildURL: DownloadURL

    public init(
      id: BuildCatalog.VersionID,
      name: String,
      branch: String?,
      tag: String?,
      buildNumber: String?,
      createdAt: Date,
      buildURL: DownloadURL
    ) {
      self.id = id
      self.name = name
      self.branch = branch
      self.tag = tag
      self.buildNumber = buildNumber
      self.createdAt = createdAt
      self.buildURL = buildURL
    }
  }
}
