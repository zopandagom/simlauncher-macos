import AppBundleTesting
import AppLogTesting
import Core
import DownloadTesting
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing
import WorkspaceTesting
@testable import LauncherFeature

/// `installedAppsModels` 가 돌려주는 기기 목록 Model·앱 시트 Model 들·Fake 묶음.
struct InstalledAppsModels {
  let model: LauncherModel
  let sheets: LauncherAppSheetsModel
  let conditions: TestConditionsModel
  let installed: InstalledAppsModel
  let simulator: SimulatorClientFake
}

/// 기기 목록 Model 이 뒤에 만든 시트 Model 들을 읽게 넘기는 상자 (App 의 `LauncherAppSheetsBox` 와 같다).
@MainActor
final class InstalledAppsSheetsBox {
  weak var sheets: LauncherAppSheetsModel?
  weak var conditions: TestConditionsModel?
  weak var installed: InstalledAppsModel?

  var hasPresentedSheet: Bool {
    (self.sheets?.hasPresentedSheet ?? false) || (self.conditions?.hasPresentedSheet ?? false)
      || (self.installed?.hasPresentedSheet ?? false)
  }
}

/// 설치된 앱 시트 테스트가 함께 쓰는 도움 함수. App 처럼 네 Model 을 잇는다.
@MainActor
protocol InstalledAppsTesting: LauncherModelTesting {}

@MainActor
extension InstalledAppsTesting {
  static var sample: InstalledApp {
    InstalledApp(bundleID: AppBundleID("com.example.sample")!, displayName: "Sample", version: "1.0", build: "1")
  }

  static var rig: InstalledApp {
    InstalledApp(bundleID: AppBundleID("com.example.rig")!, displayName: "Rig", version: nil, build: nil)
  }

  /// 샘플 목록을 읽은 기기 목록 Model 에 앱 실행·링크 열기, 테스트 조건, 설치된 앱 시트 Model 을 App 처럼 잇는다. 켜진 iPhone 에는
  /// 기본으로 Sample·Rig 두 앱이 있다 (`configure` 가 바꾼다).
  static func installedAppsModels(
    _ configure: (SimulatorClientFake) -> Void = { _ in }
  ) async -> InstalledAppsModels {
    let fake = SimulatorClientFake(inventory: .sample)
    fake.setInstalledApps([Self.sample, Self.rig], on: SampleID.iPhoneOn)
    configure(fake)
    let box = InstalledAppsSheetsBox()
    let model = LauncherModel(
      simulator: fake,
      appBundle: AppBundleClientFake(),
      download: DownloadClientFake(),
      workspace: WorkspaceClientFake(),
      appLog: AppLogClientFake.forwarding(to: fake),
      appSheetPresented: { box.hasPresentedSheet }
    )
    let sheets = Self.appSheets(simulator: fake, launcher: model)
    let conditions = TestConditionsModel(simulator: fake, target: { model.testConditionsTarget($0) })
    let installed = InstalledAppsModel(
      simulator: fake,
      target: { model.installedAppsTarget($0) },
      refreshRequested: { await model.refreshButtonTapped() }
    )
    box.sheets = sheets
    box.conditions = conditions
    box.installed = installed
    await model.onAppear()
    return InstalledAppsModels(
      model: model,
      sheets: sheets,
      conditions: conditions,
      installed: installed,
      simulator: fake
    )
  }

  /// 켜진 iPhone 의 시트를 열어 목록을 읽은 상태.
  static func opened(_ configure: (SimulatorClientFake) -> Void = { _ in }) async -> InstalledAppsModels {
    let loaded = await Self.installedAppsModels(configure)
    await loaded.installed.installedAppsTapped(SampleID.iPhoneOn)
    return loaded
  }

  static func appsReadCount(_ fake: SimulatorClientFake) -> Int {
    fake.calls.count { $0 == .installedApps(SampleID.iPhoneOn) }
  }

  static func uninstallCalls(_ fake: SimulatorClientFake) -> [SimulatorClientFake.Call] {
    fake.calls.filter {
      if case .uninstall = $0 {
        true
      } else {
        false
      }
    }
  }

  static func fetchCount(_ fake: SimulatorClientFake) -> Int {
    fake.calls.count { $0 == .fetchInventory }
  }
}

/// 설치된 앱 시트 (`InstalledAppsModel`): 열기·목록 읽기·다시 읽기·고르기·삭제 확인·실패·겹침.
@MainActor
struct InstalledAppsModelTests: InstalledAppsTesting {
  private let id = SampleID.iPhoneOn

  // MARK: - 열기·읽기

  @Test("꺼진 기기·없는 기기는 시트를 열지 않고 명령도 없다")
  func noTargetDoesNothing() async {
    let loaded = await Self.installedAppsModels()
    await loaded.installed.installedAppsTapped(SampleID.iPhoneOff)
    await loaded.installed.installedAppsTapped(VirtualDevice.ID("missing"))
    #expect(loaded.installed.draft == nil)
    #expect(loaded.simulator.calls == [.fetchInventory])
  }

  @Test("누르자마자 첫 await 전에 읽는 중으로 열고, 읽으면 목록을 보이며 앱이 둘 이상이면 고르지 않는다")
  func opensBeforeFirstAwait() async {
    let loaded = await Self.installedAppsModels { $0.suspendInstalledApps() }
    let installed = loaded.installed
    let tap = Self.start { await installed.installedAppsTapped(self.id) }
    await Self.waitUntil { Self.appsReadCount(loaded.simulator) == 1 }

    #expect(installed.draft?.deviceID == self.id)
    #expect(installed.draft?.device == Self.label(self.id))
    #expect(installed.draft?.apps == .loading)
    #expect(installed.hasPresentedSheet)
    #expect(loaded.model.isSheetOrDialogOpen)
    #expect(!loaded.model.canCreateDevice)

    loaded.simulator.resumeInstalledApps()
    await tap.value()
    #expect(installed.draft?.apps == .loaded([Self.sample, Self.rig]))
    #expect(installed.draft?.selection == nil)
  }

  @Test("앱이 하나면 그 앱을 고르고, 없으면 빈 목록이다")
  func singleAndEmpty() async {
    let single = await Self.opened { $0.setInstalledApps([Self.sample], on: SampleID.iPhoneOn) }
    #expect(single.installed.draft?.selectedApp == Self.sample)

    let empty = await Self.opened { $0.setInstalledApps([], on: SampleID.iPhoneOn) }
    #expect(empty.installed.draft?.apps == .loaded([]))
    #expect(empty.installed.draft?.selection == nil)
  }

  @Test("시트가 열려 있으면 다시 누르거나 다른 기기를 눌러도 열지 않는다")
  func secondOpenIgnored() async {
    let loaded = await Self.opened()
    await loaded.installed.installedAppsTapped(self.id)
    #expect(Self.appsReadCount(loaded.simulator) == 1)
    #expect(loaded.installed.draft?.session == 1)
  }

  @Test("목록을 읽지 못하면 실패를 보이고, 기기 문제가 아니면 기기 목록을 다시 읽지 않으며, 다시 읽기로 다시 읽는다")
  func readFailureThenRetry() async {
    let loaded = await Self.opened { $0.setInstalledAppsError(.commandFailed) }
    #expect(loaded.installed.draft?.apps == .failed(.commandFailed))
    #expect(Self.fetchCount(loaded.simulator) == 1)

    loaded.simulator.setInstalledAppsError(nil)
    await loaded.installed.refreshTapped()
    #expect(loaded.installed.draft?.apps == .loaded([Self.sample, Self.rig]))
  }

  @Test("목록 읽기가 기기 꺼짐·없어짐으로 실패하면 기기 목록을 다시 읽는다 (알림은 쌓지 않는다)")
  func readNotBootedRefreshes() async {
    for error in [SimulatorError.deviceNotBooted, .deviceNotFound] {
      let loaded = await Self.opened { $0.setInstalledAppsError(error) }
      #expect(loaded.installed.draft?.apps == .failed(error))
      #expect(Self.fetchCount(loaded.simulator) == 2)
      #expect(loaded.model.notices.isEmpty)
    }
  }

  @Test("다시 읽는 동안 마지막 목록과 선택을 그대로 보이고, 고른 앱이 새 목록에 있으면 그대로 둔다")
  func reloadKeepsListAndSelection() async {
    let loaded = await Self.opened()
    let installed = loaded.installed
    installed.selectionChanged(Self.rig.bundleID)
    loaded.simulator.suspendInstalledApps()
    let refresh = Self.start { await installed.refreshTapped() }
    await Self.waitUntil { Self.appsReadCount(loaded.simulator) == 2 }

    #expect(installed.draft?.apps == .reloading([Self.sample, Self.rig]))
    #expect(installed.draft?.selectedApp == Self.rig)
    #expect(installed.draft?.canRefresh == false)
    #expect(installed.draft?.canRequestAction == false)
    // 읽는 동안 다시 읽기는 무시한다.
    await installed.refreshTapped()
    #expect(Self.appsReadCount(loaded.simulator) == 2)

    loaded.simulator.resumeInstalledApps()
    await refresh.value()
    #expect(installed.draft?.apps == .loaded([Self.sample, Self.rig]))
    #expect(installed.draft?.selection == Self.rig.bundleID)
  }

  @Test("읽는 중에 닫고 다시 열면 앞 결과를 버리고 새 번호의 시트가 결과를 받는다")
  func closeAndReopenDiscardsOldRead() async {
    let loaded = await Self.installedAppsModels { $0.suspendInstalledApps() }
    let installed = loaded.installed
    let first = Self.start { await installed.installedAppsTapped(self.id) }
    await Self.waitUntil { Self.appsReadCount(loaded.simulator) == 1 }
    installed.closeTapped()
    #expect(installed.draft == nil)

    let second = Self.start { await installed.installedAppsTapped(self.id) }
    await Self.waitUntil { Self.appsReadCount(loaded.simulator) == 2 }
    #expect(installed.draft?.session == 2)
    loaded.simulator.setInstalledApps([Self.sample], on: SampleID.iPhoneOn)
    loaded.simulator.resumeInstalledApps()
    await first.value()
    await second.value()
    #expect(installed.draft?.session == 2)
    #expect(installed.draft?.apps == .loaded([Self.sample]))
  }

  @Test("읽는 중에 시스템이 닫으면 결과는 버려지고 시트는 닫힌 채다")
  func lateReadAfterDismissIsDropped() async {
    let loaded = await Self.installedAppsModels { $0.suspendInstalledApps() }
    let tap = Self.start { await loaded.installed.installedAppsTapped(self.id) }
    await Self.waitUntil { Self.appsReadCount(loaded.simulator) == 1 }
    loaded.installed.sheetDismissed()
    loaded.simulator.resumeInstalledApps()
    await tap.value()
    #expect(loaded.installed.draft == nil)
  }

  // MARK: - 고르기

  @Test("목록에 있는 앱과 nil 만 고를 수 있다")
  func selection() async {
    let loaded = await Self.opened()
    let installed = loaded.installed
    installed.selectionChanged(Self.sample.bundleID)
    #expect(installed.draft?.selectedApp == Self.sample)
    installed.selectionChanged(AppBundleID("com.example.missing"))
    #expect(installed.draft?.selection == Self.sample.bundleID)
    installed.selectionChanged(nil)
    #expect(installed.draft?.selection == nil)
  }
}
