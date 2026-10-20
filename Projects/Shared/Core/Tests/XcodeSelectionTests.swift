import Foundation
import Testing
@testable import Core

struct XcodeSelectionTests {
  private static let xcode = Self.installation("/Applications/Xcode.app", major: 27, minor: 1)
  private static let older = Self.installation("/Applications/Xcode-26.4.app", major: 26, minor: 4)
  private static let beta = Self.installation("/Applications/Xcode-beta.app", major: 27, minor: 2)
  private static let elsewhere = Self.installation("/Users/me/Xcode-26.app", major: 26)

  private static func installation(_ path: String, major: Int, minor: Int = 0) -> XcodeInstallation {
    XcodeInstallation(
      bundleURL: URL(filePath: path, directoryHint: .isDirectory),
      version: OSVersion(major: major, minor: minor)
    )
  }

  @Test("xcode-select 의 Xcode 가 있으면 버전이 더 낮아도 그것을 고른다")
  func selectedWins() {
    #expect(XcodeSelection.choose(selected: Self.elsewhere, installed: [Self.xcode, Self.beta]) == Self.elsewhere)
  }

  @Test("xcode-select 의 Xcode 가 없으면 설치된 것 중 가장 높은 버전")
  func highestInstalled() {
    #expect(XcodeSelection.choose(selected: nil, installed: [Self.older, Self.xcode]) == Self.xcode)
  }

  @Test("베타가 더 높으면 베타를 고른다")
  func betaIfHigher() {
    #expect(XcodeSelection.choose(selected: nil, installed: [Self.xcode, Self.beta, Self.older]) == Self.beta)
  }

  @Test("같은 버전이면 번들 이름이 Xcode.app 인 것을 입력 순서와 상관없이 고른다")
  func sameVersionPrefersXcodeApp() {
    let sameVersionBeta = Self.installation("/Applications/Xcode-beta.app", major: 27, minor: 1)
    #expect(XcodeSelection.choose(selected: nil, installed: [sameVersionBeta, Self.xcode]) == Self.xcode)
    #expect(XcodeSelection.choose(selected: nil, installed: [Self.xcode, sameVersionBeta]) == Self.xcode)
  }

  @Test("같은 버전이고 둘 다 Xcode.app 이 아니면 경로 문자열 오름차순 첫 번째")
  func sameVersionByPath() {
    let first = Self.installation("/Applications/Xcode-A.app", major: 27, minor: 1)
    let second = Self.installation("/Applications/Xcode-B.app", major: 27, minor: 1)
    #expect(XcodeSelection.choose(selected: nil, installed: [second, first]) == first)
    #expect(XcodeSelection.choose(selected: nil, installed: [first, second]) == first)
  }

  @Test("모두 없으면 nil")
  func nothing() {
    #expect(XcodeSelection.choose(selected: nil, installed: []) == nil)
  }

  @Test("개발자 디렉터리는 번들 안의 Contents/Developer")
  func developerDirectory() {
    #expect(Self.xcode.developerDirectory.path(percentEncoded: false) == "/Applications/Xcode.app/Contents/Developer/")
    #expect(Self.xcode.developerDirectory.hasDirectoryPath)
  }
}
