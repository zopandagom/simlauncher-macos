import Core
import Foundation
import SimulatorInterface
import Testing
@testable import SimulatorImpl

/// `simctl spawn <기기> launchctl list` 출력 해석. 줄은 Xcode 27.2·iOS 27.0 실측 모양을 따라 직접 쓴 것이다.
struct SimctlLaunchctlParserTests {
  private static func parse(_ lines: [String]) throws -> [String] {
    try SimctlLaunchctlParser.runningApplications(from: Data(lines.joined(separator: "\n").utf8)).map(\.rawValue)
  }

  @Test("UIKitApplication 레이블에서 첫 [ 앞까지를 번들 ID 로 읽고, 머리말·다른 레이블은 건너뛴다")
  func extractsApplications() throws {
    let ids = try Self.parse([
      "PID\tStatus\tLabel",
      "78490\t0\tUIKitApplication:com.apple.mobilecal[7e9f][rb-legacy]",
      "-\t0\tcom.apple.progressd",
      "1234\t0\tUIKitApplication:com.example.app[a1b2][rb-legacy]",
    ])

    #expect(ids == ["com.apple.mobilecal", "com.example.app"])
  }

  @Test("[ 가 없는 레이블은 끝까지가 번들 ID")
  func labelWithoutBracket() throws {
    #expect(try Self.parse(["1\t0\tUIKitApplication:com.example.plain"]) == ["com.example.plain"])
  }

  @Test("같은 앱이 여러 줄이어도 한 번, rawValue 오름차순")
  func deduplicatesAndSorts() throws {
    let ids = try Self.parse([
      "3\t0\tUIKitApplication:com.example.b[1][rb-legacy]",
      "1\t0\tUIKitApplication:com.example.a[2][rb-legacy]",
      "-\t0\tUIKitApplication:com.example.b[3][rb-legacy]",
    ])

    #expect(ids == ["com.example.a", "com.example.b"])
  }

  @Test("SimLauncher 레이아웃 러너는 빼고, 다른 UI 테스트 러너는 남긴다")
  func excludesLayoutRunner() throws {
    let ids = try Self.parse([
      "5\t0\tUIKitApplication:\(IOSLayoutRunner.appBundleID)[9][rb-legacy]",
      "6\t0\tUIKitApplication:com.example.uitests.xctrunner[8][rb-legacy]",
    ])

    #expect(ids == ["com.example.uitests.xctrunner"])
  }

  @Test(
    "AppBundleID 형식이 아닌 ID 는 뺀다",
    arguments: [
      "UIKitApplication:",
      "UIKitApplication:[7e9f]",
      "UIKitApplication:-h[1]",
      "UIKitApplication:com.example/../x[1]",
      "UIKitApplication:com example[1]",
    ]
  )
  func excludesInvalidIDs(label: String) throws {
    #expect(try Self.parse(["1\t0\t\(label)"]).isEmpty)
  }

  @Test("탭이 모자란 줄·빈 줄·빈 출력은 건너뛴다")
  func ignoresMalformedLines() throws {
    #expect(try Self.parse(["UIKitApplication:com.example.a", "1 0 UIKitApplication:com.example.b", ""]).isEmpty)
    #expect(try SimctlLaunchctlParser.runningApplications(from: Data()).isEmpty)
  }

  @Test("UTF-8 이 아니면 unexpectedOutput")
  func notUTF8() {
    #expect(throws: SimulatorError.unexpectedOutput) {
      try SimctlLaunchctlParser.runningApplications(from: Data([0xFF, 0xFE, 0x09]))
    }
  }
}
