import CommandInterface
import CommandTesting
import Core
import Foundation
import Testing

/// 테스트마다 만드는 임시 폴더. 끝나면 `remove()` 로 지운다.
/// `Applications/` 는 테스트용 앱 폴더, `Elsewhere/` 는 앱 폴더 밖 위치다.
struct TemporaryDirectory {
  /// 링크를 풀지 않은 경로 (`/var/folders/…`). 기대값은 `real(_:)` 로 만든다.
  let url: URL

  init() throws {
    self.url = FileManager.default.temporaryDirectory
      .appending(path: "DevEnvironmentTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: self.applications, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: self.elsewhere, withIntermediateDirectories: true)
  }

  var applications: URL {
    self.url.appending(path: "Applications", directoryHint: .isDirectory)
  }

  var elsewhere: URL {
    self.url.appending(path: "Elsewhere", directoryHint: .isDirectory)
  }

  func remove() {
    try? FileManager.default.removeItem(at: self.url)
  }

  /// `folder` 안에 가짜 Xcode 번들 `<name>` 을 만든다: `Contents/Info.plist`(nil 이면 없음)와
  /// `Contents/Developer` 안의 실행 가능한 `usr/bin/xcodebuild`(false 면 없음).
  @discardableResult
  func makeXcode(
    _ name: String = "Xcode.app",
    in folder: URL? = nil,
    version: String = "27.1",
    identifier: String = "com.apple.dt.Xcode",
    format: PropertyListSerialization.PropertyListFormat = .xml,
    infoPlist: Bool = true,
    xcodebuild: Bool = true
  ) throws -> URL {
    let bundle = (folder ?? self.applications).appending(path: name, directoryHint: .isDirectory)
    let contents = bundle.appending(path: "Contents", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    if infoPlist {
      let plist: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleShortVersionString": version]
      let data = try PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0)
      try data.write(to: contents.appending(path: "Info.plist"))
    }
    if xcodebuild {
      let bin = contents.appending(path: "Developer/usr/bin", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
      let tool = bin.appending(path: "xcodebuild")
      try Data("#!/bin/sh\n".utf8).write(to: tool)
      try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path(percentEncoded: false))
    }
    return bundle
  }

  /// `target` 을 가리키는 링크 `folder/<name>`.
  @discardableResult
  func link(_ name: String, in folder: URL? = nil, to target: URL) throws -> URL {
    let link = (folder ?? self.applications).appending(path: name, directoryHint: .notDirectory)
    try FileManager.default.createSymbolicLink(
      atPath: link.path(percentEncoded: false),
      withDestinationPath: target.path(percentEncoded: false)
    )
    return link
  }

  /// 번들 URL 의 realpath 로 만든 기대값.
  func installation(_ bundle: URL, _ major: Int, _ minor: Int = 0) throws -> XcodeInstallation {
    let path = try #require(RealPath.of(bundle))
    return XcodeInstallation(
      bundleURL: URL(filePath: path, directoryHint: .isDirectory),
      version: OSVersion(major: major, minor: minor)
    )
  }
}

enum RealPath {
  static func of(_ url: URL) -> String? {
    guard let resolved = realpath(url.path(percentEncoded: false), nil) else {
      return nil
    }
    defer { free(resolved) }
    return String(cString: resolved)
  }
}

/// 실행 파일별 결과를 정하는 `CommandClientFake`.
enum Responder {
  enum Outcome: Sendable {
    case exit(Int32, String = "")
    case launchFailed
  }

  /// xcode-select 는 `select`, xcodebuild 는 인자에 따라 `firstLaunch`·`license`, open 은 `open`.
  static func command(
    select: Outcome,
    firstLaunch: Outcome = .exit(0),
    license: Outcome = .exit(0),
    open: Outcome = .exit(0)
  ) -> CommandClientFake {
    CommandClientFake { invocation throws(CommandError) in
      let outcome: Outcome
      switch invocation.executable.lastPathComponent {
      case "xcode-select":
        outcome = select
      case "xcodebuild":
        outcome = invocation.arguments == ["-license", "check"] ? license : firstLaunch
      case "open":
        outcome = open
      default:
        Issue.record("부르지 않아야 할 명령: \(invocation.executable.path(percentEncoded: false))")
        throw .launchFailed
      }
      switch outcome {
      case let .exit(code, stdout):
        return CommandResult(exitCode: code, stdout: Data(stdout.utf8), stderr: Data())
      case .launchFailed:
        throw .launchFailed
      }
    }
  }

  /// xcode-select -p 가 `developerDirectory` 를 출력한다.
  static func selecting(_ developerDirectory: URL) -> Outcome {
    .exit(0, developerDirectory.path(percentEncoded: false) + "\n")
  }

  static let commandLineTools = Outcome.exit(0, "/Library/Developer/CommandLineTools\n")
}

extension CommandClientFake {
  var executables: [String] {
    self.invocations.map(\.executable.lastPathComponent)
  }
}
