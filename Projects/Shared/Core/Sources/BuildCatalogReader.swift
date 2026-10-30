import Foundation

/// JSON 값 하나. 숫자는 값이 정수가 되면(1.0·1e0·0.99999999999999999 처럼 Double 로 읽어 정수가 되는 값 포함, Foundation 동작)
/// `.integer`, 아니면 `.number`.
/// 필드마다 없음·null·타입을 구분하고 위치를 붙이려고, Decodable 구조체 대신 값 트리로 받아 직접 검사한다.
/// Int·Double·String·배열·객체 어느 것으로도 읽히지 않는 값(1e400, 짝 없는 서러게이트)은 던지고,
/// 카탈로그 전체가 `.notJSONObject` 가 된다(모르는 필드 안이어도).
enum CatalogJSON: Decodable, Hashable, Sendable {
  /// 값의 중첩 상한. 최상위 객체의 필드 값이 1. 규격 구조는 5 까지 쓴다.
  /// 상한이 없으면 재귀가 512KB 스레드(테스트·cooperative pool)에서 객체 200~250 단계에 스택을 넘겨 앱이 죽는다.
  static let maxDepth = 32

  struct NestingTooDeep: Error {}

  case null
  case bool(Bool)
  case integer(Int)
  case number(Double)
  case string(String)
  case array([CatalogJSON])
  case object([String: CatalogJSON])

  /// JSONDecoder 는 Bool 과 숫자를 서로 바꾸지 않으므로 이 순서로 시도하면 JSON 타입이 그대로 남는다.
  /// 배열 안에서 상한을 넘으면 `try?` 가 오류를 삼키고 객체 디코드의 typeMismatch 로 바뀌지만, 어느 쪽이든 더 내려가지 않는다.
  init(from decoder: any Decoder) throws {
    guard decoder.codingPath.count <= Self.maxDepth else { throw NestingTooDeep() }
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .integer(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([CatalogJSON].self) {
      self = .array(value)
    } else {
      self = try .object(container.decode([String: CatalogJSON].self))
    }
  }
}

/// 값 트리를 docs/CATALOG.md 의 검사 순서로 확인해 `BuildCatalog` 로 바꾼다.
/// 순서: `schemaVersion` → `apps` → 앱을 파일 순서로(`id` → `platform`(schemaVersion 2 만) → id 중복(같은 플랫폼 안)
/// → `name` → `versions` → 버전을 파일 순서로
/// (`id` → id 중복 → `name` → `branch` → `tag` → `buildNumber` → `createdAt` → `buildURL`)).
/// schemaVersion 1 은 앱의 `platform` 을 읽지 않고(모르는 필드처럼 무시) 모두 `.ios` 로 본다.
enum BuildCatalogReader {
  typealias Object = [String: CatalogJSON]
  typealias Field = BuildCatalogProblem.Field
  typealias Position = BuildCatalogProblem.Position

  /// id 의 최대 글자 수.
  static let maxIDLength = 128

  static func catalog(from root: CatalogJSON) throws(BuildCatalogProblem) -> BuildCatalog {
    guard case let .object(object) = root else { throw .notJSONObject }
    let schemaVersion = try self.schemaVersion(object[Field.schemaVersion.rawValue])
    let items = try self.requiredArray(object, .apps, at: .root)
    var apps: [BuildCatalog.App] = []
    var seenAppIDs: Set<String> = []
    for (index, item) in items.enumerated() {
      let position = Position.app(index, id: nil)
      guard case let .object(appObject) = item else { throw .wrongType(.apps, position: position) }
      try apps.append(self.app(appObject, index: index, schemaVersion: schemaVersion, seenIDs: &seenAppIDs))
    }
    return BuildCatalog(schemaVersion: schemaVersion, apps: apps)
  }

  private static func schemaVersion(_ value: CatalogJSON?) throws(BuildCatalogProblem) -> Int {
    switch value {
    case nil, .null?:
      throw .missingField(.schemaVersion, position: .root)
    case let .integer(version)?:
      guard BuildCatalog.supportedSchemaVersions.contains(version) else { throw .unsupportedSchemaVersion(version) }
      return version
    default:
      throw .wrongType(.schemaVersion, position: .root)
    }
  }

  private static func app(
    _ object: Object,
    index: Int,
    schemaVersion: Int,
    seenIDs: inout Set<String>
  ) throws(BuildCatalogProblem) -> BuildCatalog.App {
    let rawID = try self.id(object, at: .app(index, id: nil))
    let position = Position.app(index, id: rawID)
    let platform: BuildCatalogPlatform = if schemaVersion == 1 {
      .ios
    } else {
      try self.platform(object, at: position)
    }
    // 키는 "<platform>:<id 소문자>". 다른 플랫폼의 같은 id 는 중복이 아니다.
    let key = "\(platform.rawValue):\(rawID.lowercased())"
    guard seenIDs.insert(key).inserted else { throw .duplicateAppID(position: position) }
    let name = try self.name(object, at: position)
    let items = try self.requiredArray(object, .versions, at: position)
    var versions: [BuildCatalog.Version] = []
    var seenVersionIDs: Set<String> = []
    for (versionIndex, item) in items.enumerated() {
      let versionPosition = Position.version(versionIndex, id: nil, in: position)
      guard case let .object(versionObject) = item else { throw .wrongType(.versions, position: versionPosition) }
      try versions.append(self.version(versionObject, index: versionIndex, in: position, seenIDs: &seenVersionIDs))
    }
    return BuildCatalog.App(
      id: BuildCatalog.AppID(rawID),
      name: name,
      platform: platform,
      versions: versions.sorted(by: Self.precedes)
    )
  }

  private static func version(
    _ object: Object,
    index: Int,
    in appPosition: Position,
    seenIDs: inout Set<String>
  ) throws(BuildCatalogProblem) -> BuildCatalog.Version {
    let rawID = try self.id(object, at: .version(index, id: nil, in: appPosition))
    let position = Position.version(index, id: rawID, in: appPosition)
    guard seenIDs.insert(rawID.lowercased()).inserted else { throw .duplicateVersionID(position: position) }
    let name = try self.name(object, at: position)
    let branch = try self.optionalString(object, .branch, at: position)
    let tag = try self.optionalString(object, .tag, at: position)
    let buildNumber = try self.optionalString(object, .buildNumber, at: position)
    let rawCreatedAt = try self.requiredString(object, .createdAt, at: position)
    guard let createdAt = self.createdAt(rawCreatedAt) else { throw .invalidCreatedAt(position: position) }
    let buildURL = try self.buildURL(object, at: position)
    return BuildCatalog.Version(
      id: BuildCatalog.VersionID(rawID),
      name: name,
      branch: branch,
      tag: tag,
      buildNumber: buildNumber,
      createdAt: createdAt,
      buildURL: buildURL
    )
  }

  // MARK: - 필드

  /// 없음·null → missingField, 문자열이 아니면 wrongType. 공백은 빼지 않는다.
  static func requiredString(
    _ object: Object,
    _ field: Field,
    at position: Position
  ) throws(BuildCatalogProblem) -> String {
    switch object[field.rawValue] {
    case nil, .null?:
      throw .missingField(field, position: position)
    case let .string(value)?:
      return value
    default:
      throw .wrongType(field, position: position)
    }
  }

  /// 없음·null·앞뒤 공백을 빼면 빈 문자열 → nil. 문자열이 아니면 wrongType. 앞뒤 공백을 뺀 값을 돌려준다.
  static func optionalString(
    _ object: Object,
    _ field: Field,
    at position: Position
  ) throws(BuildCatalogProblem) -> String? {
    switch object[field.rawValue] {
    case nil, .null?:
      return nil
    case let .string(value)?:
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    default:
      throw .wrongType(field, position: position)
    }
  }

  private static func requiredArray(
    _ object: Object,
    _ field: Field,
    at position: Position
  ) throws(BuildCatalogProblem) -> [CatalogJSON] {
    switch object[field.rawValue] {
    case nil, .null?:
      throw .missingField(field, position: position)
    case let .array(items)?:
      return items
    default:
      throw .wrongType(field, position: position)
    }
  }

  /// `id` 를 읽어 형식을 확인한다. 공백을 빼지 않고 적힌 그대로 돌려준다.
  private static func id(_ object: Object, at position: Position) throws(BuildCatalogProblem) -> String {
    let raw = try self.requiredString(object, .id, at: position)
    guard self.isValidID(raw) else { throw .invalidID(position: position) }
    return raw
  }

  /// `platform` 을 공백을 빼지 않고 rawValue 와 정확히 비교한다 (`"iOS"`·`" ios"` 는 거절).
  private static func platform(
    _ object: Object,
    at position: Position
  ) throws(BuildCatalogProblem) -> BuildCatalogPlatform {
    let raw = try self.requiredString(object, .platform, at: position)
    guard let platform = BuildCatalogPlatform(rawValue: raw) else { throw .unsupportedPlatform(position: position) }
    return platform
  }

  /// 앞뒤 공백을 뺀 `name`. 비면 emptyField.
  private static func name(_ object: Object, at position: Position) throws(BuildCatalogProblem) -> String {
    let raw = try self.requiredString(object, .name, at: position)
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw .emptyField(.name, position: position) }
    return trimmed
  }

  private static func buildURL(_ object: Object, at position: Position) throws(BuildCatalogProblem) -> DownloadURL {
    let raw = try self.requiredString(object, .buildURL, at: position)
    if let problem = DownloadURL.problem(in: raw) {
      throw .invalidBuildURL(problem, position: position)
    }
    // problem(in:) 과 init 은 같은 판정을 써서 여기서는 늘 만들어진다.
    guard let url = DownloadURL(raw) else { throw .invalidBuildURL(.malformed, position: position) }
    return url
  }

  // MARK: - 규칙

  /// `^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$`. ASCII 만 받아 중복 비교(`lowercased()`)가 로캘·정규화에 흔들리지 않는다.
  static func isValidID(_ raw: String) -> Bool {
    let scalars = raw.unicodeScalars
    guard let first = scalars.first, scalars.count <= self.maxIDLength, self.isASCIIAlphanumeric(first) else {
      return false
    }
    return scalars.allSatisfy { scalar in
      self.isASCIIAlphanumeric(scalar) || scalar == "." || scalar == "_" || scalar == "-"
    }
  }

  private static func isASCIIAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar {
    case "a" ... "z", "A" ... "Z", "0" ... "9":
      true
    default:
      false
    }
  }
}

// MARK: - 날짜 규칙

extension BuildCatalogReader {
  /// 앞부분 `YYYY-MM-DDTHH:MM:SS`. `0` 자리는 ASCII 숫자, 나머지는 그 글자 그대로.
  private static let dateTimeTemplate = Array("0000-00-00T00:00:00".utf8)
  /// `+`·`-` 뒤의 시간대 `HH:MM`.
  private static let offsetTemplate = Array("00:00".utf8)
  /// 소수 초 자릿수. 10 자리부터는 Foundation 이 읽지 못한다.
  private static let fractionDigitCount = 1 ... 9

  /// `YYYY-MM-DDTHH:MM:SS(.f{1,9})?(Z|[+-]HH:MM)` 이 문자열 전체와 맞는지 본다.
  /// FormatStyle 은 끝 공백·`Zabc`·소문자 `z`·`+09`·`+0900`·자릿수 틀림·`Z+09:00` 까지 받아들여서 글자 형식은 여기서 본다.
  static func hasDateTimeSyntax(_ raw: String) -> Bool {
    let bytes = Array(raw.utf8)
    guard self.matches(bytes, self.dateTimeTemplate, from: 0) else { return false }
    var index = self.dateTimeTemplate.count
    if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
      let fractionStart = index + 1
      index = fractionStart
      while index < bytes.count, self.isDigit(bytes[index]) {
        index += 1
      }
      guard self.fractionDigitCount.contains(index - fractionStart) else { return false }
    }
    guard index < bytes.count else { return false }
    switch bytes[index] {
    case UInt8(ascii: "Z"):
      return index + 1 == bytes.count
    case UInt8(ascii: "+"), UInt8(ascii: "-"):
      return index + 1 + self.offsetTemplate.count == bytes.count
        && self.matches(bytes, self.offsetTemplate, from: index + 1)
    default:
      return false
    }
  }

  private static func matches(_ bytes: [UInt8], _ template: [UInt8], from start: Int) -> Bool {
    guard start + template.count <= bytes.count else { return false }
    for (offset, expected) in template.enumerated() {
      let byte = bytes[start + offset]
      let matched = expected == UInt8(ascii: "0") ? self.isDigit(byte) : byte == expected
      guard matched else { return false }
    }
    return true
  }

  private static func isDigit(_ byte: UInt8) -> Bool {
    (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(byte)
  }

  /// 연도 범위. Foundation 은 1582-10-15 전을 율리우스력으로 읽어 그레고리력 날짜와 어긋나므로 1583 년부터 받는다.
  private static let yearRange = 1583 ... 9999
  /// 시간대 절댓값 상한(분). Foundation 이 읽는 경계 ±18:00 과 같다.
  private static let maxOffsetMinutes = 18 * 60

  /// 글자 형식을 통과한 값(전제)의 숫자 범위: 연도 1583~9999, 달 1~12, 일 1~그 달 마지막 날(윤년 포함), 시 0~23,
  /// 분·초 0~59, 시간대 분 0~59 이면서 ±18:00 이내. Foundation 은 범위를 넘는 시·분·초·일을 다음 단위로 넘겨 읽으므로 여기서 거절한다.
  static func hasValidDateTimeValues(_ raw: String) -> Bool {
    let bytes = Array(raw.utf8)
    let year = self.number(bytes, from: 0, count: 4)
    let month = self.number(bytes, from: 5, count: 2)
    let day = self.number(bytes, from: 8, count: 2)
    guard self.yearRange.contains(year), (1 ... 12).contains(month) else { return false }
    guard (1 ... self.lastDay(ofMonth: month, year: year)).contains(day) else { return false }
    let hour = self.number(bytes, from: 11, count: 2)
    let minute = self.number(bytes, from: 14, count: 2)
    let second = self.number(bytes, from: 17, count: 2)
    guard (0 ... 23).contains(hour), (0 ... 59).contains(minute), (0 ... 59).contains(second) else { return false }
    guard bytes.last != UInt8(ascii: "Z") else { return true }
    // 마지막 6 바이트가 `±HH:MM`.
    let offsetHour = self.number(bytes, from: bytes.count - 5, count: 2)
    let offsetMinute = self.number(bytes, from: bytes.count - 2, count: 2)
    guard (0 ... 59).contains(offsetMinute) else { return false }
    return offsetHour * 60 + offsetMinute <= self.maxOffsetMinutes
  }

  /// 그레고리력 윤년: 4 의 배수, 단 100 의 배수는 평년, 400 의 배수는 윤년.
  static func isLeapYear(_ year: Int) -> Bool {
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
  }

  /// 그 달의 마지막 날 (month 는 1~12 전제).
  static func lastDay(ofMonth month: Int, year: Int) -> Int {
    switch month {
    case 2:
      self.isLeapYear(year) ? 29 : 28
    case 4, 6, 9, 11:
      30
    default:
      31
    }
  }

  /// `bytes[start ..< start + count]` 의 ASCII 숫자를 정수로 (숫자임은 글자 형식이 보장).
  private static func number(_ bytes: [UInt8], from start: Int, count: Int) -> Int {
    var value = 0
    for byte in bytes[start ..< start + count] {
      value = value * 10 + Int(byte - UInt8(ascii: "0"))
    }
    return value
  }

  private static let fractionalSecondsStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
  private static let wholeSecondsStyle = Date.ISO8601FormatStyle()

  /// 글자 형식·값 범위를 확인한 뒤 Foundation 으로 읽는다. 둘 중 하나라도 아니면 nil.
  /// Foundation 은 범위를 넘는 값을 다음 단위로 넘겨 읽으므로 범위는 Core 가 본다.
  /// 소수 초 스타일이 소수 없는 값도 읽지만, 한쪽 관대함에 기대지 않으려고 기본 스타일로 한 번 더 시도한다.
  /// 두 스타일 모두 실패하면 nil 이다(범위를 통과한 값에서 실패한 입력은 실측에 없다, 방어).
  static func createdAt(_ raw: String) -> Date? {
    guard self.hasDateTimeSyntax(raw) else { return nil }
    guard self.hasValidDateTimeValues(raw) else { return nil }
    if let date = try? self.fractionalSecondsStyle.parse(raw) {
      return date
    }
    return try? self.wholeSecondsStyle.parse(raw)
  }

  /// 생성 시각이 늦은 것 먼저, 같으면 id 오름차순(바이트 순서). id 가 앱 안에서 유일해 순서가 하나로 정해진다.
  static func precedes(_ lhs: BuildCatalog.Version, _ rhs: BuildCatalog.Version) -> Bool {
    if lhs.createdAt != rhs.createdAt {
      return lhs.createdAt > rhs.createdAt
    }
    return lhs.id.rawValue < rhs.id.rawValue
  }
}

private extension BuildCatalogProblem.Position {
  static func app(_ index: Int, id: String?) -> Self {
    Self(appIndex: index, appID: id, versionIndex: nil, versionID: nil)
  }

  static func version(_ index: Int, id: String?, in appPosition: Self) -> Self {
    Self(appIndex: appPosition.appIndex, appID: appPosition.appID, versionIndex: index, versionID: id)
  }
}
