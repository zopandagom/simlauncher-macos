import AppBundleInterface
import Core
import Foundation

/// Info.plist 에서 읽은 값. 표시 이름의 파일 이름 대체와 실행 파일 읽기는 `AppBundleClientImpl` 이 한다.
struct InfoPlistFields: Hashable, Sendable {
  let bundleID: AppBundleID
  /// CFBundleExecutable. `/`·NUL 이 없고 `.`·`..` 가 아닌 파일 이름.
  let executableName: String
  /// CFBundleDisplayName → CFBundleName 순서. 둘 다 없거나 비었으면 nil.
  let displayName: String?
  let version: String?
  let build: String?
  let platforms: Set<AppBundlePlatform>?
  let minimumOSVersion: OSVersion?
}

/// Info.plist(XML·바이너리)를 읽는다 (순수). 값은 신뢰할 수 없는 입력으로 다룬다.
enum InfoPlistReader {
  /// 사전이 아니거나 읽지 못하면, 번들 ID 가 없거나 `AppBundleID` 형식이 아니면,
  /// 실행 파일 이름이 없거나, `/`·NUL 을 포함하거나 정확히 `.`·`..` 면 `.invalidBundle`.
  static func fields(from data: Data) throws(AppBundleError) -> InfoPlistFields {
    let plist: Any
    do {
      plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    } catch {
      throw .invalidBundle
    }
    guard
      let dictionary = plist as? [String: Any],
      let rawBundleID = dictionary["CFBundleIdentifier"] as? String,
      let bundleID = AppBundleID(rawBundleID),
      let executableName = dictionary["CFBundleExecutable"] as? String,
      Self.isPlainFileName(executableName)
    else {
      throw .invalidBundle
    }
    return InfoPlistFields(
      bundleID: bundleID,
      executableName: executableName,
      displayName: Self.nonEmptyString(dictionary["CFBundleDisplayName"])
        ?? Self.nonEmptyString(dictionary["CFBundleName"]),
      version: dictionary["CFBundleShortVersionString"] as? String,
      build: dictionary["CFBundleVersion"] as? String,
      platforms: Self.platforms(dictionary["CFBundleSupportedPlatforms"]),
      minimumOSVersion: (dictionary["MinimumOSVersion"] as? String).flatMap(OSVersion.init)
    )
  }

  /// 키가 없으면 nil. 문자열 배열이 아니면 빈 집합 (시뮬레이터용으로 보지 않는다).
  private static func platforms(_ value: Any?) -> Set<AppBundlePlatform>? {
    guard let value else { return nil }
    guard let names = value as? [String] else { return [] }
    return Set(names.map(AppBundlePlatform.init(bundlePlatform:)))
  }

  private static func nonEmptyString(_ value: Any?) -> String? {
    guard let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return nil
    }
    return string
  }

  /// 번들 폴더 밖이나 하위 폴더를 가리키지 않는 이름. `A..B`·`.hidden` 같은 이름은 받는다.
  private static func isPlainFileName(_ name: String) -> Bool {
    !name.isEmpty && !name.contains("/") && !name.contains("\0") && name != "." && name != ".."
  }
}
