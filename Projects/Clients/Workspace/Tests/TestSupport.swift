import Core
import Foundation
import Synchronization

/// 테스트마다 만드는 임시 폴더. 사진 폴더 자리에 주입하고, 끝나면 `remove()` 로 지운다.
struct TemporaryDirectory {
  /// 심볼릭 링크를 푼 경로 (`/var` → `/private/var`).
  let url: URL

  init() throws {
    let base = FileManager.default.temporaryDirectory.appending(path: "WorkspaceTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    self.url = base.resolvingSymlinksInPath()
  }

  /// 저장 폴더 `<임시 폴더>/SimLauncher` (링크를 풀지 않은 경로).
  var folder: URL {
    self.url.appending(path: "SimLauncher", directoryHint: .isDirectory)
  }

  /// 권한을 뺀 폴더가 있어도 지우도록 폴더마다 소유자 권한을 되돌린 뒤 지운다.
  func remove() {
    if let enumerator = FileManager.default.enumerator(at: self.url, includingPropertiesForKeys: nil) {
      for case let url as URL in enumerator {
        Self.restoreOwnerPermissions(url)
      }
    }
    try? FileManager.default.removeItem(at: self.url)
  }

  /// 링크를 따라가지 않고, 폴더면 소유자 읽기·쓰기·실행 권한을 더한다.
  static func restoreOwnerPermissions(_ url: URL) {
    let path = url.path(percentEncoded: false)
    var info = stat()
    guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
      return
    }
    _ = chmod(path, (info.st_mode & 0o7777) | 0o700)
  }
}

/// `reveal` 클로저가 받은 인자를 기록한다.
final class RevealRecorder: Sendable {
  private let calls = Mutex<[[URL]]>([])

  var received: [[URL]] {
    self.calls.withLock { $0 }
  }

  func record(_ files: [URL]) {
    self.calls.withLock { $0.append(files) }
  }
}

enum Screenshot {
  /// 2026-10-25 05:21:33 UTC.
  static let takenAt = Date(timeIntervalSince1970: 1_792_905_693)

  static func name(_ device: String = "iPhone 17") -> ScreenshotFileName {
    ScreenshotFileName(deviceName: device, runtimeName: "iOS 26.5", takenAt: self.takenAt, timeZone: .gmt)
  }
}

extension URL {
  /// 비교용 부모 폴더 경로 (링크는 풀지 않는다).
  var parentPath: String {
    self.standardizedFileURL.deletingLastPathComponent().path(percentEncoded: false)
  }

  var plainPath: String {
    self.path(percentEncoded: false)
  }
}
