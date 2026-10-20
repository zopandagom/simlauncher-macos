import Core
import Foundation

/// Xcode 번들 후보와 Info.plist 해석 (순수). 파일 읽기는 `DevEnvironmentClientImpl` 이 한다.
enum XcodeBundleReader {
  static let xcodeBundleID = "com.apple.dt.Xcode"

  /// 폴더 맨 위 항목 중 확장자가 `.app`(대소문자 무시)인 것. 순서는 그대로 둔다.
  static func candidates(_ entries: [URL]) -> [URL] {
    entries.filter { $0.pathExtension.lowercased() == "app" }
  }

  /// Info.plist(XML·바이너리)가 사전이고 `CFBundleIdentifier` 가 Xcode(베타도 같다)이며
  /// `CFBundleShortVersionString` 이 `OSVersion(_:)` 으로 읽히면 그 Xcode. 아니면 nil.
  static func installation(bundleURL: URL, infoPlist: Data) -> XcodeInstallation? {
    guard
      let plist = try? PropertyListSerialization.propertyList(from: infoPlist, format: nil),
      let dictionary = plist as? [String: Any],
      dictionary["CFBundleIdentifier"] as? String == xcodeBundleID,
      let versionString = dictionary["CFBundleShortVersionString"] as? String,
      let version = OSVersion(versionString)
    else {
      return nil
    }
    return XcodeInstallation(bundleURL: bundleURL, version: version)
  }

  /// iOS Simulator SDK `SDKSettings.plist` 의 `Version` (예: "27.1"). 사전이 아니거나 읽지 못하면 nil.
  static func sdkVersion(settings: Data) -> OSVersion? {
    guard let version = string("Version", in: settings) else {
      return nil
    }
    return OSVersion(version)
  }

  /// SDK `SystemVersion.plist` 의 `ProductBuildVersion` (예: "24A94232"). 비었거나 읽지 못하면 nil.
  static func sdkBuild(systemVersion: Data) -> String? {
    guard let build = string("ProductBuildVersion", in: systemVersion), !build.isEmpty else {
      return nil
    }
    return build
  }

  private static func string(_ key: String, in plistData: Data) -> String? {
    guard
      let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil),
      let dictionary = plist as? [String: Any]
    else {
      return nil
    }
    return dictionary[key] as? String
  }

  /// `bundleURL` 경로 문자열이 같은 것은 먼저 나온 하나만 남긴다 (링크로 찾은 같은 번들을 합친다).
  static func unique(_ installations: [XcodeInstallation]) -> [XcodeInstallation] {
    var seen: Set<String> = []
    return installations.filter { seen.insert($0.bundleURL.path(percentEncoded: false)).inserted }
  }
}
