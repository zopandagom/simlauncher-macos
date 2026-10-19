import Core
import Foundation
import SimulatorInterface
import Testing
@testable import LauncherFeature

struct LauncherResourcesTests {
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
    let texts = LauncherTextCatalog.all
    for text in texts {
      #expect(table[text] == text, "\(text)")
    }
    // 보간이 든 키도 .stringsdict 로 빠지지 않고 .strings 표에 들어간다.
    let formatKeys = LauncherTextCatalog.formatKeys
    for key in formatKeys {
      #expect(table[key] == key, "\(key)")
    }
    // 코드의 키가 카탈로그 키와 어긋나면 코드 문자열로 서식을 만들어 겉보기에 멀쩡하므로, 표의 값으로 만든 제목과 비교한다.
    for (key, title) in zip(formatKeys, LauncherTextCatalog.formattedTitles) {
      #expect(String(format: table[key] ?? "", "iPhone 17", "iOS 26.0") == title, "\(key)")
    }
    #expect(Set(texts + formatKeys) == Set(table.keys))
  }
}

/// 문구 함수가 돌려주는 값.
struct LauncherTextTests {
  @Test("모든 문구 함수가 모든 케이스에 비어 있지 않은 한국어를 돌려준다")
  func textsAreNonEmptyKorean() {
    for text in LauncherTextCatalog.all {
      #expect(!text.isEmpty)
      #expect(text.unicodeScalars.contains { (0xAC00 ... 0xD7A3).contains($0.value) }, "\(text)")
    }
    for text in LauncherTextCatalog.formattedTitles {
      #expect(!text.isEmpty)
      #expect(text.unicodeScalars.contains { (0xAC00 ... 0xD7A3).contains($0.value) }, "\(text)")
    }
    #expect(LauncherText.title(for: nil).isEmpty)
  }

  @Test("기기 작업 실패 제목에 기기 이름과 런타임 이름이 들어간다")
  func deviceNoticeTitlesContainDeviceName() {
    let device = LauncherNotice.Device(name: "iPhone 17", runtimeName: "iOS 26.0")
    #expect(
      LauncherText.title(for: .bootFailed(device, .commandFailed)) == "“iPhone 17” (iOS 26.0) 기기를 켜지 못했습니다"
    )
    #expect(
      LauncherText.title(for: .shutdownFailed(device, .commandFailed)) == "“iPhone 17” (iOS 26.0) 기기를 끄지 못했습니다"
    )
    #expect(
      LauncherText.title(for: .openAppFailed(device, .commandFailed))
        == "“iPhone 17” (iOS 26.0) 기기는 켜졌지만 Simulator 앱을 열지 못했습니다"
    )
  }
}

/// `LauncherText` 가 돌려줄 수 있는 문구. `all` 은 키와 값이 같은 문구다 (알림 없음의 빈 제목, 기기 이름이 든 제목 제외).
enum LauncherTextCatalog {
  static let errors: [SimulatorError] = [
    .developerToolsUnavailable, .deviceNotFound, .simulatorAppNotFound, .unexpectedOutput, .commandFailed,
  ]

  static let sampleDevice = LauncherNotice.Device(name: "iPhone 17", runtimeName: "iOS 26.0")

  /// 첫 항목만 기기가 없고(제목이 키와 같다), 나머지는 기기 이름이 들어간 제목이다.
  static let notices: [LauncherNotice] = [
    .refreshFailed(.commandFailed), .bootFailed(sampleDevice, .commandFailed),
    .shutdownFailed(sampleDevice, .commandFailed), .openAppFailed(sampleDevice, .commandFailed),
  ]

  /// 기기 이름이 들어가는 제목의 카탈로그 키. 순서는 `notices.dropFirst()` 와 같다.
  static let formatKeys = [
    "“%@” (%@) 기기를 켜지 못했습니다",
    "“%@” (%@) 기기를 끄지 못했습니다",
    "“%@” (%@) 기기는 켜졌지만 Simulator 앱을 열지 못했습니다",
  ]

  /// `sampleDevice` 를 넣은 기기 작업 실패 제목.
  static var formattedTitles: [String] {
    self.notices.dropFirst().map { LauncherText.title(for: $0) }
  }

  static let reasons: [VirtualDevice.UnavailableReason] = [
    .runtimeNotInstalled, .runtimeUnavailable, .deviceTypeNotSupported, .unknown,
  ]

  static let states: [VirtualDevice.State] = [.shutdown, .booting, .booted, .shuttingDown, .unknown]

  static let emptyReasons: [DeviceListEmptyReason] = [.noIOSRuntime, .noDevices]

  static var all: [String] {
    self.errors.map { LauncherText.message(for: $0) }
      + [LauncherText.title(for: self.notices[0])]
      + self.notices.map { LauncherText.message(for: $0) }
      + self.reasons.map { LauncherText.reason(for: $0) }
      + self.states.map { LauncherText.stateLabel(for: $0) }
      + self.emptyReasons.map { LauncherText.emptyTitle(for: $0) }
      + self.emptyReasons.map { LauncherText.emptyMessage(for: $0) }
      + [
        LauncherText.okButton, LauncherText.unavailableLabel, LauncherText.bootButton, LauncherText.shutdownButton,
        LauncherText.loading, LauncherText.loadFailedTitle, LauncherText.refreshButton, LauncherText.retryButton,
      ]
  }
}
