import Core
import Foundation
import SimulatorInterface

/// `xcrun simctl listapps <기기>` 출력을 `[InstalledApp]` 로 바꾼다 (순수).
/// 출력은 OpenStep plist 이고 최상위는 번들 ID → 정보 사전이다 (Xcode 27, iOS 27.0·27.1 실측). 정보 사전의 값은 대부분 문자열
/// (`IsHidden = "0"` 등)이지만 `GroupContainers` 는 사전, `SBAppTags` 는 배열이라 필요한 키만 문자열로 읽고 나머지는 보지 않는다.
enum SimctlAppListDecoder {
  /// 최상위가 사전이 아니거나 plist 가 아니면 `.unexpectedOutput`.
  /// `ApplicationType` 이 `User` 인 항목만, 번들 ID 는 최상위 키를 `AppBundleID` 로 읽어 형식 밖이면 뺀다
  /// (그 값이 `simctl launch` 인자로 가므로). 정보가 사전이 아닌 항목도 뺀다.
  /// 결과는 표시 이름(`localizedStandardCompare`) → 번들 ID 순이다.
  static func apps(from data: Data) throws(SimulatorError) -> [InstalledApp] {
    let root: Any
    do {
      root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    } catch {
      throw .unexpectedOutput
    }
    guard let entries = root as? [String: Any] else {
      throw .unexpectedOutput
    }
    var apps: [InstalledApp] = []
    for (key, value) in entries {
      if let info = value as? [String: Any], let app = Self.app(key: key, info: info) {
        apps.append(app)
      }
    }
    return apps.sorted(by: Self.precedes)
  }

  private static func app(key: String, info: [String: Any]) -> InstalledApp? {
    guard info["ApplicationType"] as? String == "User", let bundleID = AppBundleID(key) else { return nil }
    let name = Self.nonEmptyString(info["CFBundleDisplayName"])
      ?? Self.nonEmptyString(info["CFBundleName"])
      ?? bundleID.rawValue
    return InstalledApp(
      bundleID: bundleID,
      displayName: name,
      version: Self.nonEmptyString(info["CFBundleShortVersionString"]),
      build: Self.nonEmptyString(info["CFBundleVersion"])
    )
  }

  private static func nonEmptyString(_ value: Any?) -> String? {
    guard let string = value as? String, !string.isEmpty else { return nil }
    return string
  }

  private static func precedes(_ lhs: InstalledApp, _ rhs: InstalledApp) -> Bool {
    switch lhs.displayName.localizedStandardCompare(rhs.displayName) {
    case .orderedAscending: true
    case .orderedDescending: false
    case .orderedSame: lhs.bundleID.rawValue < rhs.bundleID.rawValue
    }
  }
}
