import AndroidSDKInterface
import AndroidSDKTesting
import Core
import Foundation
import Testing
@testable import AndroidSetupFeature

struct AndroidSetupResourcesTests {
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
    for text in AndroidSetupTextCatalog.plain {
      #expect(table[text] == text, "\(text)")
    }
    // 보간이 든 키는 표의 값으로 만든 문구가 코드의 문구와 같아야 한다 (키가 어긋나면 코드 문자열로 서식을 만들어 겉보기에 멀쩡하다).
    for sample in AndroidSetupTextCatalog.formatted {
      #expect(table[sample.key] == sample.key, "\(sample.key)")
      #expect(String(format: table[sample.key] ?? "", arguments: sample.arguments) == sample.text, "\(sample.key)")
    }
    let keys = Set(AndroidSetupTextCatalog.plain).union(AndroidSetupTextCatalog.formatted.map(\.key))
    #expect(keys == Set(table.keys))
  }
}

/// 문구 함수가 돌려주는 값.
struct AndroidSetupTextTests {
  private let locale = Locale(identifier: "ko_KR")

  @Test("모든 문구가 비어 있지 않은 한국어다")
  func textsAreNonEmptyKorean() {
    for text in AndroidSetupTextCatalog.plain + AndroidSetupTextCatalog.formatted.map(\.text) {
      #expect(!text.isEmpty)
      #expect(text.unicodeScalars.contains { (0xAC00 ... 0xD7A3).contains($0.value) }, "\(text)")
    }
    #expect(AndroidSetupText.title(for: nil).isEmpty)
  }

  @Test("계획 실패는 원인마다 다르고 취소는 줄이 없다")
  func planErrorMessages() {
    let messages = AndroidSetupTextCatalog.planErrors.compactMap { AndroidSetupText.message(for: $0) }
    #expect(messages.count == AndroidSetupTextCatalog.planErrors.count)
    #expect(Set(messages).count == messages.count)
    #expect(AndroidSetupText.message(for: AndroidSDKPlanError.cancelled) == nil)
    let offline = AndroidSetupText.message(for: AndroidSDKPlanError.download(.offline))
    #expect(offline?.hasPrefix(AndroidSetupText.planDownloadFailed) == true)
  }

  @Test("설치 실패는 원인마다 다르고, 받기 실패는 어느 도구인지와 원인을 함께 보인다")
  func installErrorMessages() {
    let messages = AndroidSetupTextCatalog.installErrors.map { AndroidSetupText.message(for: $0) }
    #expect(Set(messages).count == messages.count)
    let download = AndroidSetupText.message(for: AndroidSDKInstallError.download(.systemImage, .timedOut))
    #expect(download.contains(AndroidSetupText.componentTitle(.systemImage)))
    #expect(download.contains(AndroidSetupText.message(for: AndroidDownloadFailure.timedOut)))
  }

  @Test("받기 실패 원인은 모두 다르다")
  func downloadFailureMessages() {
    let messages = AndroidSetupTextCatalog.downloadFailures.map { AndroidSetupText.message(for: $0) }
    #expect(Set(messages).count == messages.count)
  }

  @Test("저장 공간 부족은 필요한 양과 읽었으면 남은 양을 보인다")
  func insufficientSpace() {
    let both = AndroidSetupText.insufficientSpaceMessage(
      required: 9_000_000_000,
      available: 2_000_000_000,
      locale: self.locale
    )
    #expect(both.contains("9GB"))
    #expect(both.contains("2GB"))
    let requiredOnly = AndroidSetupText.insufficientSpaceMessage(
      required: 9_000_000_000,
      available: nil,
      locale: self.locale
    )
    #expect(requiredOnly.contains("9GB"))
    #expect(requiredOnly != both)
  }

  @Test("설치 결과: 모두 설치·일부 이미 있음·모두 이미 있음이 다르다")
  func finishedMessages() {
    let all = AndroidSetupText.resultMessage(for: .init(
      kind: .finished(AndroidSDKInstallOutcome(installed: [.platformTools], alreadyPresent: [])),
      root: .sample
    ))
    let some = AndroidSetupText.resultMessage(for: .init(
      kind: .finished(AndroidSDKInstallOutcome(installed: [.platformTools], alreadyPresent: [.emulator])),
      root: .sample
    ))
    let none = AndroidSetupText.resultMessage(for: .init(
      kind: .finished(AndroidSDKInstallOutcome(installed: [], alreadyPresent: [.emulator])),
      root: .sample
    ))
    #expect(Set([all, some, none]).count == 3)
    #expect(all == "Android 도구를 설치했습니다.")
  }

  @Test("필요한 저장 공간: 같은 볼륨이면 한 줄(설치 후 어림 + 가장 큰 받기), 다르면 받기·설치 두 줄")
  func requiredSpaceLines() {
    let same = AndroidSetupText.requiredSpaceLines(.sample, locale: self.locale)
    let plan = AndroidSDKInstallPlan.sample
    let total = plan.estimatedInstallBytes + AndroidSelectedPackage.systemImageSample.archive.size
    #expect(same == ["Macintosh HD 에 약 \(AndroidSetupText.bytes(total, locale: self.locale))"])
    let external = AndroidSetupText.requiredSpaceLines(.externalVolumeSample, locale: self.locale)
    let largest = AndroidSelectedPackage.systemImageSample.archive.size
    #expect(external == [
      "받기: 시동 디스크에 \(AndroidSetupText.bytes(largest, locale: self.locale))",
      "설치: Tools 에 약 \(AndroidSetupText.bytes(plan.estimatedInstallBytes, locale: self.locale))",
    ])
    let unnamed = AndroidSDKInstallPlan(
      root: .chosenSample,
      sdkVolumeName: nil,
      sameVolumeAsDownloads: false,
      packages: [.platformToolsSample],
      licenses: [.sdkSample]
    )
    #expect(AndroidSetupText.requiredSpaceLines(unnamed, locale: self.locale).last?.contains("SDK 위치의 디스크") == true)
  }

  @Test("진행 숫자: 패키지 번호·이름, 받는 중일 때만 그 패키지 바이트, 전체 바이트와 막대 값")
  func progressTexts() {
    let downloading = AndroidSDKInstallProgress.sample(
      index: 2,
      phase: .downloading(received: 0, expected: 416_112_708)
    )
    #expect(AndroidSetupText.packageLine(downloading) == "2/3 · 에뮬레이터 (emulator)")
    #expect(AndroidSetupText.packageBytes(downloading, locale: self.locale)?.hasSuffix(" / 416.1MB") == true)
    let extracting = AndroidSDKInstallProgress.sample(index: 2, phase: .extracting)
    #expect(AndroidSetupText.packageBytes(extracting, locale: self.locale) == nil)
    let fraction = AndroidSetupText.totalFraction(extracting)
    let expected = Double(16_110_554 + 416_112_708) / Double(AndroidSDKInstallPlan.sample.downloadBytes)
    #expect(fraction == expected)
    let empty = AndroidSDKInstallProgress(
      packageIndex: 1, packageCount: 1, component: .platformTools, phase: .finishing, completedBytes: 0, totalBytes: 0
    )
    #expect(AndroidSetupText.totalFraction(empty) == nil)
  }

  @Test("구성 요소 상세: 도구는 revision, 시스템 이미지는 API 폴더 이름, 설치되지 않았으면 없음")
  func componentDetail() {
    let revision = AndroidRevision(major: 37, minor: 0, micro: 1)
    #expect(AndroidSetupText
      .componentDetail(.platformTools, status: .installed(revision), installedSystemImages: []) == "37.0.1")
    #expect(AndroidSetupText.componentDetail(.emulator, status: .installed(nil), installedSystemImages: []) == nil)
    #expect(AndroidSetupText.componentDetail(
      .systemImage,
      status: .installed(AndroidRevision(major: 7)),
      installedSystemImages: ["android-36", "android-37.0"]
    ) == "android-36, android-37.0")
    #expect(AndroidSetupText.componentDetail(.platformTools, status: .missing, installedSystemImages: []) == nil)
  }

  @Test("위치 문제 안내는 잠겼으면 담당자 문의 하나다")
  func lockedLocationMessage() {
    let locked = AndroidSetupTextCatalog.locationProblems.map {
      AndroidSetupText.locationMessage(for: $0, isLocked: true)
    }
    #expect(Set(locked).count == 1)
    #expect(AndroidSetupText.path(AndroidSDKRoot.sample.url) == "/Users/fake/Library/Android/sdk")
  }
}

/// `AndroidSetupText` 가 돌려줄 수 있는 문구.
enum AndroidSetupTextCatalog {
  struct Formatted {
    let key: String
    let arguments: [any CVarArg]
    let text: String
  }

  static let locationProblems: [AndroidSDKLocationProblem] = [
    .missing, .notDirectory, .brokenLink, .unreadable, .invalidSetting,
  ]
  static let componentProblems: [AndroidComponentProblem] = [
    .executableMissing, .notExecutable, .imageFilesMissing, .unreadable,
  ]
  static let componentStatuses: [AndroidComponentStatus] = [.installed(nil), .missing, .unusable(.unreadable)]
  static let phases: [AndroidSDKInstallProgress.Phase] = [
    .downloading(received: 0, expected: 1), .verifying, .extracting, .finishing,
  ]
  static let downloadFailures: [AndroidDownloadFailure] = [
    .insecureRedirect, .offline, .hostNotFound, .cannotConnect, .timedOut, .connectionLost,
    .secureConnectionFailed, .insufficientDiskSpace, .tooLarge, .storageUnavailable, .failed,
  ]
  /// `.download` 는 앞 문장 + 원인, `.noCompatiblePackage` 는 서식 문구라 `formatted` 에서 본다.
  static let planErrors: [AndroidSDKPlanError] = [
    .download(.offline), .repositoryUnreadable, .noCompatiblePackage(.emulator), .sdkFolderUnavailable,
  ]
  static let installErrors: [AndroidSDKInstallError] = [
    .download(.emulator, .offline), .checksumMismatch(.emulator), .archiveUnreadable(.emulator),
    .archiveUnsafe(.emulator), .insufficientDiskSpace(.emulator, required: 1, available: nil),
    .sdkFolderUnavailable, .destinationExists(.emulator), .licenseNotAccepted, .sdkLocationChanged, .cancelled,
  ]

  /// 서식이 없는 문구 (키 = 값).
  static var plain: [String] {
    var texts: [String] = [
      AndroidSetupText.checkingTitle, AndroidSetupText.readyTitle, AndroidSetupText.readyMessage,
      AndroidSetupText.notReadyTitle, AndroidSetupText.notReadyMessage, AndroidSetupText.locationProblemTitle,
      AndroidSetupText.installingTitle, AndroidSetupText.installingMessage, AndroidSetupText.verifyingInstallTitle,
      AndroidSetupText.locationLabel, AndroidSetupText.defaultLocationNote, AndroidSetupText.absentLocationNote,
      AndroidSetupText.lockedLocationNote, AndroidSetupText.installButton, AndroidSetupText.recheckButton,
      AndroidSetupText.recheckingLabel, AndroidSetupText.revealButton, AndroidSetupText.openSettingsButton,
      AndroidSetupText.cancelButton, AndroidSetupText.okButton, AndroidSetupText.fetchingPlanLabel,
      AndroidSetupText.deviceListButton,
      AndroidSetupText.consentTitle, AndroidSetupText.consentMessage, AndroidSetupText.consentRecordNote,
      AndroidSetupText.acceptButton, AndroidSetupText.downloadSizeLabel, AndroidSetupText.installSizeLabel,
      AndroidSetupText.requiredSpaceLabel, AndroidSetupText.unknownVolumeName,
      AndroidSetupText.installLocationLabel, AndroidSetupText.cancellingLabel, AndroidSetupText.cannotCancelNote,
      AndroidSetupText.startingLabel, AndroidSetupText.quitAfterCancelNote, AndroidSetupText.quitAfterInstallNote,
      AndroidSetupText.terminationTitle, AndroidSetupText.terminationMessage,
      AndroidSetupText.continueInstallButton, AndroidSetupText.quitButton, AndroidSetupText.planDownloadFailed,
    ]
    texts += self.locationProblems.map { AndroidSetupText.locationTitle(for: $0) }
    texts += self.locationProblems.map { AndroidSetupText.locationMessage(for: $0, isLocked: false) }
    texts.append(AndroidSetupText.locationMessage(for: .missing, isLocked: true))
    texts += [AndroidSDKInstallBlocker.notWritable(AndroidSDKRoot.sample.url), .unsupportedVolume]
      .map { AndroidSetupText.blockerMessage($0) }
    texts += AndroidSDKComponent.allCases.map { AndroidSetupText.componentTitle($0) }
    texts += self.componentStatuses.map { AndroidSetupText.statusLabel($0) }
    texts += self.componentProblems.map { AndroidSetupText.problemMessage($0) }
    texts += self.phases.map { AndroidSetupText.phaseTitle($0) }
    texts += [AndroidSetupText.title(for: .revealFailed(.fileNotFound))]
    texts += [AndroidSetupText.message(for: AndroidSetupNotice.revealFailed(.fileNotFound))]
    texts += self.planErrors.dropFirst().compactMap { error -> String? in
      if case .noCompatiblePackage = error {
        return nil
      }
      return AndroidSetupText.message(for: error)
    }
    texts += self.downloadFailures.map { AndroidSetupText.message(for: $0) }
    texts += self.installErrors.compactMap { error -> String? in
      switch error {
      case .download, .insufficientDiskSpace, .destinationExists:
        nil
      default:
        AndroidSetupText.message(for: error)
      }
    }
    texts += self.finishedTexts
    return Array(Set(texts))
  }

  private static var finishedTexts: [String] {
    let outcomes = [
      AndroidSDKInstallOutcome(installed: [.emulator], alreadyPresent: []),
      AndroidSDKInstallOutcome(installed: [.emulator], alreadyPresent: [.systemImage]),
      AndroidSDKInstallOutcome(installed: [], alreadyPresent: [.systemImage]),
    ]
    return outcomes.map { AndroidSetupText.resultMessage(for: .init(kind: .finished($0), root: .sample)) }
  }

  /// 보간이 든 문구: 카탈로그 키, 표의 값에 넣을 인자, 코드가 만든 문구.
  static var formatted: [Formatted] {
    let name = AndroidSetupText.componentTitle(.emulator)
    let locale = Locale.current
    let plan = AndroidSDKInstallPlan.externalVolumeSample
    let install = AndroidSetupText.bytes(plan.estimatedInstallBytes, locale: locale)
    let largest = AndroidSetupText.bytes(AndroidSelectedPackage.systemImageSample.archive.size, locale: locale)
    let spaceLines = AndroidSetupText.requiredSpaceLines(plan, locale: locale)
    let same = AndroidSDKInstallPlan.sample
    let sameTotal = AndroidSetupText.bytes(
      same.estimatedInstallBytes + AndroidSelectedPackage.systemImageSample.archive.size,
      locale: locale
    )
    let needed = AndroidSetupText.bytes(9_000_000_000, locale: locale)
    let left = AndroidSetupText.bytes(2_000_000_000, locale: locale)
    let path = AndroidSetupText.path(AndroidSDKRoot.sample.url)
    return [
      Formatted(key: "약 %@", arguments: [install], text: AndroidSetupText.approximateInstallSize(plan, locale: locale)),
      Formatted(key: "받기: 시동 디스크에 %@", arguments: [largest], text: spaceLines[0]),
      Formatted(key: "설치: %@ 에 약 %@", arguments: ["Tools", install], text: spaceLines[1]),
      Formatted(
        key: "%@ 에 약 %@",
        arguments: ["Macintosh HD", sameTotal],
        text: AndroidSetupText.requiredSpaceLines(same, locale: locale)[0]
      ),
      Formatted(
        key: "이 Mac 에 맞는 %@ 을(를) 찾지 못했습니다. 앱 업데이트가 필요할 수 있습니다.",
        arguments: [name],
        text: AndroidSetupText.noCompatiblePackage(name)
      ),
      Formatted(key: "%@ 을(를) 받지 못했습니다.", arguments: [name], text: AndroidSetupText.componentFailed(name)),
      Formatted(
        key: "같은 이름의 폴더가 이미 있어 %@ 을(를) 설치하지 않았습니다. Android Studio 가 설치 중이었을 수 있습니다. 다시 확인을 누르세요.",
        arguments: [name],
        text: AndroidSetupText.destinationExists(name)
      ),
      Formatted(
        key: "Google 서버가 요청을 받아 주지 않았습니다 (HTTP %lld). 잠시 뒤 다시 시도하고, 계속되면 앱을 업데이트하세요.",
        arguments: [503],
        text: AndroidSetupText.httpStatusMessage(503)
      ),
      Formatted(
        key: "원래 위치(%@)에 설치했습니다. 지금 SDK 위치에는 보이지 않습니다.",
        arguments: [path],
        text: AndroidSetupText.originalLocationNote(.sample)
      ),
      Formatted(
        key: "저장 공간이 부족해 설치하지 못했습니다. %@ 가 필요한데 %@ 남아 있습니다. 공간을 확보한 뒤 다시 시도하세요.",
        arguments: [needed, left],
        text: AndroidSetupText.insufficientSpaceMessage(
          required: 9_000_000_000,
          available: 2_000_000_000,
          locale: locale
        )
      ),
      Formatted(
        key: "저장 공간이 부족해 설치하지 못했습니다. %@ 가 필요합니다. 공간을 확보한 뒤 다시 시도하세요.",
        arguments: [needed],
        text: AndroidSetupText.insufficientSpaceMessage(required: 9_000_000_000, available: nil, locale: locale)
      ),
    ]
  }
}
