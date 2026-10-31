import AndroidEmulatorInterface
import AndroidEmulatorTesting
import AndroidPackageInterface
import Core
import Foundation
import Testing
@testable import AndroidDevicesFeature

struct AndroidDevicesResourcesTests {
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
    for text in AndroidDevicesTextCatalog.plain {
      #expect(table[text] == text, "\(text)")
    }
    // 보간이 든 키는 표의 값으로 만든 문구가 코드의 문구와 같아야 한다 (키가 어긋나면 코드 문자열로 서식을 만들어 겉보기에 멀쩡하다).
    for sample in AndroidDevicesTextCatalog.formatted {
      #expect(table[sample.key] == sample.key, "\(sample.key)")
      #expect(String(format: table[sample.key] ?? "", arguments: sample.arguments) == sample.text, "\(sample.key)")
    }
    // URL·카탈로그에서 설치 문구와 스크린샷·녹화 문구는 표로 기대 문구를 만드는 확인 목록이다
    // (`DownloadTextCatalog`·`CaptureTextCatalog`).
    let downloadChecks = DownloadTextCatalog.sharedChecks(table) + DownloadTextCatalog.androidChecks(table)
      + CaptureTextCatalog.sharedChecks(table) + CaptureTextCatalog.androidChecks(table)
      + BatchTextCatalog.sharedChecks(table) + BatchTextCatalog.androidChecks(table)
    for check in downloadChecks {
      #expect(table[check.key] == check.key, "\(check.key)")
      #expect(check.actual == check.expected, "\(check.key)")
    }
    let keys = Set(AndroidDevicesTextCatalog.plain)
      .union(AndroidDevicesTextCatalog.formatted.map(\.key))
      .union(downloadChecks.map(\.key))
    #expect(keys == Set(table.keys))
  }
}

/// 문구 함수가 돌려주는 값.
struct AndroidDevicesTextTests {
  @Test("모든 문구가 비어 있지 않은 한국어다")
  func textsAreNonEmptyKorean() {
    for text in AndroidDevicesTextCatalog.plain + AndroidDevicesTextCatalog.formatted.map(\.text) {
      #expect(!text.isEmpty)
      #expect(
        text.unicodeScalars.contains { (0xAC00 ... 0xD7A3).contains($0.value) } || text.hasPrefix("API"),
        "\(text)"
      )
    }
    #expect(AndroidDevicesText.title(for: nil).isEmpty)
    #expect(AndroidDevicesText.confirmationTitle(for: nil).isEmpty)
  }

  @Test("취소 밖의 모든 에러에 서로 다른 본문이 있고, 취소는 본문이 없다")
  func errorMessages() {
    let messages = AndroidDevicesTextCatalog.errors.map { AndroidDevicesText.message(for: $0) }
    #expect(messages.allSatisfy { $0?.isEmpty == false })
    #expect(Set(messages).count == messages.count)
    #expect(AndroidDevicesText.message(for: .cancelled) == nil)
    // 앱이 띄우지 않은 에뮬레이터가 끝난 경우도 같은 문구다.
    #expect(AndroidDevicesText.message(for: .emulatorExited(nil)) == AndroidDevicesText
      .message(for: .emulatorExited(1)))
  }

  @Test("쓸 수 없는 기기의 켜기 실패 본문은 행의 이유와 같다")
  func unavailableMessageIsReason() {
    for reason in AndroidDevicesTextCatalog.reasons {
      #expect(AndroidDevicesText.message(for: .deviceUnavailable(reason)) == AndroidDevicesText.reason(for: reason))
    }
    #expect(Set(AndroidDevicesTextCatalog.reasons.map { AndroidDevicesText.reason(for: $0) }).count == 6)
  }

  @Test("모든 알림에 제목과 본문이 있다")
  func noticeTexts() {
    for notice in AndroidDevicesTextCatalog.notices {
      #expect(!AndroidDevicesText.title(for: notice).isEmpty, "\(notice)")
      #expect(!AndroidDevicesText.message(for: notice).isEmpty, "\(notice)")
    }
  }

  @Test("기기 라벨: 이미지가 있으면 API 를 함께, 없으면 이름만")
  func labels() {
    #expect(AndroidDevicesText.label(AndroidDeviceLabel(.phoneSample)) == "“테스트 폰” (API 37.0)")
    #expect(AndroidDevicesText.label(AndroidDeviceLabel(name: "폰", apiLabel: nil)) == "“폰”")
    #expect(AndroidDevicesText.title(for: .bootFailed(AndroidDeviceLabel(.phoneSample), .bootTimedOut))
      == "“테스트 폰” (API 37.0) 기기를 켜지 못했습니다")
  }

  @Test("만들기 시트의 Android Studio 링크는 공개 내려받기 페이지다")
  func studioDownloadURL() {
    #expect(AndroidDevicesText.studioDownloadURL == URL(string: "https://developer.android.com/studio"))
  }

  @Test("만들기 시트 안내: 그 밖의 기기는 Studio 로, 폴더블 설정이 없는 이미지면 폴더블을 만들 수 있는 이미지를 알려 준다")
  func creationGuides() {
    #expect(AndroidDevicesText.studioDevicesGuide
      == "다른 크기·모양의 기기는 Android Studio 의 기기 관리자(Device Manager)에서 만들면 이 목록에 보입니다.")
    #expect(AndroidDevicesText.foldableImageUnsupported(foldableImages: [.sample])
      == "이 시스템 이미지에는 폴더블 설정이 없어 폴더블을 만들 수 없습니다. 폴더블은 API 37.0 · google_apis 로 만들 수 있습니다.")
    #expect(AndroidDevicesText.foldableImageUnsupported(foldableImages: [.sample, .olderSample])
      == "이 시스템 이미지에는 폴더블 설정이 없어 폴더블을 만들 수 없습니다. "
      + "폴더블은 API 37.0 · google_apis, API 36 · google_apis_playstore 로 만들 수 있습니다.")
    #expect(AndroidDevicesText.foldableImageUnsupported(foldableImages: []) == AndroidDevicesText.foldableNoImage)
    #expect(AndroidDevicesText.foldableNoImage == "설치된 시스템 이미지 중 폴더블 설정이 있는 것이 없어 폴더블을 만들 수 없습니다.")
  }

  @Test("함께 켜기 결과: 같은 결과끼리 한 줄로 묶고, 켠 기기가 있으면 몇 대 중 몇 대다")
  func batchMessage() {
    let phone = AndroidDeviceLabel(.phoneSample)
    let tablet = AndroidDeviceLabel(.bootedTabletSample)
    let other = AndroidDeviceLabel(name: "폰", apiLabel: nil)
    let report = AndroidBatchBootReport(entries: [
      .init(device: phone, error: .bootTimedOut),
      .init(device: tablet, error: nil),
      .init(device: other, error: .bootTimedOut),
    ])
    #expect(AndroidDevicesText.batchTitle(for: report) == "기기 3대 중 1대를 켰습니다")
    let timedOut = AndroidDevicesText.message(for: AndroidEmulatorError.bootTimedOut) ?? ""
    #expect(AndroidDevicesText.batchMessage(for: report) == """
    “테스트 폰” (API 37.0), “폰”: 켜지 못했습니다. \(timedOut)

    “Pixel Tablet” (API 37.0): 켰습니다.
    """)
    let failed = AndroidBatchBootReport(entries: [.init(device: phone, error: .cancelled)])
    #expect(AndroidDevicesText.batchTitle(for: failed) == "기기 1대를 켜지 못했습니다")
    #expect(AndroidDevicesText.batchMessage(for: failed) == "“테스트 폰” (API 37.0): 켜지 못했습니다.")
  }

  @Test("앱 작업 문구: 판정 거절은 판정 값을 보이고, 설치 뒤 실행할 화면이 없으면 시트 실패와 다른 문구다")
  func appTexts() {
    #expect(AndroidDevicesText.message(for: AndroidInstallProblem.noMatchingABI(app: ["x86"], device: ["x86_64"]))
      .contains("(x86_64)"))
    #expect(AndroidDevicesText.message(for: AndroidInstallProblem.requiresNewerAPI(required: 99, device: 37))
      .contains("API 99"))
    let noScreen = AndroidEmulatorError.launchFailed(.noLauncherActivity)
    #expect(AndroidDevicesText.installedButNotLaunchedMessage(for: noScreen) != AndroidDevicesText
      .message(for: noScreen))
    #expect(AndroidDevicesText.installedButNotLaunchedMessage(for: .appCommandFailed)
      == AndroidDevicesText.message(for: .appCommandFailed))
    // apk 손상은 검사와 기기 거절이 같은 문구다.
    #expect(AndroidDevicesText.message(for: AndroidEmulatorError.installFailed(.notAPK))
      == AndroidDevicesText.message(for: AndroidPackageError.unreadable))
    #expect(AndroidDevicesText.appActionBlockReason(.notBooted) != AndroidDevicesText
      .appActionBlockReason(.unavailable))
  }

  @Test("초기화 거절은 경로를 알면 끝에 보인다")
  func unsafeFolder() {
    let folder = URL(filePath: "/Users/fake/x/", directoryHint: .isDirectory)
    let message = AndroidDevicesText.message(for: .unsafeDeviceFolder(folder))
    #expect(message?.hasSuffix("(/Users/fake/x)") == true)
    #expect(message != AndroidDevicesText.message(for: .unsafeDeviceFolder(nil)))
  }
}

/// iOS 기기 만들기와 같은 키·값으로 둔 이름 문제 문구 (Feature 끼리 의존하지 않기 위해, ARCHITECTURE §4 화면 문자열 행).
/// Launcher 원본 String Catalog 를 소스 경로로 읽어, 한쪽만 고치면 실패한다.
struct NameProblemSyncTests {
  static let launcherCatalog = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "../../Launcher/Sources/Localizable.xcstrings")
    .standardized

  @Test("이름 문제 문구 3개가 Launcher 원본에 같은 키·값으로 있다")
  func nameProblemsMatchLauncher() throws {
    let data = try Data(contentsOf: Self.launcherCatalog)
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let strings = try #require(root["strings"] as? [String: Any])
    for problem in [DeviceNameProblem.empty, .tooLong, .containsControlCharacter] {
      let text = AndroidDevicesText.nameProblem(problem)
      let entry = strings[text] as? [String: Any]
      let localizations = entry?["localizations"] as? [String: Any]
      let unit = (localizations?["ko"] as? [String: Any])?["stringUnit"] as? [String: Any]
      #expect(unit?["value"] as? String == text, "Launcher 에 없거나 다른 값: \(text)")
    }
  }
}

/// 화면 문구에는 기기 상표명을 쓰지 않는다 (ARCHITECTURE §4 Android 기기 행). 폴더블의 `hw.device.name` 은 config 에만 쓰는
/// 화면에 보이지 않는 값이다. 원본 String Catalog 를 소스 경로로 읽어 모든 키·ko 값도 본다.
struct BrandNameTests {
  static let catalog = URL(filePath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "../Sources/Localizable.xcstrings")
    .standardized
  static let brands = ["pixel", "samsung", "galaxy"]

  @Test("화면 모양·만들기 안내 문구와 String Catalog 에 기기 상표명이 없다")
  func noBrandNames() throws {
    let texts = AndroidDeviceProfile.all.map(AndroidDevicesText.profileOption)
      + [
        AndroidDevicesText.studioDevicesGuide, AndroidDevicesText.foldableImageUnsupported(foldableImages: [.sample]),
        AndroidDevicesText.foldableNoImage,
      ]
    let data = try Data(contentsOf: Self.catalog)
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let strings = try #require(root["strings"] as? [String: Any])
    let catalogTexts = strings.flatMap { key, entry in
      let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any]
      let unit = (localizations?["ko"] as? [String: Any])?["stringUnit"] as? [String: Any]
      return [key, unit?["value"] as? String ?? ""]
    }
    #expect(!strings.isEmpty)
    for text in texts + catalogTexts {
      let lowered = text.lowercased()
      for brand in Self.brands {
        #expect(!lowered.contains(brand), "\(text)")
      }
    }
  }
}

/// iOS 링크 열기와 같은 키·값으로 둔 링크 문구 (이름 문제와 같은 방식).
struct LinkProblemSyncTests {
  @Test("링크 열기 문구 8개가 Launcher 원본에 같은 키·값으로 있다")
  func linkTextsMatchLauncher() throws {
    let data = try Data(contentsOf: NameProblemSyncTests.launcherCatalog)
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let strings = try #require(root["strings"] as? [String: Any])
    let problems = try [DeepLinkProblem.malformed, .missingScheme]
      .map { try #require(AndroidDevicesText.linkProblem($0)) }
    let texts = problems + [
      AndroidDevicesText.openURLButton, AndroidDevicesText.linkField, AndroidDevicesText.linkPrompt,
      AndroidDevicesText.openURLConfirmButton, AndroidDevicesText.urlNotHandledMessage,
      AndroidDevicesText.taskLabel(for: .openURL),
    ]
    for text in texts {
      let entry = strings[text] as? [String: Any]
      let localizations = entry?["localizations"] as? [String: Any]
      let unit = (localizations?["ko"] as? [String: Any])?["stringUnit"] as? [String: Any]
      #expect(unit?["value"] as? String == text, "Launcher 에 없거나 다른 값: \(text)")
    }
    #expect(AndroidDevicesText.linkProblem(.empty) == nil)
  }
}

/// `AndroidDevicesText` 가 돌려줄 수 있는 문구.
enum AndroidDevicesTextCatalog {
  struct Formatted {
    let key: String
    let arguments: [any CVarArg]
    let text: String
  }

  static let reasons: [AndroidVirtualDevice.UnavailableReason] = [
    .unsupportedName, .folderMissing, .configUnreadable, .systemImageMissing(nil),
    .systemImageMissing(.sample), .unsupportedABI("x86_64"),
  ]

  /// 취소 밖의 모든 에러 (`.deviceUnavailable` 은 행 이유와 같아 하나만, 이름 문제도 하나만).
  static let errors: [AndroidEmulatorError] = [
    .sdkUnavailable, .deviceNotFound, .deviceUnavailable(.folderMissing), .deviceRunning, .emulatorLaunchFailed,
    .emulatorExited(1), .bootTimedOut, .adbUnavailable, .shutdownTimedOut, .invalidDeviceName(.tooLong),
    .nameUnavailable, .creationOptionUnavailable, .avdFolderUnavailable, .fileOperationFailed,
    .unsafeDeviceFolder(nil), .unsafeDeviceFolder(URL(filePath: "/x")), .deviceNotBooted, .installTimedOut,
    .launchFailed(.notInstalled), .launchFailed(.noLauncherActivity), .urlNotHandled, .appCommandFailed,
    .captureFailed, .captureFileUnwritable, .recordingFailed, .recordingEmpty, .recordingLost,
    .recordingTransferTimedOut, .recordingDisplayOff,
  ] + installFailures.map { .installFailed($0) }

  static let installFailures: [AndroidInstallFailure] = [
    .olderSDK, .noMatchingABIs, .updateIncompatible, .versionDowngrade, .noCertificates, .notAPK, .deprecatedSDK,
    .insufficientStorage, .conflict, .missingSharedLibrary, .testOnly, .missingSplit, .other("INSTALL_FAILED_X"),
    .other(nil),
  ]

  static let packageErrors: [AndroidPackageError] = [
    .notLocalFile, .fileNotFound, .appBundle, .splitPackage, .notAPK, .unreadable, .unsafeEntry, .unsigned,
    .inspectionUnavailable,
  ]

  static let notices: [AndroidDevicesNotice] = {
    let label = AndroidDeviceLabel(.phoneSample)
    return [
      .refreshFailed(.adbUnavailable), .bootFailed(label, .bootTimedOut), .shutdownFailed(label, .adbUnavailable),
      .createFailed(label, .nameUnavailable), .deleteFailed(label, .deviceRunning),
      .eraseFailed(label, .fileOperationFailed), .folderKept(label, URL(filePath: "/x")),
      .batchBootFinished(AndroidBatchBootReport(entries: [.init(device: label, error: .bootTimedOut)])),
      .batchInstallFailed([label, label], .package(.unsigned)),
      .batchInstallFinished(AndroidBatchInstallReport(entries: [
        .init(device: label, result: .installFailed(.deviceBusy)),
      ])),
      .installFailed(label, .multipleItems), .installFailed(label, .package(.unsigned)),
      .installFailed(label, .rejected(.requiresNewerAPI(required: 99, device: 37))),
      .installFailed(label, .deviceNotReady(.notBooted)), .installFailed(label, .emulator(.installTimedOut)),
      .installedButNotLaunched(label, .launchFailed(.noLauncherActivity)),
      .launchFailed(label, .deviceNotReady(.unavailable)), .launchFailed(label, .emulator(.appCommandFailed)),
      .openURLFailed(label, .emulator(.urlNotHandled)),
      .installFailed(label, .download(.offline, origin: .enteredURL)),
      .installFailed(label, .download(.httpStatus(404), origin: .catalog)),
      .installFailed(label, .downloadedPackage(.unreadable, isWebPage: true, origin: .enteredURL)),
      .installFailed(label, .downloadedPackage(.appBundle, isWebPage: false, origin: .catalog)),
      .screenshotFailed(label, .workspace(.folderUnavailable)), .screenshotFailed(label, .emulator(.captureFailed)),
      .screenshotRevealFailed(label, .fileNotFound), .recordingFailed(label, .workspace(.fileNameUnavailable)),
      .recordingFailed(label, .emulator(.recordingLost)), .recordingFailed(label, .emulator(.captureFileUnwritable)),
      .recordingInterrupted(label), .recordingStoppedByDevice(label), .recordingAtTimeLimit(label),
      .recordingRevealFailed(label, .fileNotFound),
    ]
  }()

  /// 서식이 없는 문구 (키 = 값).
  static var plain: [String] {
    var texts: [String] = [
      AndroidDevicesText.okButton, AndroidDevicesText.bootSelectionButton, AndroidDevicesText.selectionGuide,
      AndroidDevicesText.bootSelectionHelp, AndroidDevicesText.bootSelectionUnavailable,
      AndroidDevicesText.createDeviceButton, AndroidDevicesText.refreshButton, AndroidDevicesText.setupButton,
      AndroidDevicesText.setupButtonHelp, AndroidDevicesText.openSetupButton, AndroidDevicesText.creatingLabel,
      AndroidDevicesText.loading, AndroidDevicesText.loadFailedTitle, AndroidDevicesText.retryButton,
      AndroidDevicesText.emptyTitle, AndroidDevicesText.emptyMessage, AndroidDevicesText.noImageTitle,
      AndroidDevicesText.noImageMessage, AndroidDevicesText.createUnavailableNotice,
      AndroidDevicesText.unavailableLabel, AndroidDevicesText.bootingHelp, AndroidDevicesText.bootButton,
      AndroidDevicesText.shutdownButton, AndroidDevicesText.deviceActionsMenu, AndroidDevicesText.eraseMenuItem,
      AndroidDevicesText.deleteMenuItem, AndroidDevicesText.cancelButton, AndroidDevicesText.createSheetTitle,
      AndroidDevicesText.nameField, AndroidDevicesText.imagePicker, AndroidDevicesText.profilePicker,
      AndroidDevicesText.createConfirmButton, AndroidDevicesText.studioDevicesGuide, AndroidDevicesText.studioLinkTitle,
      AndroidDevicesText.foldableNoImage,
      AndroidDevicesText.title(for: .refreshFailed(.adbUnavailable)),
      AndroidDevicesText.title(for: .createFailed(AndroidDeviceLabel(.phoneSample), .nameUnavailable)),
      AndroidDevicesText.installAppButton, AndroidDevicesText.installFromFileMenuItem,
      AndroidDevicesText.installAppHelp,
      AndroidDevicesText.launchAppButton, AndroidDevicesText.launchAppHelp, AndroidDevicesText.loadingPackages,
      AndroidDevicesText.noInstalledPackages, AndroidDevicesText.packagePicker, AndroidDevicesText.launchConfirmButton,
      AndroidDevicesText.closeButton, AndroidDevicesText.message(for: AndroidAppInstallFailure.multipleItems),
      AndroidDevicesText.installedButNotLaunchedMessage(for: .launchFailed(.noLauncherActivity)),
      AndroidDevicesText.openURLButton, AndroidDevicesText.openURLHelp, AndroidDevicesText.linkField,
      AndroidDevicesText.linkPrompt, AndroidDevicesText.openURLConfirmButton, AndroidDevicesText.urlNotHandledMessage,
    ]
    texts += [AndroidAppActionBlockReason.notBooted, .unavailable].map { AndroidDevicesText.appActionBlockReason($0) }
    texts += [DeepLinkProblem.malformed, .missingScheme].compactMap { AndroidDevicesText.linkProblem($0) }
    texts += self.packageErrors.map { AndroidDevicesText.message(for: $0) }
    texts += [AndroidVirtualDevice.State.shutdown, .booting, .booted].map { AndroidDevicesText.stateLabel(for: $0) }
    texts += [AndroidDeviceTask.boot, .shutdown, .delete, .erase, .installApp, .launchApp, .openURL].map {
      AndroidDevicesText.taskLabel(for: $0)
    }
    texts += [DeviceActionBlockReason.notShutdown, .unavailable].map { AndroidDevicesText.blockReason($0) }
    texts += [AndroidDeviceConfirmation.Action.delete, .erase].flatMap {
      [AndroidDevicesText.confirmationMessage(for: $0), AndroidDevicesText.confirmButton(for: $0)]
    }
    texts += [DeviceNameProblem.empty, .tooLong, .containsControlCharacter].map { AndroidDevicesText.nameProblem($0) }
    texts += self.errors.compactMap { error -> String? in
      switch error {
      case .deviceUnavailable, .invalidDeviceName, .unsafeDeviceFolder(.some), .installFailed(.other(.some)):
        nil
      default:
        AndroidDevicesText.message(for: error)
      }
    }
    texts += self.reasons.compactMap { reason -> String? in
      switch reason {
      case .systemImageMissing(.some), .unsupportedABI:
        nil
      default:
        AndroidDevicesText.reason(for: reason)
      }
    }
    return Array(Set(texts))
  }

  /// 보간이 든 문구: 카탈로그 키, 표의 값에 넣을 인자, 코드가 만든 문구.
  static var formatted: [Formatted] {
    let label = AndroidDeviceLabel(.phoneSample)
    let labelText = AndroidDevicesText.label(label)
    let delete = AndroidDeviceConfirmation(
      action: .delete,
      deviceID: AndroidVirtualDevice.phoneSample.id,
      device: label
    )
    let erase = AndroidDeviceConfirmation(action: .erase, deviceID: AndroidVirtualDevice.phoneSample.id, device: label)
    let folder = URL(filePath: "/Users/fake/x/", directoryHint: .isDirectory)
    let timedOut = AndroidDevicesText.message(for: AndroidEmulatorError.bootTimedOut) ?? ""
    let okReport = AndroidBatchBootReport(entries: [
      .init(device: label, error: nil),
      .init(device: label, error: .cancelled),
    ])
    let profiles = AndroidDeviceProfile.all
    return [
      Formatted(
        key: "“%@”",
        arguments: ["폰"],
        text: AndroidDevicesText.label(AndroidDeviceLabel(name: "폰", apiLabel: nil))
      ),
      Formatted(key: "“%@” (API %@)", arguments: ["테스트 폰", "37.0"], text: labelText),
      Formatted(key: "API %@", arguments: ["37.0"], text: AndroidDevicesText.apiLabel(.sample)),
      Formatted(
        key: "이 시스템 이미지에는 폴더블 설정이 없어 폴더블을 만들 수 없습니다. 폴더블은 %@ 로 만들 수 있습니다.",
        arguments: ["API 37.0 · google_apis"],
        text: AndroidDevicesText.foldableImageUnsupported(foldableImages: [.sample])
      ),
      Formatted(key: "API %@ · %@", arguments: ["37.0", "google_apis"], text: AndroidDevicesText.imageOption(.sample)),
      Formatted(
        key: "%@ 기기를 켜지 못했습니다",
        arguments: [labelText],
        text: AndroidDevicesText.title(for: .bootFailed(label, .bootTimedOut))
      ),
      Formatted(
        key: "%@ 기기를 끄지 못했습니다",
        arguments: [labelText],
        text: AndroidDevicesText.title(for: .shutdownFailed(label, .bootTimedOut))
      ),
      Formatted(
        key: "%@ 기기를 삭제하지 못했습니다",
        arguments: [labelText],
        text: AndroidDevicesText.title(for: .deleteFailed(label, .bootTimedOut))
      ),
      Formatted(
        key: "%@ 기기를 초기화하지 못했습니다",
        arguments: [labelText],
        text: AndroidDevicesText.title(for: .eraseFailed(label, .bootTimedOut))
      ),
      Formatted(
        key: "%@ 기기를 목록에서 지웠습니다",
        arguments: [labelText],
        text: AndroidDevicesText.title(for: .folderKept(label, folder))
      ),
      Formatted(
        key: "기기 폴더가 예상한 위치가 아니어서 지우지 않고 남겨 두었습니다: %@",
        arguments: ["/Users/fake/x"],
        text: AndroidDevicesText.message(for: .folderKept(label, folder))
      ),
      Formatted(key: "%@ 기기를 삭제할까요?", arguments: [labelText], text: AndroidDevicesText.confirmationTitle(for: delete)),
      Formatted(key: "%@ 기기를 초기화할까요?", arguments: [labelText], text: AndroidDevicesText.confirmationTitle(for: erase)),
      Formatted(
        key: "기기 %lld대를 켜지 못했습니다",
        arguments: [1],
        text: AndroidDevicesText.batchTitle(for: AndroidBatchBootReport(entries: [.init(
          device: label,
          error: .bootTimedOut
        )]))
      ),
      Formatted(key: "기기 %lld대 중 %lld대를 켰습니다", arguments: [2, 1], text: AndroidDevicesText.batchTitle(for: okReport)),
      Formatted(
        key: "%@: 켰습니다.",
        arguments: [labelText],
        text: AndroidDevicesText.batchMessage(for: AndroidBatchBootReport(entries: [.init(device: label, error: nil)]))
      ),
      Formatted(
        key: "%@: 켜지 못했습니다.",
        arguments: [labelText],
        text: AndroidDevicesText.batchMessage(for: AndroidBatchBootReport(entries: [.init(
          device: label,
          error: .cancelled
        )]))
      ),
      Formatted(
        key: "%@: 켜지 못했습니다. %@",
        arguments: [labelText, timedOut],
        text: AndroidDevicesText.batchMessage(for: AndroidBatchBootReport(entries: [.init(
          device: label,
          error: .bootTimedOut
        )]))
      ),
      Formatted(
        key: "기기 폴더 위치가 예상과 달라 초기화하지 않았습니다. 기기를 삭제한 뒤 새로 만드세요. (%@)",
        arguments: ["/Users/fake/x"],
        text: AndroidDevicesText.message(for: .unsafeDeviceFolder(folder)) ?? ""
      ),
      Formatted(
        key: "이 기기에 필요한 시스템 이미지(API %@, %@)가 지금 Android 도구 위치에 없어 사용할 수 없습니다. 설정에서 Android 도구 위치를 확인하거나, 기기를 삭제하세요.",
        arguments: ["37.0", "google_apis"],
        text: AndroidDevicesText.reason(for: .systemImageMissing(.sample))
      ),
      Formatted(
        key: "이 Mac 에서 실행할 수 없는 시스템 이미지(%@)를 쓰는 기기입니다. 삭제만 할 수 있습니다.",
        arguments: ["x86_64"],
        text: AndroidDevicesText.reason(for: .unsupportedABI("x86_64"))
      ),
      Formatted(key: "휴대전화 (%@)", arguments: ["1080×2400"], text: AndroidDevicesText.profileOption(profiles[0])),
      Formatted(key: "작은 휴대전화 (%@)", arguments: ["720×1280"], text: AndroidDevicesText.profileOption(profiles[1])),
      Formatted(key: "태블릿 (%@)", arguments: ["2560×1600"], text: AndroidDevicesText.profileOption(profiles[2])),
      Formatted(key: "폴더블 (%@)", arguments: ["2076×2152"], text: AndroidDevicesText.profileOption(profiles[3])),
    ] + self.appFormatted(label: label, labelText: labelText)
  }
}

extension AndroidDevicesTextCatalog {
  /// 앱 설치·실행·링크 열기의 보간 문구.
  static func appFormatted(label: AndroidDeviceLabel, labelText: String) -> [Formatted] {
    [
      Formatted(
        key: "%@ 기기에서 앱 실행",
        arguments: [labelText],
        text: AndroidDevicesText.launchAppSheetTitle(for: label)
      ),
      Formatted(
        key: "%@ 기기에 앱을 설치하지 못했습니다",
        arguments: [labelText],
        text: AndroidDevicesText.title(for: .installFailed(label, .multipleItems))
      ),
      Formatted(
        key: "%@ 기기에 앱을 설치했지만 실행하지 못했습니다",
        arguments: [labelText],
        text: AndroidDevicesText.title(for: .installedButNotLaunched(label, .appCommandFailed))
      ),
      Formatted(
        key: "%@ 기기에서 앱을 실행하지 못했습니다",
        arguments: [labelText],
        text: AndroidDevicesText.title(for: .launchFailed(label, .emulator(.appCommandFailed)))
      ),
      Formatted(
        key: "%@ 기기에서 링크 열기",
        arguments: [labelText],
        text: AndroidDevicesText.openURLSheetTitle(for: label)
      ),
      Formatted(
        key: "%@ 기기에서 링크를 열지 못했습니다",
        arguments: [labelText],
        text: AndroidDevicesText.title(for: .openURLFailed(label, .emulator(.urlNotHandled)))
      ),
      Formatted(
        key: "이 앱에는 이 기기(%@)에서 실행할 코드가 없습니다 (앱: %@). 개발자에게 %@ 용 코드가 포함된 apk 를 요청하세요.",
        arguments: ["arm64-v8a, x86_64", "armeabi-v7a, x86", "arm64-v8a"],
        text: AndroidDevicesText.message(for: AndroidInstallProblem.noMatchingABI(
          app: ["armeabi-v7a", "x86"],
          device: ["arm64-v8a", "x86_64"]
        ))
      ),
      Formatted(
        key: "이 앱은 Android API %lld 이상에서 실행됩니다. 이 기기는 API %lld 입니다. 더 높은 API 의 기기를 만들어 설치하세요.",
        arguments: [99, 37],
        text: AndroidDevicesText.message(for: AndroidInstallProblem.requiresNewerAPI(required: 99, device: 37))
      ),
      Formatted(
        key: "설치하지 못했습니다 (%@). 파일을 다시 골라 시도하고, 계속되면 이 코드를 개발자에게 알려 주세요.",
        arguments: ["INSTALL_FAILED_X"],
        text: AndroidDevicesText.message(for: AndroidEmulatorError.installFailed(.other("INSTALL_FAILED_X"))) ?? ""
      ),
    ]
  }
}
