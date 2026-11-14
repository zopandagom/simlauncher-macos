import Core
import Foundation
import SimulatorInterface

/// `simctl ui` 항목 (인자 토큰).
enum SimctlUIOption: String, CaseIterable {
  case appearance
  case contentSize = "content_size"
  case increaseContrast = "increase_contrast"
}

/// `simctl ui` 쓰기 토큰과 읽기 해석 (순수).
/// 읽기는 stdout 한 줄을 앞뒤 공백을 빼고 소문자로 맞춰 본다: `content_size` 읽기 값은 대소문자가 쓰기 값과 다를 수 있다
/// (`extra-Small`·`Small`, 실측). 알려진 값 → `.value`, `unsupported` → `.unsupported`, 그 밖(`unknown`·빈 값·모르는 값) →
/// `.unknown`.
enum SimctlUIParser {
  /// 쓰기 항목과 값 토큰.
  static func write(_ setting: IOSDisplaySetting) -> (option: SimctlUIOption, value: String) {
    switch setting {
    case let .appearance(appearance):
      (.appearance, appearance == .dark ? "dark" : "light")
    case let .contentSize(size):
      (.contentSize, size.rawValue)
    case let .increaseContrast(enabled):
      (.increaseContrast, enabled ? "enabled" : "disabled")
    }
  }

  static func appearance(_ stdout: Data) -> IOSSettingReading<DeviceAppearance> {
    self.reading(stdout, values: ["light": .light, "dark": .dark])
  }

  static func contentSize(_ stdout: Data) -> IOSSettingReading<IOSContentSize> {
    self.reading(stdout, values: Dictionary(uniqueKeysWithValues: IOSContentSize.allCases.map { ($0.rawValue, $0) }))
  }

  static func increaseContrast(_ stdout: Data) -> IOSSettingReading<Bool> {
    self.reading(stdout, values: ["enabled": true, "disabled": false])
  }

  /// 쓰기 뒤 다시 읽은 값의 그 항목이 요청 값이면 `.applied`, 아니면 `.notApplied(read)`.
  static func outcome(of setting: IOSDisplaySetting, read: IOSDisplaySettings) -> IOSDisplaySettingOutcome {
    let applied = switch setting {
    case let .appearance(value): read.appearance == .value(value)
    case let .contentSize(value): read.contentSize == .value(value)
    case let .increaseContrast(value): read.increaseContrast == .value(value)
    }
    return applied ? .applied : .notApplied(read)
  }

  /// 셋 다 `.unknown` (꺼진 기기의 읽기와 같다).
  static func isAllUnknown(_ settings: IOSDisplaySettings) -> Bool {
    settings.appearance == .unknown && settings.contentSize == .unknown && settings.increaseContrast == .unknown
  }

  private static func reading<Value>(_ stdout: Data, values: [String: Value]) -> IOSSettingReading<Value> {
    let text = (String(bytes: stdout, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    if let value = values[text] {
      return .value(value)
    }
    return text == "unsupported" ? .unsupported : .unknown
  }
}
