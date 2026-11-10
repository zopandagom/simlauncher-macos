import Core
import Foundation
import SimulatorInterface

/// `xcrun simctl spawn <기기> launchctl list` 출력에서 떠 있는 앱의 번들 ID 를 읽는다 (순수).
/// 출력은 탭으로 나눈 `PID\tStatus\tLabel` 줄이다 (첫 줄은 머리말). 떠 있는 앱의 레이블은
/// `UIKitApplication:<번들 ID>[<짧은 ID>][rb-legacy]` 모양이다 (Xcode 27.2, iOS 27.0 실측:
/// `78490\t0\tUIKitApplication:com.apple.mobilecal[7e9f][rb-legacy]`).
/// 다른 레이블(`com.apple.progressd` 등)·머리말·탭이 모자란 줄은 건너뛴다.
enum SimctlLaunchctlParser {
  private static let applicationLabelPrefix = "UIKitApplication:"

  /// UTF-8 이 아니면 `.unexpectedOutput`. 세 번째 칸이 `UIKitApplication:` 로 시작하면 그 뒤에서 첫 `[` 앞까지(없으면 끝까지)를
  /// `AppBundleID` 로 읽고, 형식 밖이면 뺀다 (그 값이 다른 simctl 인자로 갈 수 있으므로). SimLauncher 레이아웃 러너
  /// (`IOSLayoutRunner.appBundleID`)도 뺀다. 결과는 중복 없이 rawValue 오름차순.
  static func runningApplications(from data: Data) throws(SimulatorError) -> [AppBundleID] {
    guard let text = String(bytes: data, encoding: .utf8) else {
      throw .unexpectedOutput
    }
    var bundleIDs: Set<String> = []
    for line in text.split(whereSeparator: \.isNewline) {
      let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
      guard columns.count >= 3 else { continue }
      let label = columns[2]
      guard label.hasPrefix(Self.applicationLabelPrefix) else { continue }
      let rest = label.dropFirst(Self.applicationLabelPrefix.count)
      let raw = String(rest.prefix { $0 != "[" })
      guard raw != IOSLayoutRunner.appBundleID, AppBundleID(raw) != nil else { continue }
      bundleIDs.insert(raw)
    }
    return bundleIDs.sorted().compactMap(AppBundleID.init)
  }
}
