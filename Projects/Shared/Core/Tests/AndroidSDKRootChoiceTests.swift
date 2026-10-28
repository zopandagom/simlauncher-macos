import Foundation
import Testing
@testable import Core

struct AndroidSDKRootChoiceTests {
  static let home = URL(filePath: "/Users/u", directoryHint: .isDirectory)

  static func path(_ choice: AndroidSDKRootChoice) -> String? {
    guard case let .root(root) = choice else {
      return nil
    }
    return root.url.path(percentEncoded: false)
  }

  static func isDefault(_ choice: AndroidSDKRootChoice) -> Bool? {
    guard case let .root(root) = choice else {
      return nil
    }
    return root.isDefault
  }

  @Test("키 없음 → 기본 위치 home/Library/Android/sdk, isDefault")
  func absent() {
    let choice = AndroidSDKRootChoice.resolve(.absent, home: Self.home)
    #expect(Self.path(choice) == "/Users/u/Library/Android/sdk/")
    #expect(Self.isDefault(choice) == true)
    #expect(choice == .root(AndroidSDKRoot(url: AndroidSDKRoot.defaultURL(home: Self.home), isDefault: true)))
  }

  @Test("절대 경로·~/ 경로, .. 는 푼다, 앞뒤 공백은 뺀다", arguments: [
    ("/Volumes/Tools/SDK", "/Volumes/Tools/SDK/"),
    ("~/x", "/Users/u/x/"),
    ("~/", "/Users/u/"),
    ("/a/../b", "/b/"),
    ("  /Volumes/T  \n", "/Volumes/T/"),
    ("/a/./b/", "/a/b/"),
  ])
  func paths(raw: String, expected: String) {
    let choice = AndroidSDKRootChoice.resolve(.path(raw), home: Self.home)
    #expect(Self.path(choice) == expected)
    #expect(Self.isDefault(choice) == false)
  }

  @Test("기본 경로와 같은 문자열이면 isDefault (끝 / ·~/ 표기 무관)", arguments: [
    "/Users/u/Library/Android/sdk", "/Users/u/Library/Android/sdk/", "~/Library/Android/sdk",
    "/Users/u/Library/../Library/Android/sdk",
  ])
  func defaultPath(raw: String) {
    let choice = AndroidSDKRootChoice.resolve(.path(raw), home: Self.home)
    #expect(choice == AndroidSDKRootChoice.resolve(.absent, home: Self.home))
  }

  @Test("빈·상대·~user·~ 하나·NUL·문자열 아님 → invalidSetting", arguments: [
    AndroidSDKPathSetting.Value.path(""), .path("   "), .path("sdk"), .path("./sdk"), .path("~user/sdk"), .path("~"),
    .path("/a\0b"), .malformed,
  ])
  func invalid(value: AndroidSDKPathSetting.Value) {
    #expect(AndroidSDKRootChoice.resolve(value, home: Self.home) == .invalidSetting)
  }
}
