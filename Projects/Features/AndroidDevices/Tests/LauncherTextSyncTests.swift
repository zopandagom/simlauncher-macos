import Foundation
import Testing
@testable import AndroidDevicesFeature

/// URL·카탈로그에서 설치의 공유 문구(행·URL 시트 공통 문구, 받기 실패 전부, 카탈로그 시트·카탈로그 읽기 실패 전부)는 iOS 기기 목록
/// (Launcher)과 같은 키·값으로 이 모듈에도 둔다 (Feature 끼리 의존하지 않기 위해, ARCHITECTURE §4 화면 문자열 행). 이 테스트는
/// Launcher 원본 String Catalog 를 소스 경로로 읽어 (a) 공유 키가 Launcher 와 이 모듈의 원본 카탈로그에 모두 있고 ko 값이 같은지,
/// (b) 이 모듈 문구 함수의 결과가 Launcher 값으로 만든 문구와 같은지 본다. 키가 한국어 원문이라 Launcher 가 문구를 고치면 키가 바뀌어
/// (a) 가 실패하고, 이 모듈만 고치면 (b) 가 실패한다. Settings 와의 조각 동기화는 Launcher 의 `CatalogFragmentSyncTests` 가 맡는다.
struct LauncherTextSyncTests {
  /// 이 파일 기준의 이 모듈 String Catalog 경로.
  static let androidCatalog = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "../Sources/Localizable.xcstrings")
    .standardized

  /// String Catalog(JSON)의 키 → ko 값.
  static func koreanTable(at url: URL) throws -> [String: String] {
    let data = try Data(contentsOf: url)
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let strings = try #require(root["strings"] as? [String: Any])
    var table: [String: String] = [:]
    for (key, entry) in strings {
      let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any]
      let unit = (localizations?["ko"] as? [String: Any])?["stringUnit"] as? [String: Any]
      if let value = unit?["value"] as? String {
        table[key] = value
      }
    }
    return table
  }

  @Test("공유 문구 102개가 Launcher 원본과 이 모듈 원본에 같은 키·값으로 있고, 문구 함수의 결과가 Launcher 값으로 만든 문구와 같다")
  func sharedTextsMatchLauncher() throws {
    let launcher = try Self.koreanTable(at: NameProblemSyncTests.launcherCatalog)
    let android = try Self.koreanTable(at: Self.androidCatalog)
    #expect(!launcher.isEmpty)
    let checks = DownloadTextCatalog.sharedChecks(launcher)

    #expect(Set(checks.map(\.key)).count == 102)
    for check in checks {
      #expect(launcher[check.key] == check.key, "Launcher 에 없거나 다른 값: \(check.key)")
      #expect(android[check.key] == launcher[check.key], "이 모듈에 없거나 다른 값: \(check.key)")
      #expect(check.actual == check.expected, "\(check.key)")
    }
  }

  @Test("스크린샷·녹화 공유 문구 25개가 Launcher 원본과 이 모듈 원본에 같은 키·값으로 있고, 문구 함수의 결과가 Launcher 값과 같다")
  func sharedCaptureTextsMatchLauncher() throws {
    let launcher = try Self.koreanTable(at: NameProblemSyncTests.launcherCatalog)
    let android = try Self.koreanTable(at: Self.androidCatalog)
    let checks = CaptureTextCatalog.sharedChecks(launcher)

    #expect(Set(checks.map(\.key)).count == 25)
    for check in checks {
      #expect(launcher[check.key] == check.key, "Launcher 에 없거나 다른 값: \(check.key)")
      #expect(android[check.key] == launcher[check.key], "이 모듈에 없거나 다른 값: \(check.key)")
      #expect(check.actual == check.expected, "\(check.key)")
    }
  }

  @Test("여러 기기 설치 공유 문구 12개가 Launcher 원본과 이 모듈 원본에 같은 키·값으로 있고, 문구 함수의 결과가 Launcher 값과 같다")
  func sharedBatchTextsMatchLauncher() throws {
    let launcher = try Self.koreanTable(at: NameProblemSyncTests.launcherCatalog)
    let android = try Self.koreanTable(at: Self.androidCatalog)
    let checks = BatchTextCatalog.sharedChecks(launcher)

    #expect(Set(checks.map(\.key)).count == 12)
    for check in checks {
      #expect(launcher[check.key] == check.key, "Launcher 에 없거나 다른 값: \(check.key)")
      #expect(android[check.key] == launcher[check.key], "이 모듈에 없거나 다른 값: \(check.key)")
      #expect(check.actual == check.expected, "\(check.key)")
    }
  }

  @Test("Android 문장은 Launcher 에 같은 키가 없다 (공유로 잘못 옮기지 않았다)")
  func androidTextsAreOwn() throws {
    let launcher = try Self.koreanTable(at: NameProblemSyncTests.launcherCatalog)
    let android = try Self.koreanTable(at: Self.androidCatalog)
    let checks = DownloadTextCatalog.androidChecks(android) + CaptureTextCatalog.androidChecks(android)
      + BatchTextCatalog.androidChecks(android)
    for check in checks {
      #expect(launcher[check.key] == nil, "\(check.key)")
    }
  }
}
