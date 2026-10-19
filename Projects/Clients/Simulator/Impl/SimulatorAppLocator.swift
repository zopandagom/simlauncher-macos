import Foundation

/// 개발자 디렉터리에서 Simulator 앱 위치를 찾는다 (순수).
enum SimulatorAppLocator {
  /// `xcode-select -p` 출력에서 개발자 디렉터리. 앞뒤 공백·개행을 자르고, 비었거나 절대 경로가 아니면 nil.
  static func developerDirectory(fromXcodeSelectOutput output: Data) -> URL? {
    guard
      let text = String(bytes: output, encoding: .utf8),
      case let path = text.trimmingCharacters(in: .whitespacesAndNewlines),
      path.hasPrefix("/")
    else { return nil }
    return URL(filePath: path, directoryHint: .isDirectory)
  }

  /// 확인할 순서대로의 후보. 처음 존재하는 것을 연다.
  /// 1. `<개발자 디렉터리>/Applications/Simulator.app` (Xcode 26 이하, 미확인)
  /// 2. `<개발자 디렉터리>/../Applications/DeviceHub.app` = `Xcode.app/Contents/Applications/DeviceHub.app` (Xcode 27.1 확인)
  static func candidates(developerDirectory: URL) -> [URL] {
    [
      developerDirectory.appending(path: "Applications/Simulator.app", directoryHint: .isDirectory),
      developerDirectory.deletingLastPathComponent()
        .appending(path: "Applications/DeviceHub.app", directoryHint: .isDirectory),
    ]
  }
}
