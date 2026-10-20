import CommandInterface
import Core
import Foundation

/// 실행할 명령과 인자·환경, 결과 해석 (순수). `/usr/bin` 아래의 xcrun·xcodebuild shim 은 쓰지 않는다:
/// 개발자 도구가 없는 Mac 에서 Command Line Tools 설치 대화상자를 띄울 수 있다.
enum XcodeCommand {
  static let xcodeSelect = URL(filePath: "/usr/bin/xcode-select")
  static let open = URL(filePath: "/usr/bin/open")
  static let commandLineTools = URL(filePath: "/Library/Developer/CommandLineTools", directoryHint: .isDirectory)
  /// App Store 의 Xcode 페이지 (Mac App Store id 497799835. `open` exit 0, 웹 페이지 title "Xcode App - App Store" 로 확인).
  static let appStoreXcodePage = "macappstore://apps.apple.com/app/id497799835"

  static func printDeveloperDirectory() -> [String] {
    ["-p"]
  }

  /// 고른 Xcode 안의 xcodebuild. `/usr/bin` 의 xcodebuild shim 은 쓰지 않는다.
  static func xcodebuild(in xcode: XcodeInstallation) -> URL {
    xcode.developerDirectory.appending(path: "usr/bin/xcodebuild", directoryHint: .notDirectory)
  }

  /// 0 이면 라이선스 동의와 추가 구성요소 설치가 모두 끝났다. 둘 중 하나라도 남으면 69.
  static func checkFirstLaunchStatus() -> [String] {
    ["-checkFirstLaunchStatus"]
  }

  /// `-license` 와 `check` 는 따로 넘긴다 (한 인자로 주면 잘못된 옵션으로 64).
  static func licenseCheck() -> [String] {
    ["-license", "check"]
  }

  /// `bundlePath` 는 `XcodeInstallation.bundleURL` 의 절대 경로만 넘긴다 (`/` 로 시작해 옵션으로 읽히지 않는다).
  static func openApp(bundlePath: String) -> [String] {
    [bundlePath]
  }

  static func openAppStorePage() -> [String] {
    [self.appStoreXcodePage]
  }

  /// 개발자 디렉터리가 있으면 `DEVELOPER_DIR` 로 넣고, 없으면 물려받은 `DEVELOPER_DIR` 를 지운다.
  /// xcode-select -p 는 `DEVELOPER_DIR` 를 검증 없이 그대로 출력하므로 반드시 지운 환경에서 실행한다.
  static func environment(base: [String: String], developerDirectory: URL?) -> [String: String] {
    var environment = base
    if let developerDirectory {
      environment["DEVELOPER_DIR"] = developerDirectory.path(percentEncoded: false)
    } else {
      environment["DEVELOPER_DIR"] = nil
    }
    return environment
  }

  /// xcode-select -p 결과에서 개발자 디렉터리. 종료 코드 0, UTF-8, 앞뒤 공백·개행 제거, `/` 로 시작해야 한다. 아니면 nil.
  static func selectedDeveloperDirectory(from result: CommandResult) -> URL? {
    guard result.exitCode == 0, let text = String(bytes: result.stdout, encoding: .utf8) else {
      return nil
    }
    let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard path.hasPrefix("/") else {
      return nil
    }
    return URL(filePath: path, directoryHint: .isDirectory)
  }

  /// 개발자 디렉터리가 `<X>.app/Contents/Developer` 꼴이면 `<X>.app`. 아니면 nil. (경로 모양만 본다)
  static func xcodeBundle(forDeveloperDirectory directory: URL) -> URL? {
    let components = directory.standardizedFileURL.pathComponents
    guard
      components.count >= 4,
      components[components.count - 1] == "Developer",
      components[components.count - 2] == "Contents",
      components[components.count - 3].lowercased().hasSuffix(".app")
    else {
      return nil
    }
    return directory.standardizedFileURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  /// 표준화한 경로가 CommandLineTools 와 같거나 그 아래인지.
  static func isCommandLineTools(_ directory: URL) -> Bool {
    let path = directory.standardizedFileURL.pathComponents
    let base = Self.commandLineTools.pathComponents
    return path.starts(with: base)
  }

  /// -checkFirstLaunchStatus·-license check 종료 코드 해석: 0 이면 true, 그 밖(69 포함)은 false.
  static func passed(_ result: CommandResult) -> Bool {
    result.exitCode == 0
  }
}
