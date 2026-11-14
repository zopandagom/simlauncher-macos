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

/// `conditionsModels` 가 돌려주는 기기 목록 Model·앱 실행/링크 열기 시트 Model·테스트 조건 Model·Fake 묶음.
struct ConditionsModels {
  let model: LauncherModel
  let sheets: LauncherAppSheetsModel
  let conditions: TestConditionsModel
  let simulator: SimulatorClientFake
}

/// 테스트 조건 테스트가 함께 쓰는 도움 함수. App 처럼 세 Model 을 잇는다.
@MainActor
protocol TestConditionsTesting: LauncherModelTesting {}

@MainActor
extension TestConditionsTesting {
  /// 보낸 위치에 기록되는 고정 시각.
  static var fixedNow: Date {
    Date(timeIntervalSince1970: 1_800_000_000)
  }

  /// 샘플 목록을 읽은 기기 목록 Model 에 앱 시트·테스트 조건 Model 을 App 처럼 잇는다 (기기 목록의 `appSheetPresented` 는 두 시트를
  /// OR 로 보고, 테스트 조건 시트를 열 기기·다시 읽기는 기기 목록에 묻는다).
  static func conditionsModels(_ configure: (SimulatorClientFake) -> Void = { _ in }) async -> ConditionsModels {
    let fake = SimulatorClientFake(inventory: .sample)
    configure(fake)
    let box = ConditionsSheetsBox()
    let model = LauncherModel(
      simulator: fake,
      appBundle: AppBundleClientFake(),
      download: DownloadClientFake(),
      workspace: WorkspaceClientFake(),
      appLog: AppLogClientFake.forwarding(to: fake),
      appSheetPresented: { box.hasPresentedSheet }
    )
    let sheets = Self.appSheets(simulator: fake, launcher: model)
    let now = Self.fixedNow
    let conditions = TestConditionsModel(
      simulator: fake,
      target: { model.testConditionsTarget($0) },
      refreshRequested: { await model.refreshButtonTapped() },
      now: { now }
    )
    box.sheets = sheets
    box.conditions = conditions
    await model.onAppear()
    return ConditionsModels(model: model, sheets: sheets, conditions: conditions, simulator: fake)
  }

  static func fetchCount(_ fake: SimulatorClientFake) -> Int {
    fake.calls.filter { $0 == .fetchInventory }.count
  }

  static func conditionCalls(_ fake: SimulatorClientFake) -> [SimulatorClientFake.ConditionCall] {
    fake.calls.compactMap {
      if case let .testCondition(call) = $0 {
        call
      } else {
        nil
      }
    }
  }

  static func readCount(_ fake: SimulatorClientFake) -> Int {
    self.conditionCalls(fake).filter {
      if case .displaySettings = $0 {
        true
      } else {
        false
      }
    }.count
  }
}

/// 기기 목록 Model 이 뒤에 만든 시트 Model 들을 읽게 넘기는 상자 (App 의 `LauncherAppSheetsBox` 와 같다).
@MainActor
final class ConditionsSheetsBox {
  weak var sheets: LauncherAppSheetsModel?
  weak var conditions: TestConditionsModel?

  var hasPresentedSheet: Bool {
    (self.sheets?.hasPresentedSheet ?? false) || (self.conditions?.hasPresentedSheet ?? false)
  }
}

/// 테스트 조건 시트: 열기·읽기·화면 설정 적용·겹침. 위치는 `TestConditionsLocationTests`.
@MainActor
struct TestConditionsModelTests: TestConditionsTesting {
  private let id = SampleID.iPhoneOn

  // MARK: - 열기

  @Test("꺼진 기기·없는 기기는 시트를 열지 않고 명령도 없다")
  func noTargetDoesNothing() async {
    let loaded = await Self.conditionsModels()
    await loaded.conditions.testConditionsTapped(SampleID.iPhoneOff)
    await loaded.conditions.testConditionsTapped(VirtualDevice.ID("missing"))

    #expect(loaded.conditions.draft == nil)
    #expect(loaded.simulator.calls == [.fetchInventory])
  }

  @Test("누르자마자 첫 await 전에 읽는 중으로 열고, 읽으면 지금 값을 보인다")
  func opensBeforeFirstAwait() async {
    let loaded = await Self.conditionsModels { $0.suspendConditions() }
    let conditions = loaded.conditions
    let tap = Self.start { await conditions.testConditionsTapped(self.id) }
    await Self.waitUntil { loaded.simulator.calls.contains(.testCondition(.displaySettings(self.id))) }

    #expect(conditions.draft?.deviceID == self.id)
    #expect(conditions.draft?.device == Self.label(self.id))
    #expect(conditions.draft?.display == .loading)
    #expect(conditions.hasPresentedSheet)
    #expect(!loaded.model.canCreateDevice)
    #expect(loaded.model.isSheetOrDialogOpen)

    loaded.simulator.resumeConditions()
    await tap.value()
    #expect(conditions.draft?.display == .loaded(SimulatorClientFake.defaultDisplaySettings))
  }

  @Test("읽기가 실패하면 실패를 보이고, 기기 문제가 아니면 목록을 다시 읽지 않으며, 다시 읽기로 다시 읽는다")
  func readFailureThenRetry() async {
    let loaded = await Self.conditionsModels { $0.setDisplaySettingsError(.commandFailed) }
    let conditions = loaded.conditions
    await conditions.testConditionsTapped(self.id)

    #expect(conditions.draft?.display == .failed(.commandFailed))
    #expect(Self.fetchCount(loaded.simulator) == 1)

    loaded.simulator.setDisplaySettingsError(nil)
    await conditions.displayRetryTapped()
    #expect(conditions.draft?.display == .loaded(SimulatorClientFake.defaultDisplaySettings))
    #expect(Self.readCount(loaded.simulator) == 2)
  }

  @Test("기기가 꺼져 읽지 못하면 실패를 보이고 기기 목록을 한 번 다시 읽는다 (알림은 쌓지 않는다)")
  func readNotBootedRefreshes() async {
    let loaded = await Self.conditionsModels { $0.setDisplaySettingsError(.deviceNotBooted) }
    await loaded.conditions.testConditionsTapped(self.id)

    #expect(loaded.conditions.draft?.display == .failed(.deviceNotBooted))
    #expect(Self.fetchCount(loaded.simulator) == 2)
    #expect(loaded.model.notices.isEmpty)
  }

  @Test("다시 읽기는 읽기 실패 상태에서만 한다")
  func retryOnlyWhenFailed() async {
    let loaded = await Self.conditionsModels()
    await loaded.conditions.displayRetryTapped()
    await loaded.conditions.testConditionsTapped(self.id)
    await loaded.conditions.displayRetryTapped()
    #expect(Self.readCount(loaded.simulator) == 1)
  }

  @Test("읽는 중에 닫으면 늦게 온 결과를 버리고, 닫고 다시 열면 새 번호의 시트가 결과를 받는다")
  func closeAndReopenDiscardsOldRead() async {
    let loaded = await Self.conditionsModels { $0.suspendConditions() }
    let conditions = loaded.conditions
    let first = Self.start { await conditions.testConditionsTapped(self.id) }
    await Self.waitUntil { Self.readCount(loaded.simulator) == 1 }
    conditions.closeTapped()
    #expect(conditions.draft == nil)
    #expect(!conditions.hasPresentedSheet)

    let second = Self.start { await conditions.testConditionsTapped(self.id) }
    await Self.waitUntil { Self.readCount(loaded.simulator) == 2 }
    #expect(conditions.draft?.session == 2)
    #expect(conditions.draft?.display == .loading)

    loaded.simulator.resumeConditions()
    await first.value()
    await second.value()
    #expect(conditions.draft?.session == 2)
    #expect(conditions.draft?.display == .loaded(SimulatorClientFake.defaultDisplaySettings))
  }

  @Test("읽는 중에 닫고 다시 열지 않으면 결과는 버려지고 시트는 닫힌 채다")
  func lateReadAfterDismissIsDropped() async {
    let loaded = await Self.conditionsModels { $0.suspendConditions() }
    let conditions = loaded.conditions
    let tap = Self.start { await conditions.testConditionsTapped(self.id) }
    await Self.waitUntil { Self.readCount(loaded.simulator) == 1 }
    conditions.sheetDismissed()
    loaded.simulator.resumeConditions()
    await tap.value()
    #expect(conditions.draft == nil)
  }

  @Test("시트가 열려 있으면 다시 누르거나 다른 기기를 눌러도 열지 않는다")
  func secondOpenIgnored() async {
    let loaded = await Self.conditionsModels()
    await loaded.conditions.testConditionsTapped(self.id)
    await loaded.conditions.testConditionsTapped(self.id)
    #expect(Self.readCount(loaded.simulator) == 1)
  }

  // MARK: - 화면 설정 적용

  @Test("외관을 고르면 첫 await 전에 적용 중이 되고, 연타는 무시되며, 끝나면 값이 바뀌고 적용 중이 풀린다")
  func appearanceApplies() async {
    let loaded = await Self.conditionsModels()
    let conditions = loaded.conditions
    await conditions.testConditionsTapped(self.id)
    loaded.simulator.suspendConditions()

    let first = Self.start { await conditions.appearanceSelected(.dark) }
    await Self.waitUntil { loaded.simulator.calls.contains(.testCondition(.setDisplaySetting(
      .appearance(.dark),
      self.id
    ))) }
    #expect(conditions.applying[self.id] == .appearance)
    let second = Self.start { await conditions.appearanceSelected(.dark) }
    await Self.waitUntil { second.isFinished }
    let third = Self.start { await conditions.contentSizeSelected(.extraLarge) }
    await Self.waitUntil { third.isFinished }

    loaded.simulator.resumeConditions()
    await first.value()
    let writes = Self.conditionCalls(loaded.simulator).filter {
      if case .setDisplaySetting = $0 {
        true
      } else {
        false
      }
    }
    #expect(writes.count == 1)
    #expect(conditions.applying.isEmpty)
    guard case let .loaded(settings) = conditions.draft?.display else {
      Issue.record("값이 보이지 않는다")
      return
    }
    #expect(settings.appearance == .value(.dark))
    #expect(conditions.draft?.message == nil)
  }

  @Test("지금 값과 같은 외관을 고르면 명령을 보내지 않는다")
  func sameValueDoesNothing() async {
    let loaded = await Self.conditionsModels()
    await loaded.conditions.testConditionsTapped(self.id)
    await loaded.conditions.appearanceSelected(.light)
    await loaded.conditions.contentSizeSelected(.large)
    await loaded.conditions.increaseContrastChanged(false)
    #expect(Self.conditionCalls(loaded.simulator) == [.displaySettings(self.id)])
  }

  @Test("지원 안 함·알 수 없음인 항목은 보내지 않는다")
  func unsupportedOrUnknownDoesNothing() async {
    let loaded = await Self.conditionsModels {
      $0.setDisplaySettings(
        IOSDisplaySettings(appearance: .unknown, contentSize: .unsupported, increaseContrast: .unknown),
        for: SampleID.iPhoneOn
      )
    }
    await loaded.conditions.testConditionsTapped(self.id)
    await loaded.conditions.appearanceSelected(.dark)
    await loaded.conditions.contentSizeSelected(.small)
    await loaded.conditions.increaseContrastChanged(true)
    #expect(Self.conditionCalls(loaded.simulator) == [.displaySettings(self.id)])
  }

  @Test("글씨 크기·고대비를 바꾸면 그 값이 보인다")
  func contentSizeAndContrastApply() async {
    let loaded = await Self.conditionsModels()
    let conditions = loaded.conditions
    await conditions.testConditionsTapped(self.id)
    await conditions.contentSizeSelected(.accessibilityExtraExtraExtraLarge)
    await conditions.increaseContrastChanged(true)

    let expected = IOSDisplaySettings(
      appearance: .value(.light),
      contentSize: .value(.accessibilityExtraExtraExtraLarge),
      increaseContrast: .value(true)
    )
    #expect(conditions.draft?.display == .loaded(expected))
    #expect(Self.conditionCalls(loaded.simulator).suffix(2) == [
      .setDisplaySetting(.contentSize(.accessibilityExtraExtraExtraLarge), self.id),
      .setDisplaySetting(.increaseContrast(true), self.id),
    ])
  }

  @Test("적용되지 않으면 다시 읽은 값을 보이고 적용 안 됨을 알린다")
  func notAppliedShowsReadValue() async {
    let read = IOSDisplaySettings(
      appearance: .value(.light),
      contentSize: .value(.small),
      increaseContrast: .value(false)
    )
    let loaded = await Self.conditionsModels { $0.setDisplaySettingNotApplied(read) }
    await loaded.conditions.testConditionsTapped(self.id)
    await loaded.conditions.appearanceSelected(.dark)

    #expect(loaded.conditions.draft?.display == .loaded(read))
    #expect(loaded.conditions.draft?.message == .notApplied(.appearance))
  }

  @Test("다시 읽은 그 항목이 지원 안 함이면 지원하지 않는다고 알린다")
  func notAppliedUnsupported() async {
    let read = IOSDisplaySettings(
      appearance: .value(.light),
      contentSize: .value(.large),
      increaseContrast: .unsupported
    )
    let loaded = await Self.conditionsModels { $0.setDisplaySettingNotApplied(read) }
    await loaded.conditions.testConditionsTapped(self.id)
    await loaded.conditions.increaseContrastChanged(true)

    #expect(loaded.conditions.draft?.display == .loaded(read))
    #expect(loaded.conditions.draft?.message == .unsupported(.increaseContrast))
  }

  @Test("쓰기가 기기 꺼짐으로 실패하면 실패를 알리고 기기 목록을 다시 읽으며, 다음 적용이 알림을 지운다")
  func writeFailureRefreshes() async {
    let loaded = await Self.conditionsModels { $0.setDisplaySettingError(.deviceNotBooted) }
    let conditions = loaded.conditions
    await conditions.testConditionsTapped(self.id)
    await conditions.appearanceSelected(.dark)

    #expect(conditions.draft?.message == .failed(.appearance, .deviceNotBooted))
    #expect(Self.fetchCount(loaded.simulator) == 2)
    #expect(conditions.applying.isEmpty)
    #expect(loaded.model.notices.isEmpty)

    loaded.simulator.setDisplaySettingError(nil)
    await conditions.appearanceSelected(.dark)
    #expect(conditions.draft?.message == nil)
  }
}

// MARK: - 적용 중 닫기·다시 열기

extension TestConditionsModelTests {
  @Test("적용 중에 닫았다 다시 열면, 다시 읽는 동안 끝난 결과는 표시를 건드리지 않고 알림만 남기며 읽기를 한 번 더 한다")
  func writeFinishedDuringReopenRead() async {
    let read = IOSDisplaySettings(
      appearance: .value(.light),
      contentSize: .value(.small),
      increaseContrast: .value(false)
    )
    let loaded = await Self.conditionsModels()
    let conditions = loaded.conditions
    let simulator = loaded.simulator
    await conditions.testConditionsTapped(self.id)
    simulator.setDisplaySettingNotApplied(read)
    simulator.suspendConditions()
    let write = Self.start { await conditions.appearanceSelected(.dark) }
    await Self.waitUntil { Self.conditionCalls(simulator).count == 2 }
    conditions.closeTapped()

    simulator.suspendConditionReads()
    let reopen = Self.start { await conditions.testConditionsTapped(self.id) }
    await Self.waitUntil { Self.readCount(simulator) == 2 }
    // 다시 연 시트에서도 같은 기기는 적용 중이라 위치를 보내지 않는다.
    conditions.pointTextChanged("37.5, 127")
    await conditions.setPointTapped()
    #expect(Self.conditionCalls(simulator).count == 3)

    simulator.resumeConditions()
    await write.value()
    #expect(conditions.applying.isEmpty)
    #expect(conditions.draft?.display == .loading)
    #expect(conditions.draft?.message == .notApplied(.appearance))

    simulator.resumeConditionReads()
    await reopen.value()
    #expect(Self.readCount(simulator) == 3)
    #expect(conditions.draft?.display == .loaded(read))
    #expect(conditions.draft?.message == .notApplied(.appearance))
  }

  @Test("적용 중에 닫아도 명령은 끝까지 돌고 적용 중이 풀린다")
  func closeWhileApplying() async {
    let loaded = await Self.conditionsModels()
    let conditions = loaded.conditions
    await conditions.testConditionsTapped(self.id)
    loaded.simulator.suspendConditions()
    let write = Self.start { await conditions.appearanceSelected(.dark) }
    await Self.waitUntil { conditions.applying[self.id] != nil }
    conditions.closeTapped()
    #expect(conditions.draft == nil)

    loaded.simulator.resumeConditions()
    await write.value()
    #expect(conditions.applying.isEmpty)
    #expect(loaded.simulator.displaySettings(for: self.id).appearance == .value(.dark))
  }
}
