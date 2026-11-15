import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

/// 앱 단위 구역 테스트가 함께 쓰는 샘플 앱과 도움 함수.
@MainActor
protocol TestConditionsAppTesting: TestConditionsTesting {}

@MainActor
extension TestConditionsAppTesting {
  static var sample: InstalledApp {
    InstalledApp(bundleID: AppBundleID("com.example.sample")!, displayName: "Sample", version: "1.0", build: "1")
  }

  static var rig: InstalledApp {
    InstalledApp(bundleID: AppBundleID("com.example.rig")!, displayName: "Rig", version: nil, build: nil)
  }

  /// 두 앱을 둔 기기 목록·시트를 열고 Sample 을 고른 상태.
  static func openedWithSample(
    _ configure: (SimulatorClientFake) -> Void = { _ in }
  ) async -> ConditionsModels {
    let loaded = await Self.conditionsModels {
      $0.setInstalledApps([Self.sample, Self.rig], on: SampleID.iPhoneOn)
      configure($0)
    }
    await loaded.conditions.testConditionsTapped(SampleID.iPhoneOn)
    loaded.conditions.appSelected(Self.sample.bundleID)
    return loaded
  }

  static func appsReadCount(_ fake: SimulatorClientFake) -> Int {
    fake.calls.count { $0 == .installedApps(SampleID.iPhoneOn) }
  }

  static func privacyCalls(_ fake: SimulatorClientFake) -> [SimulatorClientFake.ConditionCall] {
    self.conditionCalls(fake).filter {
      if case .setPrivacy = $0 {
        true
      } else {
        false
      }
    }
  }

  static func pushCalls(_ fake: SimulatorClientFake) -> [SimulatorClientFake.ConditionCall] {
    self.conditionCalls(fake).filter {
      if case .sendPush = $0 {
        true
      } else {
        false
      }
    }
  }
}

/// 테스트 조건 시트의 앱 단위 구역: 앱 목록 읽기·고르기·다시 읽기. 권한·푸시는 `TestConditionsPrivacyPushTests`.
@MainActor
struct TestConditionsAppTests: TestConditionsAppTesting {
  private let id = SampleID.iPhoneOn

  // MARK: - 앱 목록 읽기

  @Test("열면 화면 설정을 읽은 뒤 설치된 앱 목록을 읽고, 앱이 둘 이상이면 고르지 않는다")
  func opensAndReadsApps() async {
    let loaded = await Self.conditionsModels { $0.setInstalledApps([Self.sample, Self.rig], on: SampleID.iPhoneOn) }
    await loaded.conditions.testConditionsTapped(self.id)

    #expect(loaded.conditions.draft?.app.apps == .loaded([Self.sample, Self.rig]))
    #expect(loaded.conditions.draft?.app.selectedAppID == nil)
    #expect(loaded.conditions.draft?.app.selectedApp == nil)
    #expect(Self.appsReadCount(loaded.simulator) == 1)
  }

  @Test("읽는 동안 앱 구역은 읽는 중이고, 앱이 하나면 그 앱을 고른다")
  func singleAppAutoSelected() async {
    let loaded = await Self.conditionsModels {
      $0.setInstalledApps([Self.sample], on: SampleID.iPhoneOn)
      $0.suspendInstalledApps()
    }
    let tap = Self.start { await loaded.conditions.testConditionsTapped(self.id) }
    await Self.waitUntil { Self.appsReadCount(loaded.simulator) == 1 }
    #expect(loaded.conditions.draft?.app.apps == .loading)

    loaded.simulator.resumeInstalledApps()
    await tap.value()
    #expect(loaded.conditions.draft?.app.selectedApp == Self.sample)
  }

  @Test("설치한 앱이 없으면 빈 목록이고 고른 앱이 없다")
  func emptyList() async {
    let loaded = await Self.conditionsModels()
    await loaded.conditions.testConditionsTapped(self.id)
    #expect(loaded.conditions.draft?.app.apps == .loaded([]))
    #expect(loaded.conditions.draft?.app.selectedAppID == nil)
  }

  @Test("같은 기기에서 마지막으로 고른 앱을 다시 열 때 먼저 고르고, 목록에 없으면 앱 하나 규칙으로 돌아간다")
  func remembersLastSelection() async {
    let loaded = await Self.conditionsModels { $0.setInstalledApps([Self.sample, Self.rig], on: SampleID.iPhoneOn) }
    let conditions = loaded.conditions
    await conditions.testConditionsTapped(self.id)
    conditions.appSelected(Self.rig.bundleID)
    conditions.closeTapped()

    await conditions.testConditionsTapped(self.id)
    #expect(conditions.draft?.app.selectedAppID == Self.rig.bundleID)
    conditions.closeTapped()

    loaded.simulator.setInstalledApps([Self.sample], on: SampleID.iPhoneOn)
    await conditions.testConditionsTapped(self.id)
    #expect(conditions.draft?.app.selectedAppID == Self.sample.bundleID)
  }

  @Test("목록을 읽지 못하면 실패를 보이고, 기기 문제가 아니면 기기 목록을 다시 읽지 않는다")
  func appsReadFailure() async {
    let loaded = await Self.conditionsModels { $0.setInstalledAppsError(.commandFailed) }
    await loaded.conditions.testConditionsTapped(self.id)
    #expect(loaded.conditions.draft?.app.apps == .failed(.commandFailed))
    #expect(Self.fetchCount(loaded.simulator) == 1)
  }

  @Test("목록 읽기가 기기 꺼짐으로 실패하면 기기 목록을 다시 읽는다")
  func appsReadNotBootedRefreshes() async {
    let loaded = await Self.conditionsModels { $0.setInstalledAppsError(.deviceNotBooted) }
    await loaded.conditions.testConditionsTapped(self.id)
    #expect(loaded.conditions.draft?.app.apps == .failed(.deviceNotBooted))
    #expect(Self.fetchCount(loaded.simulator) == 2)
  }

  @Test("화면 설정 읽기가 기기 꺼짐으로 실패하면 앱 목록은 읽지 않고 같은 실패를 보이며, 기기 목록은 한 번만 다시 읽는다")
  func displayNotBootedSkipsApps() async {
    let loaded = await Self.conditionsModels { $0.setDisplaySettingsError(.deviceNotBooted) }
    await loaded.conditions.testConditionsTapped(self.id)
    #expect(loaded.conditions.draft?.app.apps == .failed(.deviceNotBooted))
    #expect(Self.appsReadCount(loaded.simulator) == 0)
    #expect(Self.fetchCount(loaded.simulator) == 2)
  }

  @Test("화면 설정 읽기가 기기 밖 이유로 실패해도 앱 목록은 읽는다")
  func displayOtherFailureStillReadsApps() async {
    let loaded = await Self.conditionsModels { $0.setDisplaySettingsError(.commandFailed) }
    await loaded.conditions.testConditionsTapped(self.id)
    #expect(loaded.conditions.draft?.app.apps == .loaded([]))
  }

  @Test("목록을 읽는 중에 닫으면 늦은 결과를 버리고, 다시 열면 새 시트가 새로 읽는다")
  func lateAppsReadDropped() async {
    let loaded = await Self.conditionsModels {
      $0.setInstalledApps([Self.sample], on: SampleID.iPhoneOn)
      $0.suspendInstalledApps()
    }
    let conditions = loaded.conditions
    let first = Self.start { await conditions.testConditionsTapped(self.id) }
    await Self.waitUntil { Self.appsReadCount(loaded.simulator) == 1 }
    conditions.sheetDismissed()
    let second = Self.start { await conditions.testConditionsTapped(self.id) }
    await Self.waitUntil { Self.appsReadCount(loaded.simulator) == 2 }

    loaded.simulator.resumeInstalledApps()
    await first.value()
    await second.value()
    #expect(conditions.draft?.session == 2)
    #expect(conditions.draft?.app.apps == .loaded([Self.sample]))
  }

  // MARK: - 다시 읽기·고르기

  @Test("앱 목록 다시 읽기는 읽는 중에는 무시하고, 읽은 뒤에는 다시 읽어 고른 앱이 있으면 그대로 둔다")
  func refreshKeepsSelection() async throws {
    let loaded = await Self.conditionsModels {
      $0.setInstalledApps([Self.sample, Self.rig], on: SampleID.iPhoneOn)
      $0.suspendInstalledApps()
    }
    let conditions = loaded.conditions
    let tap = Self.start { await conditions.testConditionsTapped(self.id) }
    await Self.waitUntil { Self.appsReadCount(loaded.simulator) == 1 }
    let ignored = Self.start { await conditions.appsRefreshTapped() }
    await Self.waitUntil { ignored.isFinished }
    #expect(Self.appsReadCount(loaded.simulator) == 1)
    loaded.simulator.resumeInstalledApps()
    await tap.value()

    conditions.appSelected(Self.rig.bundleID)
    let newApp = try InstalledApp(
      bundleID: #require(AppBundleID("com.example.new")),
      displayName: "New",
      version: nil,
      build: nil
    )
    loaded.simulator.setInstalledApps([Self.sample, Self.rig, newApp], on: SampleID.iPhoneOn)
    await conditions.appsRefreshTapped()
    #expect(Self.appsReadCount(loaded.simulator) == 2)
    #expect(conditions.draft?.app.apps == .loaded([Self.sample, Self.rig, newApp]))
    #expect(conditions.draft?.app.selectedAppID == Self.rig.bundleID)
  }

  @Test("다시 읽은 목록에 고른 앱이 없으면 자동 선택 규칙대로 고른다")
  func refreshDropsMissingSelection() async {
    let loaded = await Self.openedWithSample()
    let conditions = loaded.conditions
    loaded.simulator.setInstalledApps([Self.rig], on: SampleID.iPhoneOn)
    await conditions.appsRefreshTapped()
    // 기억한 앱(Sample)도 목록에 없어 앱 하나 규칙으로 Rig.
    #expect(conditions.draft?.app.selectedAppID == Self.rig.bundleID)

    loaded.simulator.setInstalledApps([], on: SampleID.iPhoneOn)
    await conditions.appsRefreshTapped()
    #expect(conditions.draft?.app.selectedAppID == nil)
  }

  @Test("읽기 실패 뒤 다시 읽기로 목록을 보이고, 시트가 없으면 다시 읽기는 아무것도 하지 않는다")
  func refreshAfterFailure() async {
    let loaded = await Self.conditionsModels {
      $0.setInstalledApps([Self.sample], on: SampleID.iPhoneOn)
      $0.setInstalledAppsError(.commandFailed)
    }
    await loaded.conditions.appsRefreshTapped()
    #expect(Self.appsReadCount(loaded.simulator) == 0)

    await loaded.conditions.testConditionsTapped(self.id)
    loaded.simulator.setInstalledAppsError(nil)
    await loaded.conditions.appsRefreshTapped()
    #expect(loaded.conditions.draft?.app.apps == .loaded([Self.sample]))
    #expect(loaded.conditions.draft?.app.selectedAppID == Self.sample.bundleID)
  }

  @Test("목록 밖의 앱은 고르지 않고, nil 로 고른 것을 지운다")
  func appSelection() async {
    let loaded = await Self.openedWithSample()
    let conditions = loaded.conditions
    #expect(conditions.draft?.app.selectedApp == Self.sample)

    conditions.appSelected(AppBundleID("com.example.missing"))
    #expect(conditions.draft?.app.selectedAppID == Self.sample.bundleID)

    conditions.appSelected(nil)
    #expect(conditions.draft?.app.selectedAppID == nil)
  }
}
