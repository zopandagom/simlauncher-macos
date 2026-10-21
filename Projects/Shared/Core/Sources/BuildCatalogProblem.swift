import Foundation

/// 카탈로그 해석에서 걸린 문제. 케이스 순서는 docs/CATALOG.md "앱이 거절하는 경우" 표와 같다. 화면 문구는 Feature 가 정한다.
public enum BuildCatalogProblem: Error, Hashable, Sendable {
  /// JSON 이 아니거나(로그인 HTML·빈 파일·잘못된 UTF-8), 최상위가 객체가 아니거나, 값의 중첩이 32 단계를 넘거나,
  /// 어디에든 읽지 못하는 값(Double 범위를 넘는 큰 숫자·짝 없는 서러게이트가 든 문자열·키)이 있다.
  case notJSONObject
  /// `schemaVersion` 이 이 앱이 모르는 정수(Int 범위)다. 큰 값이면 앱 업데이트가 필요하다.
  case unsupportedSchemaVersion(Int)
  /// 필수 필드가 없거나 null 이다.
  case missingField(Field, position: Position)
  /// 필드 값의 JSON 타입이 다르다 (선택 필드 포함). `apps`·`versions` 의 항목이 객체가 아니면 그 배열 필드로 알린다.
  case wrongType(Field, position: Position)
  /// 필수 문자열(`name`)이 앞뒤 공백을 빼면 비었다.
  case emptyField(Field, position: Position)
  /// id 가 형식(docs/CATALOG.md "id 형식")에 맞지 않는다.
  case invalidID(position: Position)
  /// 앱 id 가 앞 앱과 (대소문자 무시) 같다. 위치는 뒤 앱(인덱스·id).
  case duplicateAppID(position: Position)
  /// 같은 앱 안에서 버전 id 가 앞 버전과 (대소문자 무시) 같다. 위치는 뒤 버전(앱·버전 인덱스와 id).
  case duplicateVersionID(position: Position)
  /// `createdAt` 이 날짜 형식(docs/CATALOG.md "날짜 형식")의 글자 형식이 아니거나 값이 범위 밖이다.
  case invalidCreatedAt(position: Position)
  /// `buildURL` 이 `DownloadURL` 검사에 걸렸다 (상대 주소·http 는 `.notHTTPS`).
  case invalidBuildURL(DownloadURLProblem, position: Position)

  /// rawValue 는 JSON 키.
  public enum Field: String, Hashable, Sendable, CaseIterable {
    case schemaVersion, apps, id, name, versions, branch, tag, buildNumber, createdAt, buildURL
  }

  /// 문제가 난 곳. 인덱스는 파일 순서(0부터), id 는 그 객체의 id 가 형식 검사를 통과했을 때만.
  /// 중복 문제는 뒤 항목의 id 를 담는다 (형식은 통과했으므로).
  public struct Position: Hashable, Sendable {
    public let appIndex: Int?
    public let appID: String?
    public let versionIndex: Int?
    public let versionID: String?

    /// 최상위 객체 (`schemaVersion`·`apps`).
    public static let root = Position(appIndex: nil, appID: nil, versionIndex: nil, versionID: nil)

    public init(appIndex: Int?, appID: String?, versionIndex: Int?, versionID: String?) {
      self.appIndex = appIndex
      self.appID = appID
      self.versionIndex = versionIndex
      self.versionID = versionID
    }
  }
}
