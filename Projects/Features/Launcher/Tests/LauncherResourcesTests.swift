import AppBundleInterface
import Core
import DownloadInterface
import Foundation
import SimulatorInterface
import Testing
import WorkspaceInterface
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
    // 받는 중 바이트(%@ 둘·하나)와 HTTP 상태(%lld) 키는 형식이 달라 따로 넣어 본다.
    let bytes = LauncherTextCatalog.byteSamples
    let bothKey = LauncherTextCatalog.downloadingBothKey
    #expect(table[bothKey] == bothKey)
    #expect(
      String(format: table[bothKey] ?? "", bytes.received, bytes.total)
        == LauncherText.downloadingLabel(LauncherTextCatalog.knownTotalProgress)
    )
    let receivedKey = LauncherTextCatalog.downloadingReceivedKey
    #expect(table[receivedKey] == receivedKey)
    #expect(
      String(format: table[receivedKey] ?? "", bytes.received)
        == LauncherText.downloadingLabel(LauncherTextCatalog.unknownTotalProgress)
    )
    let httpKeys = LauncherTextCatalog.httpStatusKeys
    for (key, code) in httpKeys {
      #expect(table[key] == key, "\(key)")
      #expect(String(format: table[key] ?? "", code) == LauncherText.httpStatusMessage(code), "\(key)")
    }
    var keys = Set(texts)
    keys.formUnion(formatKeys)
    keys.formUnion(confirmationKeys)
    keys.formUnion([osKey, bothKey, receivedKey])
    keys.formUnion(httpKeys.map(\.key))
    keys.formUnion(Self.checkCatalogTexts(in: table))
    keys.formUnion(BatchTextCatalog.checkedKeys(in: table))
    #expect(keys == Set(table.keys))
  }

  /// 카탈로그에서 설치 문구(`CatalogTextCatalog` 의 78개)가 표에 있고, 표의 값(보간 키는 인자를 넣은 값)이 코드 결과와 같은지 보고
  /// 그 키를 돌려준다.
  static func checkCatalogTexts(in table: [String: String]) -> Set<String> {
    var checks = CatalogTextCatalog.checks(table)
    checks += CatalogTextCatalog.fragmentChecks(table)
    for check in checks {
      #expect(table[check.key] == check.key, "\(check.key)")
      #expect(check.actual == check.expected, "\(check.key)")
    }
    let keys = Set(checks.map(\.key))
    #expect(keys.count == 78)
    return keys
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
    for text in LauncherTextCatalog.formattedDownloadTexts {
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
      LauncherText.recordingMessage(for: error),
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
    .invalidURL, .recordingInProgress, .recordingEmpty, .recordingUnfinished,
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
    .screenshotFailed(sampleDevice, .workspace(.folderUnavailable)),
    .screenshotRevealFailed(sampleDevice, .fileNotFound),
    .recordingFailed(sampleDevice, .workspace(.folderUnavailable)),
    .recordingFailed(sampleDevice, .simulator(.recordingUnfinished)),
    .recordingInterrupted(sampleDevice), .recordingStoppedByDevice(sampleDevice),
    .recordingRevealFailed(sampleDevice, .fileNotFound),
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
    "“%@” (%@) 기기의 스크린샷을 저장하지 못했습니다",
    "“%@” (%@) 기기의 스크린샷을 저장했지만 Finder 에서 보여 주지 못했습니다",
    "“%@” (%@) 기기의 화면을 녹화하지 못했습니다",
    "“%@” (%@) 기기의 녹화 저장을 마치지 못했습니다",
    "“%@” (%@) 기기의 녹화가 중간에 끝났습니다",
    "“%@” (%@) 기기가 꺼져 녹화를 멈추고 저장했습니다",
    "“%@” (%@) 기기의 녹화를 저장했지만 Finder 에서 보여 주지 못했습니다",
    "“%@” (%@) 기기에서 링크 열기",
    "“%@” (%@) 기기에 URL 에서 앱 설치",
  ]

  /// `sampleDevice` 를 넣은 기기 작업 실패 제목과 링크 시트·URL 설치 시트 제목.
  static var formattedTitles: [String] {
    var titles = self.notices.dropFirst().map { LauncherText.title(for: $0) }
    titles += [LauncherText.openURLSheetTitle(for: sampleDevice), LauncherText.installURLSheetTitle(for: sampleDevice)]
    return titles
  }

  // MARK: - URL 에서 설치

  static let downloadingBothKey = "받는 중… %@ / %@"
  static let downloadingReceivedKey = "받는 중… %@"
  static let knownTotalProgress = DownloadProgress(receivedBytes: 1_000_000, expectedBytes: 2_000_000)
  static let unknownTotalProgress = DownloadProgress(receivedBytes: 1_000_000, expectedBytes: nil)

  /// `knownTotalProgress` 의 바이트를 화면과 같은 형식으로 쓴 값.
  static var byteSamples: (received: String, total: String) {
    (
      Int64(1_000_000).formatted(.byteCount(style: .file)),
      Int64(2_000_000).formatted(.byteCount(style: .file))
    )
  }

  /// HTTP 상태가 들어가는 키와 그 키를 고르는 상태 코드 하나 (407 은 숫자를 넣은 고정 문구라 `all` 에 있다).
  static let httpStatusKeys: [(key: String, code: Int)] = [
    ("서버가 로그인이나 접근 권한을 요구해 받지 못했습니다 (HTTP %lld). 로그인 없이 받을 수 있는 주소인지 확인하세요.", 401),
    ("서버에 파일이 없습니다 (HTTP %lld). 주소가 맞는지, 파일이 지워지지 않았는지 확인하세요.", 404),
    ("서버 오류로 받지 못했습니다 (HTTP %lld). 잠시 뒤 다시 시도하세요.", 503),
    ("서버가 파일을 주지 않았습니다 (HTTP %lld). 주소를 확인한 뒤 다시 시도하세요.", 400),
  ]

  /// HTTP 상태 문구를 뺀 받기 실패 (`.httpStatus` 는 `httpStatusKeys` 와 407 로 본다).
  static let downloadErrors: [DownloadError] = [
    .insecureRedirect, .offline, .hostNotFound, .cannotConnect, .timedOut, .connectionLost, .secureConnectionFailed,
    .insufficientDiskSpace, .tooLarge, .cancelled, .storageUnavailable, .failed,
  ]

  /// 바이트·HTTP 상태를 넣은 받기 문구.
  static var formattedDownloadTexts: [String] {
    var texts = [
      LauncherText.downloadingLabel(self.knownTotalProgress), LauncherText.downloadingLabel(self.unknownTotalProgress),
    ]
    texts += self.httpStatusKeys.map { LauncherText.httpStatusMessage($0.code) }
    return texts
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

  static let screenshotBlockReasons: [ScreenshotBlockReason] = [.notBooted, .unavailable]

  static let workspaceErrors: [WorkspaceError] = [.folderUnavailable, .fileNameUnavailable, .fileNotFound]

  static let requiresNewerOSKey = "이 앱은 iOS %@ 이상에서 실행됩니다. 더 높은 iOS 버전의 기기에 설치하세요."

  static var formattedRequiresNewerOS: String {
    LauncherText.message(for: .requiresNewerOS(OSVersion(major: 27, minor: 1)))
  }

  /// 녹화 문구 (알림 본문은 `notices`·`errors` 가 덮고, 여기는 그 밖의 것).
  static var recordingTexts: [String] {
    var texts = self.screenshotBlockReasons.map { LauncherText.recordBlockReason($0) }
    texts += self.workspaceErrors.map { LauncherText.recordingMessage(for: $0) }
    let failures: [RecordingFailure] = [.simulator(.deviceNotBooted), .simulator(.commandFailed)]
    texts += failures.map { LauncherText.message(for: $0) }
    texts += [
      LauncherText.recordButton, LauncherText.recordHelp, LauncherText.stopRecordingButton,
      LauncherText.startingRecordingLabel, LauncherText.recordingLabel, LauncherText.stoppingRecordingLabel,
      LauncherText.stopRecordingFirstHelp, LauncherText.recordingBlocksDeviceActions,
      LauncherText.recordingTerminationTitle, LauncherText.recordingTerminationMessage, LauncherText.saveAndQuitButton,
    ]
    return texts
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
    texts += [
      LauncherText.installFromFileMenuItem, LauncherText.installFromURLMenuItem, LauncherText.downloadingLabel(nil),
      LauncherText.cancellingDownloadLabel, LauncherText.cancelDownloadAccessibilityLabel,
      LauncherText.cancelDownloadHelp, LauncherText.downloadURLField, LauncherText.downloadURLPrompt,
      LauncherText.downloadURLGuide, LauncherText.installURLConfirmButton, LauncherText.httpStatusMessage(407),
    ]
    texts += [DownloadURLProblem.malformed, .notHTTPS, .missingHost, .hasCredentials].compactMap {
      LauncherText.downloadURLProblem($0)
    }
    texts += self.downloadErrors.map { LauncherText.message(for: $0) }
    texts += [true, false].map { LauncherText.downloadedNotZipMessage(isWebPage: $0) }
    texts += self.bundleErrors.map { LauncherText.downloadedZipMessage(for: $0) }
    texts += self.installBlockReasons.map { LauncherText.openURLBlockReason($0) }
    texts += [DeepLinkProblem.malformed, .missingScheme].compactMap { LauncherText.linkProblem($0) }
    texts += [
      LauncherText.openURLButton, LauncherText.openURLHelp, LauncherText.openingURLLabel, LauncherText.linkField,
      LauncherText.linkPrompt, LauncherText.openURLConfirmButton,
    ]
    texts += self.screenshotBlockReasons.map { LauncherText.screenshotBlockReason($0) }
    texts += self.workspaceErrors.map { LauncherText.message(for: $0) }
    texts += [LauncherText.message(for: ScreenshotFailure.simulator(.deviceNotBooted))]
    texts += [LauncherText.screenshotButton, LauncherText.screenshotHelp, LauncherText.takingScreenshotLabel]
    texts += self.recordingTexts
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
