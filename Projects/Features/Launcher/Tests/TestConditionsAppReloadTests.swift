import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

/// 테스트 조건 시트의 앱 목록 다시 읽기: 읽는 동안 마지막 목록·고른 앱과 권한·푸시를 그대로 두고, 실패하면 지운다.
/// 첫 읽기·끝 상태는 `TestConditionsAppTests`.
@MainActor
struct TestConditionsAppReloadTests: TestConditionsAppTesting {
  private let id = SampleID.iPhoneOn

  private static var newApp: InstalledApp {
    InstalledApp(bundleID: AppBundleID("com.example.new")!, displayName: "New", version: nil, build: nil)
  }

  @Test("다시 읽는 동안 마지막 목록과 고른 앱을 그대로 보이고, 두 번째 다시 읽기는 무시하며, 끝나면 새 목록에서 선택을 지킨다")
  func refreshKeepsListAndSelectionWhileReading() async {
    let loaded = await Self.openedWithSample()
    let conditions = loaded.conditions
    conditions.appSelected(Self.rig.bundleID)
    loaded.simulator.setInstalledApps([Self.sample, Self.rig, Self.newApp], on: self.id)
    loaded.simulator.suspendInstalledApps()
    let refresh = Self.start { await conditions.appsRefreshTapped() }
    await Self.waitUntil { Self.appsReadCount(loaded.simulator) == 2 }

    #expect(conditions.draft?.app.apps == .reloading([Self.sample, Self.rig]))
    #expect(conditions.draft?.app.isReadingApps == true)
    #expect(conditions.draft?.app.loadedApps == [Self.sample, Self.rig])
    #expect(conditions.draft?.app.selectedApp == Self.rig)

    let ignored = Self.start { await conditions.appsRefreshTapped() }
    await Self.waitUntil { ignored.isFinished }
    #expect(Self.appsReadCount(loaded.simulator) == 2)

    loaded.simulator.resumeInstalledApps()
    await refresh.value()
    #expect(conditions.draft?.app.apps == .loaded([Self.sample, Self.rig, Self.newApp]))
    #expect(conditions.draft?.app.isReadingApps == false)
    #expect(conditions.draft?.app.selectedApp == Self.rig)
  }

  @Test("다시 읽는 동안에도 고른 앱으로 권한을 바꾸고 푸시를 보낸다")
  func privacyAndPushWorkWhileReloading() async {
    let loaded = await Self.openedWithSample()
    let conditions = loaded.conditions
    loaded.simulator.suspendInstalledApps()
    let refresh = Self.start { await conditions.appsRefreshTapped() }
    await Self.waitUntil { Self.appsReadCount(loaded.simulator) == 2 }

    await conditions.privacyTapped(.camera, .grant)
    #expect(Self.privacyCalls(loaded.simulator) == [.setPrivacy(.grant, .camera, Self.sample.bundleID, self.id)])
    #expect(conditions.draft?.app.result == .privacyChanged(.camera, .grant, appName: "Sample"))

    conditions.pushBodyChanged("본문")
    await conditions.sendPushTapped()
    #expect(Self.pushCalls(loaded.simulator).count == 1)
    #expect(conditions.draft?.app.result == .pushSent(appName: "Sample"))
    #expect(conditions.draft?.app.isReadingApps == true)

    loaded.simulator.resumeInstalledApps()
    await refresh.value()
    #expect(conditions.draft?.app.selectedApp == Self.sample)
  }

  @Test("다시 읽는 동안 마지막 목록의 앱을 고를 수 있고, 새 목록에 있으면 지키며 없으면 자동 선택 규칙을 따른다")
  func selectingDuringReloadIsKeptIfStillListed() async {
    let loaded = await Self.openedWithSample()
    let conditions = loaded.conditions
    loaded.simulator.setInstalledApps([Self.sample, Self.rig, Self.newApp], on: self.id)
    loaded.simulator.suspendInstalledApps()
    let first = Self.start { await conditions.appsRefreshTapped() }
    await Self.waitUntil { Self.appsReadCount(loaded.simulator) == 2 }

    // 마지막 목록 밖의 앱(새 목록에만 있는 앱)은 받지 않는다.
    conditions.appSelected(Self.newApp.bundleID)
    #expect(conditions.draft?.app.selectedAppID == Self.sample.bundleID)
    conditions.appSelected(Self.rig.bundleID)
    #expect(conditions.draft?.app.selectedApp == Self.rig)
    loaded.simulator.resumeInstalledApps()
    await first.value()
    #expect(conditions.draft?.app.selectedAppID == Self.rig.bundleID)

    // 다시 읽는 동안 고른 Sample 이 새 목록에 없으면: 기억한 앱(Sample)도 없어 앱 하나 규칙으로 Rig.
    loaded.simulator.setInstalledApps([Self.rig], on: self.id)
    loaded.simulator.suspendInstalledApps()
    let second = Self.start { await conditions.appsRefreshTapped() }
    await Self.waitUntil { Self.appsReadCount(loaded.simulator) == 3 }
    conditions.appSelected(Self.sample.bundleID)
    #expect(conditions.draft?.app.selectedApp == Self.sample)
    loaded.simulator.resumeInstalledApps()
    await second.value()
    #expect(conditions.draft?.app.selectedAppID == Self.rig.bundleID)
  }

  @Test("다시 읽기가 실패하면 실패를 보이고 선택을 지우며, 그 뒤 다시 읽기는 처음 읽기처럼 시작해 성공하면 기억한 앱을 다시 고른다")
  func reloadFailureClearsSelectionThenRestoresRemembered() async {
    let loaded = await Self.openedWithSample()
    let conditions = loaded.conditions
    conditions.appSelected(Self.rig.bundleID)
    loaded.simulator.setInstalledAppsError(.commandFailed)
    await conditions.appsRefreshTapped()
    #expect(conditions.draft?.app.apps == .failed(.commandFailed))
    #expect(conditions.draft?.app.selectedAppID == nil)
    #expect(conditions.draft?.app.selectedApp == nil)

    loaded.simulator.setInstalledAppsError(nil)
    loaded.simulator.suspendInstalledApps()
    let retry = Self.start { await conditions.appsRefreshTapped() }
    await Self.waitUntil { Self.appsReadCount(loaded.simulator) == 3 }
    #expect(conditions.draft?.app.apps == .loading)
    #expect(conditions.draft?.app.loadedApps == nil)

    loaded.simulator.resumeInstalledApps()
    await retry.value()
    #expect(conditions.draft?.app.apps == .loaded([Self.sample, Self.rig]))
    #expect(conditions.draft?.app.selectedAppID == Self.rig.bundleID)
  }

  @Test("다시 읽는 중에 닫고 다시 열면 앞 결과를 버리고, 새 시트는 처음 읽기부터 시작한다")
  func reloadResultDroppedAfterReopen() async {
    let loaded = await Self.openedWithSample()
    let conditions = loaded.conditions
    loaded.simulator.suspendInstalledApps()
    let refresh = Self.start { await conditions.appsRefreshTapped() }
    await Self.waitUntil { Self.appsReadCount(loaded.simulator) == 2 }
    conditions.sheetDismissed()

    let reopen = Self.start { await conditions.testConditionsTapped(self.id) }
    await Self.waitUntil { Self.appsReadCount(loaded.simulator) == 3 }
    #expect(conditions.draft?.session == 2)
    #expect(conditions.draft?.app.apps == .loading)
    #expect(conditions.draft?.app.selectedAppID == nil)

    loaded.simulator.setInstalledApps([Self.rig], on: self.id)
    loaded.simulator.resumeInstalledApps()
    await refresh.value()
    await reopen.value()
    #expect(conditions.draft?.session == 2)
    #expect(conditions.draft?.app.apps == .loaded([Self.rig]))
    #expect(conditions.draft?.app.selectedAppID == Self.rig.bundleID)
  }
}
