import AppBundleInterface
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
    let confirmationKeys = LauncherTextCatalog.confirmationFormatKeys
    for (key, title) in zip(confirmationKeys, LauncherTextCatalog.formattedConfirmationTitles) {
      #expect(table[key] == key, "\(key)")
      #expect(String(format: table[key] ?? "", "iPhone 17", "iOS 26.0") == title, "\(key)")
    }
    let osKey = LauncherTextCatalog.requiresNewerOSKey
    #expect(table[osKey] == osKey)
    #expect(String(format: table[osKey] ?? "", "27.1") == LauncherTextCatalog.formattedRequiresNewerOS)
    #expect(Set(texts + formatKeys + confirmationKeys + [osKey]) == Set(table.keys))
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
    let formatted = LauncherTextCatalog.formattedTitles + LauncherTextCatalog.formattedConfirmationTitles
      + [LauncherTextCatalog.formattedRequiresNewerOS]
    for text in formatted {
      #expect(!text.isEmpty)
      #expect(text.unicodeScalars.contains { (0xAC00 ... 0xD7A3).contains($0.value) }, "\(text)")
    }
    #expect(LauncherText.title(for: nil).isEmpty)
    #expect(LauncherText.confirmationTitle(for: nil).isEmpty)
  }

  @Test("빈 화면 이유마다 설치 버튼 문구가 정해져 있다")
  func emptyReasonInstallButtons() {
    #expect(LauncherText.installButton(for: .noIOSRuntime) == "iOS 설치")
    #expect(LauncherText.installButton(for: .noCreatableDeviceType) == "다른 iOS 버전 설치")
    // 기기만 없으면 iOS 를 설치할 일이 아니라 버튼이 없다 (기기 만들기 버튼을 보인다).
    #expect(LauncherText.installButton(for: .noDevices) == nil)
  }

  @Test("시뮬레이터 오류마다 정확히 한 분류가 본문을 돌려준다", arguments: LauncherTextCatalog.errors)
  func eachErrorHasExactlyOneMessageFamily(error: SimulatorError) {
    let messages = [
      LauncherText.setupMessage(for: error), LauncherText.deviceMessage(for: error),
      LauncherText.appCommandMessage(for: error), LauncherText.linkMessage(for: error),
    ].compactMap(\.self)
    #expect(messages.count == 1)
    #expect(messages.first == LauncherText.message(for: error))
  }

  @Test("번들 검사·zip 풀기 오류마다 정확히 한 분류가 본문을 돌려준다", arguments: LauncherTextCatalog.bundleErrors)
  func eachBundleErrorHasExactlyOneMessageFamily(error: AppBundleError) {
    let messages = [LauncherText.bundleFileMessage(for: error), LauncherText.zipMessage(for: error)].compactMap(\.self)
    #expect(messages.count == 1)
    #expect(messages.first == LauncherText.message(for: error))
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
    #expect(
      LauncherText.title(for: .createFailed(device, .commandFailed)) == "“iPhone 17” (iOS 26.0) 기기를 만들지 못했습니다"
    )
    #expect(
      LauncherText.title(for: .deleteFailed(device, .commandFailed)) == "“iPhone 17” (iOS 26.0) 기기를 삭제하지 못했습니다"
    )
    #expect(
      LauncherText.title(for: .eraseFailed(device, .commandFailed)) == "“iPhone 17” (iOS 26.0) 기기를 초기화하지 못했습니다"
    )
    #expect(
      LauncherText.title(for: .installFailed(device, .multipleItems)) == "“iPhone 17” (iOS 26.0) 기기에 앱을 설치하지 못했습니다"
    )
    #expect(
      LauncherText.title(for: .launchFailed(device, .appLaunchFailed))
        == "“iPhone 17” (iOS 26.0) 기기에 앱을 설치했지만 실행하지 못했습니다"
    )
    #expect(
      LauncherText.title(for: .openURLFailed(device, .simulator(.urlNotHandled)))
        == "“iPhone 17” (iOS 26.0) 기기에서 링크를 열지 못했습니다"
    )
    #expect(LauncherText.openURLSheetTitle(for: device) == "“iPhone 17” (iOS 26.0) 기기에서 링크 열기")
  }

  @Test("링크 열기 실패 본문: 기기 상태는 막힌 이유, 명령 실패는 오류 분류 문구이고, 꺼진 기기 문구는 링크 열기도 말한다")
  func openURLFailureMessages() {
    for reason in LauncherTextCatalog.installBlockReasons {
      let message = LauncherText.message(for: OpenURLFailure.deviceNotReady(reason))
      #expect(message == LauncherText.openURLBlockReason(reason))
    }
    for error in LauncherTextCatalog.errors {
      #expect(LauncherText.message(for: OpenURLFailure.simulator(error)) == LauncherText.message(for: error))
    }
    #expect(LauncherText.message(for: .urlNotHandled).contains("열 수 있는 앱이 기기에 없습니다"))
    #expect(LauncherText.message(for: .invalidURL).contains("형식을 받아들이지 않았습니다"))
    #expect(
      LauncherText.message(for: .deviceNotBooted)
        == "기기가 켜져 있지 않아 앱 설치·실행이나 링크 열기를 하지 못했습니다. 기기를 켠 뒤 다시 시도하세요."
    )
  }

  @Test("링크 입력 문제: 비어 있으면 문구가 없고(버튼만 비활성), 나머지는 스킴을 안내한다")
  func linkProblemTexts() {
    #expect(LauncherText.linkProblem(.empty) == nil)
    for problem in [DeepLinkProblem.malformed, .missingScheme] {
      #expect(LauncherText.linkProblem(problem)?.contains("myapp://") == true, "\(problem)")
    }
  }

  @Test("결과를 알 수 없는 만들기 실패만 제목에서 단정하지 않고 목록을 확인하라고 안내하며, 다른 실패는 일반 문구다")
  func creationResultUnknownAsksToCheckList() {
    let device = LauncherNotice.Device(name: "iPhone 17", runtimeName: "iOS 26.0")
    let unknown = LauncherNotice.createFailed(device, .creationResultUnknown)
    #expect(LauncherText.title(for: unknown) == "“iPhone 17” (iOS 26.0) 기기를 만들었는지 확인하지 못했습니다")
    #expect(LauncherText.message(for: unknown).contains("목록을 확인한 뒤, 없을 때만 다시 만드세요"))
    #expect(LauncherText.message(for: unknown) == LauncherText.message(for: .creationResultUnknown))
    // 사전 목록 해석 실패(.unexpectedOutput)는 기기를 만들지 않았으므로 일반 제목·본문이다.
    let errors: [SimulatorError] = [.unexpectedOutput, .commandFailed, .creationOptionUnavailable, .invalidDeviceName]
    for error in errors {
      let notice = LauncherNotice.createFailed(device, error)
      #expect(LauncherText.title(for: notice) == "“iPhone 17” (iOS 26.0) 기기를 만들지 못했습니다")
      #expect(LauncherText.message(for: notice) == LauncherText.message(for: error))
      #expect(!LauncherText.message(for: notice).contains("없을 때만 다시 만드세요"))
    }
  }

  @Test("삭제·초기화 확인 제목에 기기 이름과 런타임 이름이 들어간다")
  func confirmationTitlesContainDeviceName() {
    let device = LauncherNotice.Device(name: "iPhone 17", runtimeName: "iOS 26.0")
    let id = VirtualDevice.ID("00000000-0000-0000-0000-000000000001")
    #expect(
      LauncherText.confirmationTitle(for: DeviceConfirmation(action: .delete, deviceID: id, device: device))
        == "“iPhone 17” (iOS 26.0) 기기를 삭제할까요?"
    )
    #expect(
      LauncherText.confirmationTitle(for: DeviceConfirmation(action: .erase, deviceID: id, device: device))
        == "“iPhone 17” (iOS 26.0) 기기를 초기화할까요?"
    )
  }
}

/// `LauncherText` 가 돌려줄 수 있는 문구. `all` 은 키와 값이 같은 문구다 (알림 없음의 빈 제목, 기기 이름이 든 제목 제외).
enum LauncherTextCatalog {
  static let errors: [SimulatorError] = [
    .developerToolsUnavailable, .deviceNotFound, .deviceNotShutdown, .creationOptionUnavailable, .invalidDeviceName,
    .creationResultUnknown, .simulatorAppNotFound, .unexpectedOutput, .commandFailed, .deviceNotBooted, .appNotFound,
    .appInvalid, .appIncompatible, .appRequiresNewerOS, .appNotInstalled, .appLaunchFailed, .urlNotHandled,
    .invalidURL,
  ]

  static let sampleDevice = LauncherNotice.Device(name: "iPhone 17", runtimeName: "iOS 26.0")

  /// 첫 항목만 기기가 없고(제목이 키와 같다), 나머지는 기기 이름이 들어간 제목이다.
  static let notices: [LauncherNotice] = [
    .refreshFailed(.commandFailed), .bootFailed(sampleDevice, .commandFailed),
    .shutdownFailed(sampleDevice, .commandFailed), .openAppFailed(sampleDevice, .commandFailed),
    .createFailed(sampleDevice, .commandFailed), .deleteFailed(sampleDevice, .commandFailed),
    .eraseFailed(sampleDevice, .commandFailed), .createFailed(sampleDevice, .creationResultUnknown),
    .installFailed(sampleDevice, .multipleItems), .launchFailed(sampleDevice, .appLaunchFailed),
    .openURLFailed(sampleDevice, .simulator(.urlNotHandled)),
  ]

  /// 기기 이름이 들어가는 제목의 카탈로그 키. 순서는 `notices.dropFirst()` 뒤에 링크 시트 제목이다 (`formattedTitles`).
  static let formatKeys = [
    "“%@” (%@) 기기를 켜지 못했습니다",
    "“%@” (%@) 기기를 끄지 못했습니다",
    "“%@” (%@) 기기는 켜졌지만 Simulator 앱을 열지 못했습니다",
    "“%@” (%@) 기기를 만들지 못했습니다",
    "“%@” (%@) 기기를 삭제하지 못했습니다",
    "“%@” (%@) 기기를 초기화하지 못했습니다",
    "“%@” (%@) 기기를 만들었는지 확인하지 못했습니다",
    "“%@” (%@) 기기에 앱을 설치하지 못했습니다",
    "“%@” (%@) 기기에 앱을 설치했지만 실행하지 못했습니다",
    "“%@” (%@) 기기에서 링크를 열지 못했습니다",
    "“%@” (%@) 기기에서 링크 열기",
  ]

  /// `sampleDevice` 를 넣은 기기 작업 실패 제목과 링크 시트 제목.
  static var formattedTitles: [String] {
    self.notices.dropFirst().map { LauncherText.title(for: $0) } + [LauncherText.openURLSheetTitle(for: sampleDevice)]
  }

  /// 확인 대화상자 제목의 카탈로그 키. 순서는 `confirmations` 와 같다.
  static let confirmationFormatKeys = [
    "“%@” (%@) 기기를 삭제할까요?",
    "“%@” (%@) 기기를 초기화할까요?",
  ]

  static let confirmations: [DeviceConfirmation] = [DeviceConfirmation.Action.delete, .erase].map {
    DeviceConfirmation(
      action: $0,
      deviceID: VirtualDevice.ID("00000000-0000-0000-0000-000000000001"),
      device: sampleDevice
    )
  }

  /// `sampleDevice` 를 넣은 확인 대화상자 제목.
  static var formattedConfirmationTitles: [String] {
    self.confirmations.map { LauncherText.confirmationTitle(for: $0) }
  }

  static let actions: [DeviceConfirmation.Action] = [.delete, .erase]

  static let blockReasons: [DeviceActionBlockReason] = [.notShutdown, .unavailable]

  static let nameProblems: [DeviceNameProblem] = [.empty, .tooLong, .containsControlCharacter]

  static let reasons: [VirtualDevice.UnavailableReason] = [
    .runtimeNotInstalled, .runtimeUnavailable, .deviceTypeNotSupported, .unknown,
  ]

  static let states: [VirtualDevice.State] = [.shutdown, .booting, .booted, .shuttingDown, .unknown]

  static let emptyReasons: [DeviceListEmptyReason] = [.noIOSRuntime, .noCreatableDeviceType, .noDevices]

  static let bundleErrors: [AppBundleError] = [
    .notLocalFile, .fileNotFound, .ipaFile, .notAppBundle, .macOSApp, .invalidBundle, .zipUnreadable, .zipWithoutApp,
    .zipWithMultipleApps, .zipUnsafeEntry, .insufficientDiskSpace, .extractionUnavailable,
  ]

  /// 버전이 들어가는 `.requiresNewerOS` 는 `requiresNewerOSKey` 로 따로 본다.
  static let installProblems: [AppInstallProblem] = [
    .notSimulatorBuild, .missingArchitecture(.arm64), .missingArchitecture(.x86_64),
  ]

  static let installBlockReasons: [AppInstallBlockReason] = [.unavailable, .stateChanging]

  static let requiresNewerOSKey = "이 앱은 iOS %@ 이상에서 실행됩니다. 더 높은 iOS 버전의 기기에 설치하세요."

  static var formattedRequiresNewerOS: String {
    LauncherText.message(for: .requiresNewerOS(OSVersion(major: 27, minor: 1)))
  }

  static var all: [String] {
    // 긴 `+` 연결식은 타입 추론이 느려 CI 의 Xcode 에서 시간 초과가 나므로 줄마다 `+=` 로 붙인다.
    var texts: [String] = self.errors.map { LauncherText.message(for: $0) }
    texts += [LauncherText.title(for: self.notices[0])]
    texts += self.notices.map { LauncherText.message(for: $0) }
    texts += self.reasons.map { LauncherText.reason(for: $0) }
    texts += self.states.map { LauncherText.stateLabel(for: $0) }
    texts += self.emptyReasons.map { LauncherText.emptyTitle(for: $0) }
    texts += self.emptyReasons.map { LauncherText.emptyMessage(for: $0) }
    texts += self.emptyReasons.compactMap { LauncherText.installButton(for: $0) }
    texts += self.actions.map { LauncherText.confirmationMessage(for: $0) }
    texts += self.actions.map { LauncherText.confirmButton(for: $0) }
    texts += self.blockReasons.map { LauncherText.blockReason($0) }
    texts += self.nameProblems.map { LauncherText.nameProblem($0) }
    texts += self.bundleErrors.map { LauncherText.message(for: $0) }
    texts += self.installProblems.map { LauncherText.message(for: $0) }
    texts += self.installBlockReasons.map { LauncherText.installBlockReason($0) }
    texts += [LauncherText.installAppButton, LauncherText.installAppHelp, LauncherText.installingLabel]
    texts += self.installBlockReasons.map { LauncherText.openURLBlockReason($0) }
    texts += [DeepLinkProblem.malformed, .missingScheme].compactMap { LauncherText.linkProblem($0) }
    texts += [
      LauncherText.openURLButton, LauncherText.openURLHelp, LauncherText.openingURLLabel, LauncherText.linkField,
      LauncherText.linkPrompt, LauncherText.openURLConfirmButton,
    ]
    texts += [
      LauncherText.okButton, LauncherText.unavailableLabel, LauncherText.bootButton, LauncherText.shutdownButton,
      LauncherText.loading, LauncherText.loadFailedTitle, LauncherText.refreshButton, LauncherText.retryButton,
      LauncherText.setupButton, LauncherText.setupButtonHelp, LauncherText.openSetupButton,
      LauncherText.cancelButton, LauncherText.deviceActionsMenu, LauncherText.eraseMenuItem,
      LauncherText.deleteMenuItem, LauncherText.createDeviceButton, LauncherText.creatingLabel,
      LauncherText.createSheetTitle, LauncherText.nameField, LauncherText.runtimePicker,
      LauncherText.deviceTypePicker, LauncherText.createConfirmButton, LauncherText.createUnavailableNotice,
    ]
    return texts
  }
}
