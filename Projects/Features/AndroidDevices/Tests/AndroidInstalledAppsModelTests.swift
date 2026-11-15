import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Foundation
import Testing
@testable import AndroidDevicesFeature

/// 설치된 앱 시트 테스트가 함께 쓰는 샘플 패키지와 도움 함수.
@MainActor
protocol AndroidInstalledAppsTesting: AndroidDevicesTesting {}

@MainActor
extension AndroidInstalledAppsTesting {
  static var sample: AndroidPackageName {
    AndroidPackageName("com.example.sample")!
  }

  static var shop: AndroidPackageName {
    AndroidPackageName("org.example.shop")!
  }

  static var tabletID: AndroidVirtualDevice.ID {
    AndroidVirtualDevice.bootedTabletSample.id
  }

  /// 두 패키지를 둔 Fake 로 켜진 태블릿의 시트를 열어 목록을 읽은 상태.
  static func opened(_ configure: (AndroidEmulatorClientFake) -> Void = { _ in }) async -> AndroidDevicesFixture {
    let setup = await Self.loadedFixture {
      $0.setInstalledPackages(.success([Self.sample, Self.shop]))
      configure($0)
    }
    await setup.installedApps.installedAppsTapped(Self.tabletID)
    return setup
  }

  /// 시트를 열고 com.example.sample 을 골라 "삭제…" 로 확인을 기다리는 상태.
  static func pendingSample(_ configure: (AndroidEmulatorClientFake) -> Void = { _ in
  }) async -> AndroidDevicesFixture {
    let setup = await Self.opened(configure)
    setup.installedApps.selectionChanged(Self.sample)
    setup.installedApps.removeTapped()
    return setup
  }

  static func packagesReadCount(_ fake: AndroidEmulatorClientFake) -> Int {
    count(.installedPackages(self.tabletID), in: fake)
  }

  static func uninstallCalls(_ fake: AndroidEmulatorClientFake) -> [AndroidEmulatorClientFake.AppManagementCall] {
    fake.calls.compactMap {
      if case let .appManagement(call) = $0 {
        call
      } else {
        nil
      }
    }
  }
}

/// 행 "설치된 앱…" 시트 (`AndroidInstalledAppsModel`): 열기·목록 읽기·다시 읽기·고르기와 열기 조건. 삭제는
/// `AndroidInstalledAppsRemoveTests`.
@MainActor
struct AndroidInstalledAppsModelTests: AndroidInstalledAppsTesting {
  private var id: AndroidVirtualDevice.ID {
    Self.tabletID
  }

  @Test("꺼진 기기·없는 기기는 열지 않고, 켜진 기기는 첫 await 전에 읽는 중으로 열어 목록을 보인다")
  func opensAndReads() async {
    let setup = await Self.loadedFixture {
      $0.setInstalledPackages(.success([Self.sample, Self.shop]))
      $0.suspendPackageLists()
    }
    let installed = setup.installedApps
    await installed.installedAppsTapped(AndroidVirtualDevice.phoneSample.id)
    await installed.installedAppsTapped(AndroidVirtualDevice.ID("Gone"))
    #expect(installed.draft == nil)

    let tap = Self.start { await installed.installedAppsTapped(self.id) }
    await Self.waitUntil { Self.packagesReadCount(setup.fake) == 1 }
    #expect(installed.draft?.packages == .loading)
    #expect(installed.draft?.device == AndroidDeviceLabel(.bootedTabletSample))
    #expect(setup.model.hasPresentedSheet)
    #expect(!setup.model.canCreateDevice)

    setup.fake.resumePackageLists()
    await tap.value()
    #expect(installed.draft?.packages == .loaded([Self.sample, Self.shop]))
    #expect(installed.draft?.selection == nil)
  }

  @Test("패키지가 하나면 고르고, 시트가 열려 있으면 다시 눌러도 열지 않는다")
  func singleAutoSelectedAndSecondOpenIgnored() async {
    let setup = await Self.opened { $0.setInstalledPackages(.success([Self.sample])) }
    #expect(setup.installedApps.draft?.selectedPackage == Self.sample)
    await setup.installedApps.installedAppsTapped(self.id)
    #expect(Self.packagesReadCount(setup.fake) == 1)
    #expect(setup.installedApps.draft?.session == 1)
  }

  @Test("읽기 실패를 보이고 adb 문제면 기기 목록을 다시 읽지 않으며, 다시 읽기로 다시 읽는다")
  func readFailureThenRetry() async {
    let setup = await Self.opened { $0.setInstalledPackages(.failure(.adbUnavailable)) }
    #expect(setup.installedApps.draft?.packages == .failed(.adbUnavailable))
    #expect(Self.fetchCount(setup.fake) == 1)

    setup.fake.setInstalledPackages(.success([Self.shop]))
    await setup.installedApps.refreshTapped()
    #expect(setup.installedApps.draft?.packages == .loaded([Self.shop]))
    #expect(setup.installedApps.draft?.selection == Self.shop)
  }

  @Test("읽기가 기기 꺼짐으로 실패하면 기기 목록을 다시 읽는다")
  func readNotBootedRefreshes() async {
    let setup = await Self.opened { $0.setInstalledPackages(.failure(.deviceNotBooted)) }
    #expect(setup.installedApps.draft?.packages == .failed(.deviceNotBooted))
    #expect(Self.fetchCount(setup.fake) == 2)
  }

  @Test("다시 읽는 동안 마지막 목록과 선택을 그대로 보이고 쓰기·다시 읽기를 받지 않으며, 끝나면 선택을 유지한다")
  func reloadKeepsListAndSelection() async {
    let setup = await Self.opened()
    let installed = setup.installedApps
    installed.selectionChanged(Self.shop)
    setup.fake.suspendPackageLists()
    let refresh = Self.start { await installed.refreshTapped() }
    await Self.waitUntil { Self.packagesReadCount(setup.fake) == 2 }

    #expect(installed.draft?.packages == .reloading([Self.sample, Self.shop]))
    #expect(installed.draft?.selectedPackage == Self.shop)
    #expect(installed.draft?.canRequestAction == false)
    installed.removeTapped()
    #expect(installed.draft?.pendingAction == nil)
    await installed.refreshTapped()
    #expect(Self.packagesReadCount(setup.fake) == 2)

    setup.fake.resumePackageLists()
    await refresh.value()
    #expect(installed.draft?.packages == .loaded([Self.sample, Self.shop]))
    #expect(installed.draft?.selection == Self.shop)
  }

  @Test("읽는 중에 닫고 다시 열면 앞 결과를 버리고, 시스템이 닫은 뒤 온 결과도 버린다")
  func closeAndReopenDiscardsOldRead() async {
    let setup = await Self.loadedFixture { $0.suspendPackageLists() }
    let installed = setup.installedApps
    let first = Self.start { await installed.installedAppsTapped(self.id) }
    await Self.waitUntil { Self.packagesReadCount(setup.fake) == 1 }
    installed.closeTapped()
    #expect(installed.draft == nil)

    let second = Self.start { await installed.installedAppsTapped(self.id) }
    await Self.waitUntil { Self.packagesReadCount(setup.fake) == 2 }
    #expect(installed.draft?.session == 2)
    installed.sheetDismissed()
    setup.fake.resumePackageLists()
    await first.value()
    await second.value()
    #expect(installed.draft == nil)
  }

  @Test("목록에 있는 패키지와 nil 만 고를 수 있다")
  func selection() async {
    let setup = await Self.opened()
    let installed = setup.installedApps
    installed.selectionChanged(Self.sample)
    #expect(installed.draft?.selectedPackage == Self.sample)
    installed.selectionChanged(AndroidPackageName("com.example.missing"))
    #expect(installed.draft?.selection == Self.sample)
    installed.selectionChanged(nil)
    #expect(installed.draft?.selection == nil)
  }

  // MARK: - 열기 조건

  @Test("열기: 켜지고 쓸 수 있는 기기이고 진행 작업이 하나도 없을 때만 연다")
  func canOpenTable() {
    let booted = AndroidVirtualDevice.bootedTabletSample
    #expect(AndroidInstalledAppsAvailability.canOpen(device: booted, during: nil))
    #expect(!AndroidInstalledAppsAvailability.canOpen(device: .phoneSample, during: nil))
    #expect(!AndroidInstalledAppsAvailability.canOpen(device: .unsupportedNameSample, during: nil))
    #expect(!AndroidInstalledAppsAvailability.canOpen(device: .bootingSample, during: nil))
    let tasks: [AndroidDeviceTask] = [.installApp, .launchApp, .openURL, .boot, .shutdown, .delete, .erase]
    for task in tasks {
      #expect(!AndroidInstalledAppsAvailability.canOpen(device: booted, during: task), "\(task)")
    }
  }

  @Test("열 기기: 앱 실행·링크 열기·테스트 조건·만들기 시트, 확인 대화상자가 있으면 없고, 설치된 앱 시트가 있으면 만들기를 열지 않는다")
  func targetBlockedByOtherSheets() async {
    let setup = await Self.loadedFixture()
    let model = setup.model
    #expect(model.installedAppsTarget(self.id)?.id == self.id)
    #expect(model.installedAppsTarget(AndroidVirtualDevice.phoneSample.id) == nil)

    setup.sheets.openURLTapped(self.id)
    #expect(model.installedAppsTarget(self.id) == nil)
    setup.sheets.openURLSheetDismissed()

    await setup.conditions.testConditionsTapped(self.id)
    #expect(model.installedAppsTarget(self.id) == nil)
    setup.conditions.closeTapped()

    model.createButtonTapped()
    #expect(model.installedAppsTarget(self.id) == nil)
    model.creationSheetDismissed()

    model.eraseTapped(AndroidVirtualDevice.phoneSample.id)
    #expect(model.installedAppsTarget(self.id) == nil)
    model.confirmationCancelled()
    #expect(model.installedAppsTarget(self.id)?.id == self.id)

    await setup.installedApps.installedAppsTapped(self.id)
    model.createButtonTapped()
    #expect(model.creationDraft == nil)
    #expect(model.testConditionsTarget(self.id) == nil)
  }

  @Test("열 기기: 목록을 읽기 전이면 없고, 그 기기에 진행 작업(설치)이 있으면 없다")
  func targetBlockedByListAndTask() async {
    let unloaded = Self.fixture()
    #expect(unloaded.model.installedAppsTarget(self.id) == nil)

    let setup = await Self.loadedFixture()
    setup.package.suspend()
    let apk = URL(filePath: "/Users/me/Downloads/app.apk", directoryHint: .notDirectory)
    let install = Self.start { await setup.model.appFileSelected(apk, for: self.id) }
    await Self.waitUntil { setup.model.activity.task(on: self.id) == .installApp }
    #expect(setup.model.installedAppsTarget(self.id) == nil)
    await setup.installedApps.installedAppsTapped(self.id)
    #expect(setup.installedApps.draft == nil)
    setup.package.resume()
    await install.value()
  }
}
