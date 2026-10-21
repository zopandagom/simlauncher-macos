import Core
import DevEnvironmentInterface
import DevEnvironmentTesting
import Foundation
import SimulatorInterface
import SimulatorTesting
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

  @Test("내려받기 숫자는 퍼센트·바이트를 보이고 없는 값은 뺀다")
  func downloadDetail() {
    let locale = Locale(identifier: "ko_KR")
    let full = RuntimeInstallProgress.downloading(fraction: 0.149, completed: 558_600_000, total: 3_760_000_000)
    #expect(SetupText.downloadDetail(full, locale: locale) == "14.9% · 558.6MB / 3.76GB")
    #expect(SetupText.downloadDetail(.downloading(fraction: 0.149), locale: locale) == "14.9%")
    let bytesOnly = RuntimeInstallProgress.downloading(fraction: nil, completed: 558_600_000, total: 3_760_000_000)
    #expect(SetupText.downloadDetail(bytesOnly, locale: locale) == "558.6MB / 3.76GB")
    // 받은 양과 전체 중 하나만 있으면 바이트는 뺀다.
    let partial = RuntimeInstallProgress.downloading(fraction: 0.5, completed: 558_600_000, total: nil)
    #expect(SetupText.downloadDetail(partial, locale: locale) == "50.0%")
    #expect(SetupText.downloadDetail(.downloading(fraction: nil), locale: locale) == nil)
    // 내려받기 단계가 아니면 숫자 줄이 없다.
    #expect(SetupText.downloadDetail(.preparing, locale: locale) == nil)
    #expect(SetupText.downloadDetail(.installing, locale: locale) == nil)
  }

  @Test("결과 줄은 기본 iOS 가 설치됨이면 방금 설치한 경우만 보이고 지난 실패·취소는 보이지 않는다")
  func resultLineWhenInstalled() {
    let installed = SetupRuntimeState.checked(.sample, .installed(SampleRuntimeImage.iOS27Point1))
    #expect(SetupText.installResultMessage(for: .finished(.installed), runtime: installed) == "iOS 시뮬레이터를 설치했습니다.")
    #expect(SetupText.installResultMessage(for: .finished(.alreadyInstalled), runtime: installed) == nil)
    // 늦은 취소로 설치된 경우 포함.
    for error in SetupTextCatalog.installErrors {
      #expect(SetupText.installResultMessage(for: .failed(error), runtime: installed) == nil, "\(error)")
    }
    #expect(SetupText.installResultMessage(for: nil, runtime: installed) == nil)
  }

  @Test("결과 줄은 설치되지 않았으면 결과마다 다르다")
  func resultLineWhenNotInstalled() {
    let notInstalled = SetupRuntimeState.checked(.sample, .notInstalled)
    let finished = SetupText.installResultMessage(for: .finished(.installed), runtime: notInstalled)
    #expect(finished == "설치가 끝났지만 iOS 시뮬레이터가 아직 보이지 않습니다. 잠시 뒤 다시 확인을 누르세요.")
    #expect(SetupText.installResultMessage(for: .finished(.alreadyInstalled), runtime: notInstalled) == finished)
    let failures: [String?] = SetupTextCatalog.installErrors.map { (error: RuntimeInstallError) -> String? in
      SetupText.installResultMessage(for: .failed(error), runtime: notInstalled)
    }
    #expect(!failures.contains(nil))
    #expect(Set(failures + [finished]).count == SetupTextCatalog.installErrors.count + 1)
    #expect(SetupText.installResultMessage(for: .failed(.cancelled), runtime: notInstalled) == "설치를 취소했습니다.")
    #expect(SetupText.installResultMessage(for: nil, runtime: notInstalled) == nil)

    // 그 밖의 런타임 상태는 상태 제목·본문이 안내하므로 결과 줄이 없다.
    for runtime in SetupTextCatalog.runtimes where !runtime.isInstalled && runtime != notInstalled {
      for result in SetupTextCatalog.installResults {
        #expect(SetupText.installResultMessage(for: result, runtime: runtime) == nil, "\(runtime) \(result)")
      }
    }
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

  static let runtimes: [SetupRuntimeState] = [
    .notChecked,
    .checked(.sample, .installed(SampleRuntimeImage.iOS27Point1)),
    .checked(.sample, .notInstalled),
    .checked(.sample, .preparing(SampleRuntimeImage.iOS27Point1)),
    .checked(.sample, .unusable(SampleRuntimeImage.iOS27Point1)),
    .defaultRuntimeUnknown,
    .failed(.commandFailed),
  ]

  static let installErrors: [RuntimeInstallError] = [.xcodeNotFound, .launchFailed, .cancelled, .failed]

  static var installResults: [SetupInstallResult] {
    var results: [SetupInstallResult] = [.finished(.installed), .finished(.alreadyInstalled)]
    results += self.installErrors.map { (error: RuntimeInstallError) -> SetupInstallResult in .failed(error) }
    return results
  }

  static var notices: [SetupNotice] {
    let appStore: [SetupNotice] = self.errors.map { SetupNotice.openAppStoreFailed($0) }
    let xcode: [SetupNotice] = self.errors.map { SetupNotice.openXcodeFailed($0) }
    return appStore + xcode
  }

  /// 식 하나로 이으면 타입 추론이 오래 걸려 Xcode 26 에서 컴파일이 실패하므로 문장마다 더한다.
  static var all: [String] {
    var texts: [String] = []
    texts += self.statuses.map { (status: DevEnvironmentStatus) -> String in SetupText.title(for: status) }
    texts += self.statuses.map { (status: DevEnvironmentStatus) -> String in SetupText.message(for: status) }
    texts.append(SetupText.failedTitle)
    texts += self.errors.map { (error: DevEnvironmentError) -> String in SetupText.message(for: error) }
    texts += SetupStep.Kind.allCases.map { (kind: SetupStep.Kind) -> String in SetupText.stepTitle(kind) }
    texts += self.notices.map { (notice: SetupNotice) -> String in SetupText.title(for: notice) }
    texts += self.notices.map { (notice: SetupNotice) -> String in SetupText.message(for: notice) }
    let labels: [String] = [
      SetupText.checkingTitle, SetupText.adminPasswordNote, SetupText.autoRecheckNote, SetupText.currentXcodeLabel,
      SetupText.openAppStoreButton, SetupText.openXcodeButton, SetupText.recheckButton, SetupText.finishButton,
      SetupText.okButton, SetupText.recheckingLabel,
    ]
    texts += labels
    texts += self.runtimes.map { (runtime: SetupRuntimeState) -> String in SetupText.title(for: runtime) }
    texts += self.runtimes.compactMap { (runtime: SetupRuntimeState) -> String? in SetupText.message(for: runtime) }
    texts += self.installTexts
    return texts
  }

  /// 설치 진행·결과·종료 확인 문구.
  static var installTexts: [String] {
    var texts: [String] = []
    let phases: [RuntimeInstallProgress.Phase] = [.preparing, .downloading, .installing]
    texts += phases.map { (phase: RuntimeInstallProgress.Phase) -> String in SetupText.phaseTitle(phase) }
    for runtime in self.runtimes {
      for result in self.installResults {
        if let message = SetupText.installResultMessage(for: result, runtime: runtime) {
          texts.append(message)
        }
      }
    }
    let labels: [String] = [
      SetupText.installingTitle, SetupText.installingMessage, SetupText.verifyingInstallTitle,
      SetupText.installButton, SetupText.otherVersionNote, SetupText.defaultRuntimeLabel,
      SetupText.cancelInstallButton, SetupText.cancellingLabel, SetupText.cannotCancelNote, SetupText.stalledNote,
      SetupText.quitAfterCancelNote, SetupText.quitAfterInstallNote, SetupText.terminationTitle,
      SetupText.terminationMessage, SetupText.continueInstallButton, SetupText.quitButton,
    ]
    texts += labels
    return texts
  }
}
