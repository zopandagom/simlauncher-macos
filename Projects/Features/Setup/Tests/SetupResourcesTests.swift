import Core
import DevEnvironmentInterface
import DevEnvironmentTesting
import Foundation
import Testing
@testable import SetupFeature

struct SetupResourcesTests {
  @Test("리소스 번들의 원문 언어는 한국어다")
  func resourceBundleIsKorean() {
    #expect(Bundle.module.developmentLocalization == "ko")
  }

  @Test("화면의 모든 문구가 String Catalog 에서 한국어 값으로 컴파일되고, 그 밖의 키는 없다")
  func everyTextIsInCompiledKoreanTable() throws {
    let url = try #require(
      Bundle.module.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "ko")
    )
    let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
    let texts = SetupTextCatalog.all
    for text in texts {
      #expect(table[text] == text, "\(text)")
    }
    #expect(Set(texts) == Set(table.keys))
  }
}

/// 문구 함수가 돌려주는 값.
struct SetupTextTests {
  @Test("모든 문구 함수가 모든 케이스에 비어 있지 않은 한국어를 돌려준다")
  func textsAreNonEmptyKorean() {
    for text in SetupTextCatalog.all {
      #expect(!text.isEmpty)
      #expect(text.unicodeScalars.contains { (0xAC00 ... 0xD7A3).contains($0.value) }, "\(text)")
    }
    #expect(SetupText.title(for: nil).isEmpty)
  }

  @Test("Xcode 없음과 Command Line Tools 만 있음은 제목이 같고 본문이 다르다")
  func installStatusesDifferInMessage() {
    #expect(SetupText.title(for: .xcodeNotInstalled) == SetupText.title(for: .commandLineToolsOnly))
    #expect(SetupText.message(for: .xcodeNotInstalled) != SetupText.message(for: .commandLineToolsOnly))
    #expect(SetupText.message(for: DevEnvironmentStatus.commandLineToolsOnly).contains("Command Line Tools"))
  }

  @Test("Xcode 열기 실패 알림은 Xcode 가 없어진 경우만 제목·본문이 다르다")
  func openXcodeNoticeTexts() {
    #expect(SetupText.title(for: .openXcodeFailed(.xcodeNotFound)) == "Xcode 를 찾지 못했습니다")
    #expect(SetupText.title(for: .openXcodeFailed(.openFailed)) == "Xcode 를 열지 못했습니다")
    #expect(SetupText.title(for: .openXcodeFailed(.checkFailed)) == "Xcode 를 열지 못했습니다")
    #expect(
      SetupText.message(for: SetupNotice.openXcodeFailed(.openFailed))
        == SetupText.message(for: SetupNotice.openXcodeFailed(.checkFailed))
    )
    #expect(
      SetupText.message(for: SetupNotice.openXcodeFailed(.xcodeNotFound))
        != SetupText.message(for: SetupNotice.openXcodeFailed(.openFailed))
    )
  }

  @Test("Xcode 경로는 끝 / 를 떼고, 없으면 그대로 보인다")
  func xcodeLocation() {
    #expect(SetupText.xcodeLocation(XcodeInstallation.sample.bundleURL) == "/Applications/Xcode.app")
    #expect(SetupText.xcodeLocation(URL(filePath: "/Applications/Xcode-beta.app", directoryHint: .notDirectory))
      == "/Applications/Xcode-beta.app")
    #expect(SetupText.xcodeLocation(URL(filePath: "/", directoryHint: .isDirectory)) == "/")
  }
}

/// `SetupText` 가 돌려줄 수 있는 문구. 모두 키와 값이 같다 (알림 없음의 빈 제목 제외).
enum SetupTextCatalog {
  static let statuses: [DevEnvironmentStatus] = [
    .xcodeNotInstalled, .commandLineToolsOnly, .licenseNotAccepted(.sample), .firstLaunchRequired(.sample),
    .ready(.sample),
  ]

  static let errors: [DevEnvironmentError] = [.checkFailed, .xcodeNotFound, .openFailed]

  static var notices: [SetupNotice] {
    self.errors.map { .openAppStoreFailed($0) } + self.errors.map { .openXcodeFailed($0) }
  }

  static var all: [String] {
    self.statuses.map { SetupText.title(for: $0) }
      + self.statuses.map { SetupText.message(for: $0) }
      + [SetupText.failedTitle]
      + self.errors.map { SetupText.message(for: $0) }
      + SetupStep.Kind.allCases.map { SetupText.stepTitle($0) }
      + self.notices.map { SetupText.title(for: $0) }
      + self.notices.map { SetupText.message(for: $0) }
      + [
        SetupText.checkingTitle, SetupText.adminPasswordNote, SetupText.autoRecheckNote, SetupText.currentXcodeLabel,
        SetupText.openAppStoreButton, SetupText.openXcodeButton, SetupText.recheckButton, SetupText.finishButton,
        SetupText.okButton, SetupText.recheckingLabel,
      ]
  }
}
