import Core
import Foundation
import SimulatorInterface
import Testing
@testable import LauncherFeature

/// 여러 기기 문구 (`LauncherText+Batch.swift`, `AppInstallFailure.deviceBusy`).
struct BatchTextTests {
  static let iPhone = LauncherNotice.Device(name: "iPhone 17", runtimeName: "iOS 27.0")
  static let iPhonePro = LauncherNotice.Device(name: "iPhone 17 Pro", runtimeName: "iOS 27.0")
  static let iPad = LauncherNotice.Device(name: "iPad (A16)", runtimeName: "iOS 26.5")

  static func report(
    _ action: BatchReport.Action,
    _ entries: [(LauncherNotice.Device, BatchDeviceResult)],
    simulatorAppError: SimulatorError? = nil
  ) -> BatchReport {
    BatchReport(
      action: action,
      entries: entries.map { BatchReport.Entry(device: $0.0, result: $0.1) },
      simulatorAppError: simulatorAppError
    )
  }

  @Test("설치 일부 성공: 제목은 몇 대 중 몇 대이고, 본문은 같은 결과를 한 줄로 묶어 처음 나온 순서로 잇는다")
  func installPartialSuccess() {
    let rejected = BatchDeviceResult.installFailed(.rejected(.requiresNewerOS(OSVersion(major: 27))))
    let report = Self.report(.install, [(Self.iPhone, .succeeded), (Self.iPad, rejected), (Self.iPhonePro, .succeeded)])
    let notice = LauncherNotice.batchFinished(report)
    #expect(LauncherText.title(for: notice) == "기기 3대 중 2대에 앱을 설치했습니다")
    let reason = LauncherText.message(for: AppInstallFailure.rejected(.requiresNewerOS(OSVersion(major: 27))))
    #expect(
      LauncherText.message(for: notice) == """
      “iPhone 17” (iOS 27.0), “iPhone 17 Pro” (iOS 27.0): 설치하고 실행했습니다.

      “iPad (A16)” (iOS 26.5): 설치하지 못했습니다. \(reason)
      """
    )
  }

  @Test("모든 기기가 같은 이유로 실패하면 제목은 모두 실패이고, 이유 문구는 한 번만 나온다")
  func installAllFailedSameReason() {
    let rejected = BatchDeviceResult.installFailed(.rejected(.missingArchitecture(.arm64)))
    let notice = LauncherNotice.batchFinished(Self.report(.install, [(Self.iPhone, rejected), (Self.iPad, rejected)]))
    #expect(LauncherText.title(for: notice) == "기기 2대에 앱을 설치하지 못했습니다")
    let reason = LauncherText.message(for: AppInstallFailure.rejected(.missingArchitecture(.arm64)))
    #expect(LauncherText
      .message(for: notice) == "“iPhone 17” (iOS 27.0), “iPad (A16)” (iOS 26.5): 설치하지 못했습니다. \(reason)")
  }

  @Test("실행만 실패한 기기는 설치는 됐으므로 성공 수에 세고, 실행 실패 줄을 보인다")
  func launchFailureCountsAsInstalled() {
    let report = Self.report(.install, [(Self.iPhone, .launchFailed(.appLaunchFailed)), (Self.iPad, .deviceBusyResult)])
    #expect(LauncherText.title(for: .batchFinished(report)) == "기기 2대 중 1대에 앱을 설치했습니다")
    let message = LauncherText.message(for: .batchFinished(report))
    #expect(
      message.hasPrefix(
        "“iPhone 17” (iOS 27.0): 설치했지만 실행하지 못했습니다. \(LauncherText.message(for: SimulatorError.appLaunchFailed))"
      )
    )
    #expect(message.hasSuffix("“iPad (A16)” (iOS 26.5): 설치하지 못했습니다. \(LauncherText.message(for: .deviceBusy))"))
  }

  @Test("설치 중 켜기 실패는 켜지 못해 설치하지 않았다는 줄이다")
  func installBootFailure() {
    let report = Self.report(.install, [(Self.iPhone, .bootFailed(.commandFailed))])
    #expect(
      LauncherText.message(for: .batchFinished(report))
        == "“iPhone 17” (iOS 27.0): 켜지 못해 설치하지 않았습니다. \(LauncherText.message(for: SimulatorError.commandFailed))"
    )
  }

  @Test("켜기 결과: 일부 성공은 몇 대 중 몇 대, 모두 실패는 켜지 못함이고, 줄은 켜기 문구다")
  func bootResults() {
    let partial = Self.report(.boot, [(Self.iPhone, .succeeded), (Self.iPad, .bootFailed(.commandFailed))])
    #expect(LauncherText.title(for: .batchFinished(partial)) == "기기 2대 중 1대를 켰습니다")
    #expect(
      LauncherText.message(for: .batchFinished(partial)) == """
      “iPhone 17” (iOS 27.0): 켰습니다.

      “iPad (A16)” (iOS 26.5): 켜지 못했습니다. \(LauncherText.message(for: SimulatorError.commandFailed))
      """
    )
    let failed = Self.report(.boot, [(Self.iPhone, .bootFailed(.commandFailed))])
    #expect(LauncherText.title(for: .batchFinished(failed)) == "기기 1대를 켜지 못했습니다")
  }

  @Test("Simulator 앱 열기 실패는 기기별 줄 뒤 끝에 한 번만 보인다")
  func simulatorAppErrorLine() {
    let report = Self.report(
      .install,
      [(Self.iPhone, .succeeded), (Self.iPad, .launchFailed(.appLaunchFailed))],
      simulatorAppError: .simulatorAppNotFound
    )
    let message = LauncherText.message(for: .batchFinished(report))
    let line = "Simulator 앱을 열지 못했습니다. \(LauncherText.message(for: SimulatorError.simulatorAppNotFound))"
    #expect(message.hasSuffix("\n\n" + line))
    #expect(message.components(separatedBy: "Simulator 앱을 열지 못했습니다.").count == 2)
    #expect(LauncherText.title(for: .batchFinished(report)) == "기기 2대 중 2대에 앱을 설치했습니다")
  }

  @Test("공통 단계 실패: 제목은 요청한 대수의 설치 실패이고, 본문은 한 기기 설치와 같은 원인 문구다")
  func commonStepFailure() {
    let failures: [AppInstallFailure] = [
      .download(.httpStatus(404)), .catalogDownload(.httpStatus(404)), .downloadedZip(.zipWithoutApp),
      .bundle(.ipaFile),
    ]
    for failure in failures {
      let notice = LauncherNotice.batchInstallFailed([Self.iPhone, Self.iPad, Self.iPhonePro], failure)
      #expect(LauncherText.title(for: notice) == "기기 3대에 앱을 설치하지 못했습니다", "\(failure)")
      #expect(LauncherText.message(for: notice) == LauncherText.message(for: failure), "\(failure)")
      #expect(LauncherText.message(for: notice) == LauncherText.message(for: .installFailed(Self.iPhone, failure)))
    }
  }

  @Test("시트 제목: 한 대면 행 메뉴와 같고 대상 줄이 없으며, 여러 대면 대수와 대상 이름 줄을 보인다")
  func sheetTitles() {
    let one = [TargetDevice(id: VirtualDevice.ID("A"), label: Self.iPhone)]
    #expect(LauncherText.installURLSheetTitle(for: one) == LauncherText.installURLSheetTitle(for: Self.iPhone))
    #expect(LauncherText.catalogSheetTitle(for: one) == LauncherText.catalogSheetTitle(for: Self.iPhone))
    #expect(LauncherText.batchTargetsLine(one) == nil)
    let two = one + [TargetDevice(id: VirtualDevice.ID("B"), label: Self.iPad)]
    #expect(LauncherText.installURLSheetTitle(for: two) == "기기 2대에 URL 에서 앱 설치")
    #expect(LauncherText.catalogSheetTitle(for: two) == "기기 2대에 카탈로그에서 앱 설치")
    #expect(LauncherText.batchTargetsLine(two) == "대상: “iPhone 17” (iOS 27.0), “iPad (A16)” (iOS 26.5)")
  }

  @Test("툴바·행 문구가 서로 다르고 비어 있지 않으며, 다른 작업 중 본문은 다시 설치를 안내한다")
  func toolbarAndRowTexts() {
    let texts = [
      LauncherText.installOnSelectionMenu, LauncherText.bootSelectionButton, LauncherText.selectionGuide,
      LauncherText.installOnSelectionHelp(count: 2), LauncherText.installOnSelectionUnavailable,
      LauncherText.bootSelectionHelp, LauncherText.bootSelectionUnavailable,
      LauncherText.batchCancelDownloadHelp(count: 2), LauncherText.cancelDownloadHelp,
    ]
    #expect(Set(texts).count == texts.count)
    for text in texts {
      #expect(!text.isEmpty)
    }
    #expect(LauncherText.selectionGuide.contains("⌘"))
    #expect(LauncherText.installOnSelectionHelp(count: 3).hasPrefix("고른 기기 3대에"))
    #expect(LauncherText.batchCancelDownloadHelp(count: 3).hasPrefix("기기 3대에 함께 받는 중입니다."))
    #expect(LauncherText.message(for: AppInstallFailure.deviceBusy).contains("다른 작업이 진행 중"))
  }
}

extension BatchDeviceResult {
  static let deviceBusyResult = BatchDeviceResult.installFailed(.deviceBusy)
}

/// 여러 기기 문구의 String Catalog 키 23개. 확인마다 표의 값(보간 키는 인자를 넣은 값)과 코드 결과를 비교한다.
/// `LauncherResourcesTests` 가 표의 키 전체를 맞출 때 이 키를 더한다.
enum BatchTextCatalog {
  static let device = CatalogTextCatalog.device
  static let names = "“iPhone 17” (iOS 26.0)"

  static func checks(_ table: [String: String]) -> [CatalogTextCatalog.Check] {
    let plain: [(String, String)] = [
      ("선택한 기기에 앱 설치", LauncherText.installOnSelectionMenu),
      ("선택한 기기 켜기", LauncherText.bootSelectionButton),
      (
        "목록에서 기기를 고르세요. ⌘ 키를 누른 채 클릭하면 여러 대를, ⇧ 키를 누른 채 클릭하면 사이의 기기를 함께 고릅니다.",
        LauncherText.selectionGuide
      ),
      (
        "고른 기기 중 앱을 설치할 수 있는 기기가 없습니다. 사용할 수 없거나, 켜거나 끄는 중이거나, 다른 작업 중입니다.",
        LauncherText.installOnSelectionUnavailable
      ),
      ("고른 기기 중 꺼진 기기를 함께 켭니다.", LauncherText.bootSelectionHelp),
      ("고른 기기 중 켤 수 있는 꺼진 기기가 없습니다.", LauncherText.bootSelectionUnavailable),
      (
        "이 기기에서 다른 작업이 진행 중이라 설치하지 않았습니다. 끝난 뒤 이 기기에만 다시 설치하세요.",
        LauncherText.message(for: AppInstallFailure.deviceBusy)
      ),
    ]
    var checks = plain.map { CatalogTextCatalog.check(table, $0.0, $0.1) }
    checks += self.countChecks(table)
    checks += self.lineChecks(table)
    return checks
  }

  /// 대수가 들어가는 키 (툴팁·시트·제목).
  private static func countChecks(_ table: [String: String]) -> [CatalogTextCatalog.Check] {
    let two = [
      TargetDevice(id: VirtualDevice.ID("A"), label: self.device), TargetDevice(
        id: VirtualDevice.ID("B"),
        label: self.device
      ),
    ]
    let partial = BatchTextTests.report(.install, [(self.device, .succeeded), (self.device, .deviceBusyResult)])
    let bootPartial = BatchTextTests.report(
      .boot,
      [(self.device, .succeeded), (self.device, .bootFailed(.commandFailed))]
    )
    let bootFailed = BatchTextTests.report(.boot, [(self.device, .bootFailed(.commandFailed))])
    return [
      CatalogTextCatalog.check(
        table,
        "고른 기기 %lld대에 앱을 설치하고 실행합니다. 설치할 수 없는 기기는 이유와 함께 건너뜁니다.",
        LauncherText.installOnSelectionHelp(count: 3),
        3
      ),
      CatalogTextCatalog.check(table, "기기 %lld대에 URL 에서 앱 설치", LauncherText.installURLSheetTitle(for: two), 2),
      CatalogTextCatalog.check(table, "기기 %lld대에 카탈로그에서 앱 설치", LauncherText.catalogSheetTitle(for: two), 2),
      CatalogTextCatalog.check(
        table,
        "대상: %@",
        LauncherText.batchTargetsLine(two) ?? "",
        "\(self.names), \(self.names)"
      ),
      CatalogTextCatalog.check(
        table,
        "기기 %lld대에 함께 받는 중입니다. 취소하면 모두 멈추고 받은 부분을 지웁니다.",
        LauncherText.batchCancelDownloadHelp(count: 2),
        2
      ),
      CatalogTextCatalog.check(
        table, "기기 %lld대 중 %lld대에 앱을 설치했습니다", LauncherText.title(for: .batchFinished(partial)), 2, 1
      ),
      CatalogTextCatalog.check(
        table,
        "기기 %lld대에 앱을 설치하지 못했습니다",
        LauncherText.title(for: .batchInstallFailed([self.device, self.device], .multipleItems)),
        2
      ),
      CatalogTextCatalog.check(
        table, "기기 %lld대 중 %lld대를 켰습니다", LauncherText.title(for: .batchFinished(bootPartial)), 2, 1
      ),
      CatalogTextCatalog.check(
        table, "기기 %lld대를 켜지 못했습니다", LauncherText.title(for: .batchFinished(bootFailed)), 1
      ),
    ]
  }

  /// 결과 줄 키 (기기 한 대짜리 결과의 본문이 줄 하나다).
  private static func lineChecks(_ table: [String: String]) -> [CatalogTextCatalog.Check] {
    let launch = LauncherText.message(for: SimulatorError.appLaunchFailed)
    let command = LauncherText.message(for: SimulatorError.commandFailed)
    let busy = LauncherText.message(for: AppInstallFailure.deviceBusy)
    var checks = [
      self.line(table, "%@: 설치하고 실행했습니다.", .install, .succeeded, self.names),
      self.line(table, "%@: 설치하지 못했습니다. %@", .install, .deviceBusyResult, self.names, busy),
      self.line(table, "%@: 설치했지만 실행하지 못했습니다. %@", .install, .launchFailed(.appLaunchFailed), self.names, launch),
      self.line(table, "%@: 켜지 못해 설치하지 않았습니다. %@", .install, .bootFailed(.commandFailed), self.names, command),
      self.line(table, "%@: 켰습니다.", .boot, .succeeded, self.names),
      self.line(table, "%@: 켜지 못했습니다. %@", .boot, .bootFailed(.commandFailed), self.names, command),
    ]
    let simulatorApp = LauncherText.message(
      for: .batchFinished(BatchTextTests.report(.install, [], simulatorAppError: .simulatorAppNotFound))
    )
    checks.append(
      CatalogTextCatalog.check(
        table,
        "Simulator 앱을 열지 못했습니다. %@",
        simulatorApp,
        LauncherText.message(for: SimulatorError.simulatorAppNotFound)
      )
    )
    return checks
  }

  /// 기기 한 대짜리 결과의 본문(줄 하나)과 표의 값에 인자를 넣은 것을 비교하는 확인.
  private static func line(
    _ table: [String: String],
    _ key: String,
    _ action: BatchReport.Action,
    _ result: BatchDeviceResult,
    _ arguments: any CVarArg...
  ) -> CatalogTextCatalog.Check {
    let report = BatchTextTests.report(action, [(self.device, result)])
    return CatalogTextCatalog.Check(
      key: key,
      expected: String(format: table[key] ?? "", arguments: arguments),
      actual: LauncherText.message(for: .batchFinished(report))
    )
  }

  /// 표에 키가 있고 값이 키와 같으며 코드 결과가 표의 값과 같은지 보고, 키 23개를 돌려준다.
  static func checkedKeys(in table: [String: String]) -> Set<String> {
    let checks = self.checks(table)
    for check in checks {
      #expect(table[check.key] == check.key, "\(check.key)")
      #expect(check.actual == check.expected, "\(check.key)")
    }
    let keys = Set(checks.map(\.key))
    #expect(keys.count == 23)
    return keys
  }
}

/// 여러 기기 문구가 컴파일된 한국어 표에 있다.
struct BatchTextResourceTests {
  @Test("여러 기기 문구 23개가 String Catalog 에서 한국어 값으로 컴파일되고, 코드 결과가 표의 값과 같다")
  func batchTextsAreInCompiledKoreanTable() throws {
    let url = try #require(
      Bundle.module.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "ko")
    )
    let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
    #expect(BatchTextCatalog.checkedKeys(in: table).count == 23)
  }
}
