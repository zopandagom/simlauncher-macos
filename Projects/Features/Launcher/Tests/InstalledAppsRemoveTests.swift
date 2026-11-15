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

/// 설치된 앱 시트의 삭제: 확인·취소, 연타, 진행 중 막기, 성공·실패 뒤 목록, 확인 대기와 목록 읽기의 겹침.
@MainActor
struct InstalledAppsRemoveTests: InstalledAppsTesting {
  private let id = SampleID.iPhoneOn

  /// Sample 을 고르고 "삭제…" 로 확인을 기다리는 상태.
  private static func pendingSample(
    _ configure: (SimulatorClientFake) -> Void = { _ in }
  ) async -> InstalledAppsModels {
    let loaded = await Self.opened(configure)
    loaded.installed.selectionChanged(Self.sample.bundleID)
    loaded.installed.removeTapped()
    return loaded
  }

  @Test("고른 앱이 없으면 삭제… 는 아무것도 하지 않는다")
  func removeNeedsSelection() async {
    let loaded = await Self.opened()
    #expect(loaded.installed.draft?.canRequestAction == false)
    loaded.installed.removeTapped()
    #expect(loaded.installed.draft?.pendingAction == nil)
  }

  @Test("삭제… 는 확인을 기다리고, 취소하면 아무것도 지우지 않는다")
  func cancelDoesNothing() async {
    let loaded = await Self.pendingSample()
    let installed = loaded.installed
    #expect(installed.draft?.pendingAction == .remove(Self.sample))
    #expect(installed.draft?.canRefresh == false)
    #expect(installed.draft?.canRequestAction == false)

    installed.actionCancelled()
    #expect(installed.draft?.pendingAction == nil)
    #expect(Self.uninstallCalls(loaded.simulator).isEmpty)
    // 대기가 없을 때의 취소는 무시한다.
    installed.actionCancelled()
    #expect(installed.draft?.pendingAction == nil)
  }

  @Test("확인하면 첫 await 전에 진행 중이 되고, 진행 중에는 닫기·다시 읽기·고르기·연타를 무시하며, 끝나면 목록에서 빼고 다시 읽는다")
  func confirmRemoves() async {
    let loaded = await Self.pendingSample { $0.suspendUninstalls() }
    let installed = loaded.installed
    let action = InstalledAppsDraft.Action.remove(Self.sample)
    let confirm = Self.start { await installed.actionConfirmed(action) }
    await Self.waitUntil { Self.uninstallCalls(loaded.simulator).count == 1 }

    #expect(installed.draft?.runningAction == action)
    #expect(installed.draft?.pendingAction == nil)
    #expect(installed.draft?.canClose == false)
    installed.closeTapped()
    installed.sheetDismissed()
    #expect(installed.draft != nil)
    await installed.refreshTapped()
    installed.selectionChanged(Self.rig.bundleID)
    #expect(installed.draft?.selection == Self.sample.bundleID)
    let second = Self.start { await installed.actionConfirmed(action) }
    await Self.waitUntil { second.isFinished }
    #expect(Self.appsReadCount(loaded.simulator) == 1)

    // 지운 뒤 다시 읽은 목록에는 그 앱이 없다 (Fake 는 목록을 바꾸지 않아 테스트가 다시 정한다).
    loaded.simulator.setInstalledApps([Self.rig], on: SampleID.iPhoneOn)
    loaded.simulator.suspendInstalledApps()
    loaded.simulator.resumeUninstalls()
    await Self.waitUntil { Self.appsReadCount(loaded.simulator) == 2 }
    #expect(installed.draft?.apps == .reloading([Self.rig]))
    #expect(installed.draft?.selection == nil)
    #expect(installed.draft?.message == .removed(appName: "Sample"))
    #expect(installed.draft?.runningAction == nil)

    loaded.simulator.resumeInstalledApps()
    await confirm.value()
    #expect(Self.uninstallCalls(loaded.simulator) == [.uninstall(Self.sample.bundleID, self.id)])
    #expect(installed.draft?.apps == .loaded([Self.rig]))
    #expect(installed.draft?.selectedApp == Self.rig)
    #expect(installed.draft?.canClose == true)
    installed.closeTapped()
    #expect(installed.draft == nil)
  }

  @Test("SwiftUI 가 버튼 동작 뒤 대화상자를 먼저 닫아도(대기가 비어도) 버튼이 넘긴 동작으로 지운다")
  func confirmAfterDialogDismissed() async {
    let loaded = await Self.pendingSample()
    loaded.installed.actionCancelled()
    await loaded.installed.actionConfirmed(.remove(Self.sample))
    #expect(Self.uninstallCalls(loaded.simulator) == [.uninstall(Self.sample.bundleID, self.id)])
  }

  @Test("명령이 실패하면 결과 줄을 보이고 목록을 다시 읽어 실제 상태를 맞추며, 기기 목록은 다시 읽지 않는다")
  func commandFailureReloads() async {
    let loaded = await Self.pendingSample { $0.setUninstallError(.commandFailed) }
    await loaded.installed.actionConfirmed(.remove(Self.sample))

    #expect(loaded.installed.draft?.message == .failed(.remove(Self.sample), .commandFailed))
    #expect(loaded.installed.draft?.runningAction == nil)
    #expect(loaded.installed.draft?.apps == .loaded([Self.sample, Self.rig]))
    #expect(loaded.installed.draft?.selection == Self.sample.bundleID)
    #expect(Self.appsReadCount(loaded.simulator) == 2)
    #expect(Self.fetchCount(loaded.simulator) == 1)
  }

  @Test("기기 꺼짐·없어짐으로 실패하면 결과 줄과 목록 실패를 보이고 기기 목록을 다시 읽는다 (목록은 다시 읽지 않는다)")
  func deviceGoneFailure() async {
    for error in [SimulatorError.deviceNotBooted, .deviceNotFound] {
      let loaded = await Self.pendingSample { $0.setUninstallError(error) }
      await loaded.installed.actionConfirmed(.remove(Self.sample))

      #expect(loaded.installed.draft?.message == .failed(.remove(Self.sample), error))
      #expect(loaded.installed.draft?.apps == .failed(error))
      #expect(loaded.installed.draft?.selection == nil)
      #expect(Self.appsReadCount(loaded.simulator) == 1)
      #expect(Self.fetchCount(loaded.simulator) == 2)
      #expect(loaded.model.notices.isEmpty)
    }
  }

  @Test("목록을 읽는 동안에는 삭제… 를 받지 않고, 확인(버튼이 넘긴 동작)이 와도 지우지 않는다")
  func confirmIgnoredWhileReading() async {
    let loaded = await Self.opened()
    let installed = loaded.installed
    installed.selectionChanged(Self.sample.bundleID)
    loaded.simulator.suspendInstalledApps()
    let refresh = Self.start { await installed.refreshTapped() }
    await Self.waitUntil { Self.appsReadCount(loaded.simulator) == 2 }
    installed.removeTapped()
    #expect(installed.draft?.pendingAction == nil)

    // 확인 대기 중 읽기가 시작된 경우(대기를 띄운 채 읽기 시작)는 `InstalledAppsDraftTests.canConfirmFollowsReading` 이 본다.
    await installed.actionConfirmed(.remove(Self.sample))
    #expect(Self.uninstallCalls(loaded.simulator).isEmpty)
    #expect(installed.draft?.runningAction == nil)
    loaded.simulator.resumeInstalledApps()
    await refresh.value()
    #expect(installed.draft?.apps == .loaded([Self.sample, Self.rig]))
  }

  @Test("대상 앱이 보이는 목록에 없으면 확인을 받지 않는다")
  func confirmIgnoredWhenAppMissing() async throws {
    let loaded = await Self.opened()
    try await loaded.installed.actionConfirmed(.remove(InstalledApp(
      bundleID: #require(AppBundleID("com.example.other")),
      displayName: "Other",
      version: nil,
      build: nil
    )))
    #expect(Self.uninstallCalls(loaded.simulator).isEmpty)
  }
}

/// 초안 계산(`InstalledAppsDraft`)과 열기 조건(`InstalledAppsAvailability`·`LauncherModel.installedAppsTarget`).
@MainActor
struct InstalledAppsDraftTests: InstalledAppsTesting {
  private let id = SampleID.iPhoneOn

  private func draft() -> InstalledAppsDraft {
    InstalledAppsDraft(deviceID: self.id, device: Self.label(self.id), session: 1)
  }

  @Test("확인 대기 중 목록 읽기가 시작되면 canConfirm 이 거짓이고, 읽기가 끝나면 다시 참이다")
  func canConfirmFollowsReading() {
    var draft = self.draft()
    draft.appsStarted()
    draft.appsLoaded([Self.sample, Self.rig])
    draft.selectionChanged(Self.sample.bundleID)
    draft.actionRequested(.remove(Self.sample))
    #expect(draft.canConfirm(.remove(Self.sample)))
    #expect(!draft.canConfirm(.remove(Self.rig)))

    draft.appsStarted()
    #expect(draft.apps == .reloading([Self.sample, Self.rig]))
    #expect(!draft.canConfirm(.remove(Self.sample)))

    draft.appsLoaded([Self.rig])
    #expect(!draft.canConfirm(.remove(Self.sample)))
    #expect(draft.selection == Self.rig.bundleID)
  }

  @Test("진행 중이면 고르기·닫기·다시 읽기·요청·확인을 받지 않고, 실패하면 목록·선택을 그대로 둔다")
  func runningBlocks() {
    var draft = self.draft()
    draft.appsStarted()
    draft.appsLoaded([Self.sample, Self.rig])
    draft.selectionChanged(Self.sample.bundleID)
    draft.actionStarted(.remove(Self.sample))
    #expect(draft.isBusy)
    #expect(!draft.canClose)
    #expect(!draft.canRefresh)
    #expect(!draft.canRequestAction)
    #expect(!draft.canConfirm(.remove(Self.sample)))
    draft.selectionChanged(Self.rig.bundleID)
    #expect(draft.selection == Self.sample.bundleID)

    draft.actionFailed(.remove(Self.sample), .commandFailed)
    #expect(draft.canClose)
    #expect(draft.apps == .loaded([Self.sample, Self.rig]))
    #expect(draft.message == .failed(.remove(Self.sample), .commandFailed))
  }

  @Test("열기: 켜지고 쓸 수 있는 기기이고 진행 작업이 하나도 없을 때만 연다")
  func canOpenTable() {
    let states: [VirtualDevice.State] = [.shutdown, .booted, .booting, .shuttingDown, .unknown]
    for state in states {
      for isAvailable in [true, false] {
        let device = Self.device(state: state, isAvailable: isAvailable)
        let expected = isAvailable && state == .booted
        #expect(InstalledAppsAvailability.canOpen(device: device, during: nil) == expected, "\(state) \(isAvailable)")
      }
    }
    let booted = Self.device(state: .booted)
    for task in [DeviceTask.installApp, .openURL, .launchApp, .boot, .shutdown, .delete, .erase] {
      #expect(!InstalledAppsAvailability.canOpen(device: booted, during: task), "\(task)")
    }
  }

  @Test("열 기기: 목록·기기·켜짐이 필요하고, 다른 시트·URL 설치 시트·만들기 시트·확인 대화상자가 있으면 없다")
  func targetBlockedByOtherSheets() async {
    let loaded = await Self.installedAppsModels()
    let model = loaded.model
    #expect(model.installedAppsTarget(self.id)?.id == self.id)
    #expect(model.installedAppsTarget(SampleID.iPhoneOff) == nil)
    #expect(model.installedAppsTarget(VirtualDevice.ID("missing")) == nil)

    loaded.sheets.openURLTapped(self.id)
    #expect(model.installedAppsTarget(self.id) == nil)
    loaded.sheets.openURLCancelTapped()

    await loaded.conditions.testConditionsTapped(self.id)
    #expect(model.installedAppsTarget(self.id) == nil)
    loaded.conditions.closeTapped()

    model.installFromURLMenuTapped(self.id)
    #expect(model.installedAppsTarget(self.id) == nil)
    model.installURLSheetDismissed()

    model.eraseButtonTapped(SampleID.iPhoneOff)
    #expect(model.installedAppsTarget(self.id) == nil)
    model.confirmationDismissed()

    model.createButtonTapped()
    #expect(model.installedAppsTarget(self.id) == nil)
    model.createSheetDismissed()

    #expect(model.installedAppsTarget(self.id)?.id == self.id)
    // 설치된 앱 시트가 떠 있으면 다른 시트를 열지 않는다.
    await loaded.installed.installedAppsTapped(self.id)
    #expect(model.testConditionsTarget(self.id) == nil)
    model.createButtonTapped()
    #expect(model.createDraft == nil)
  }

  @Test("열 기기: 목록을 읽기 전이면 없고, 그 기기에 진행 작업(설치)이 있으면 없다")
  func targetBlockedByListAndTask() async {
    let fake = SimulatorClientFake(inventory: .sample)
    let unloaded = LauncherModel(
      simulator: fake,
      appBundle: AppBundleClientFake(),
      download: DownloadClientFake(),
      workspace: WorkspaceClientFake(),
      appLog: AppLogClientFake()
    )
    #expect(unloaded.installedAppsTarget(self.id) == nil)

    let loaded = await Self.installedAppsModels { $0.suspendInstalls() }
    let picked = URL(filePath: "/Users/tester/Downloads/My App.app", directoryHint: .isDirectory)
    let install = Task { await loaded.model.appFileSelected(picked, for: self.id) }
    await Self.waitUntil { loaded.model.activity.task(on: self.id) == .installApp }
    #expect(loaded.model.installedAppsTarget(self.id) == nil)
    await loaded.installed.installedAppsTapped(self.id)
    #expect(loaded.installed.draft == nil)
    loaded.simulator.resumeInstalls()
    await install.value
  }

  private static func device(state: VirtualDevice.State, isAvailable: Bool = true) -> VirtualDevice {
    VirtualDevice(
      id: SampleID.iPhoneOn,
      name: "iPhone 17 Pro",
      family: .phone,
      state: state,
      availability: isAvailable ? .available : .unavailable(.runtimeNotInstalled),
      runtime: SampleRuntime.iOS27
    )
  }
}
