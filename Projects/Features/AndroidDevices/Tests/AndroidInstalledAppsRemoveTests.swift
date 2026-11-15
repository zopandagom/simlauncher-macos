import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Foundation
import Testing
@testable import AndroidDevicesFeature

/// Android 설치된 앱 시트의 삭제: 확인·취소, 연타, 진행 중 막기, 성공·실패 뒤 목록, 목록 읽기와의 겹침, 초안 계산.
@MainActor
struct AndroidInstalledAppsRemoveTests: AndroidInstalledAppsTesting {
  private var id: AndroidVirtualDevice.ID {
    Self.tabletID
  }

  @Test("고른 패키지가 없으면 삭제… 는 아무것도 하지 않고, 고르면 확인을 기다리며 취소하면 지우지 않는다")
  func requestAndCancel() async {
    let setup = await Self.opened()
    let installed = setup.installedApps
    installed.removeTapped()
    #expect(installed.draft?.pendingAction == nil)

    installed.selectionChanged(Self.sample)
    installed.removeTapped()
    #expect(installed.draft?.pendingAction == .remove(Self.sample))
    #expect(installed.draft?.canRefresh == false)
    installed.actionCancelled()
    installed.actionCancelled()
    #expect(installed.draft?.pendingAction == nil)
    #expect(Self.uninstallCalls(setup.fake).isEmpty)
  }

  @Test("확인하면 첫 await 전에 진행 중이 되고, 진행 중에는 닫기·다시 읽기·고르기·연타를 무시하며, 끝나면 목록에서 빼고 다시 읽는다")
  func confirmRemoves() async {
    let setup = await Self.pendingSample { $0.suspendUninstalls() }
    let installed = setup.installedApps
    let action = AndroidInstalledAppsDraft.Action.remove(Self.sample)
    let confirm = Self.start { await installed.actionConfirmed(action) }
    await Self.waitUntil { Self.uninstallCalls(setup.fake).count == 1 }

    #expect(installed.draft?.runningAction == action)
    #expect(installed.draft?.canClose == false)
    installed.closeTapped()
    installed.sheetDismissed()
    #expect(installed.draft != nil)
    await installed.refreshTapped()
    installed.selectionChanged(Self.shop)
    #expect(installed.draft?.selection == Self.sample)
    let second = Self.start { await installed.actionConfirmed(action) }
    await Self.waitUntil { second.isFinished }
    #expect(Self.packagesReadCount(setup.fake) == 1)

    setup.fake.setInstalledPackages(.success([Self.shop]))
    setup.fake.suspendPackageLists()
    setup.fake.resumeUninstalls()
    await Self.waitUntil { Self.packagesReadCount(setup.fake) == 2 }
    #expect(installed.draft?.packages == .reloading([Self.shop]))
    #expect(installed.draft?.selection == nil)
    #expect(installed.draft?.message == .removed(Self.sample))

    setup.fake.resumePackageLists()
    await confirm.value()
    #expect(Self.uninstallCalls(setup.fake) == [.uninstall(Self.sample, self.id)])
    #expect(installed.draft?.packages == .loaded([Self.shop]))
    #expect(installed.draft?.selectedPackage == Self.shop)
    installed.closeTapped()
    #expect(installed.draft == nil)
  }

  @Test("SwiftUI 가 버튼 동작 뒤 대화상자를 먼저 닫아도(대기가 비어도) 버튼이 넘긴 동작으로 지운다")
  func confirmAfterDialogDismissed() async {
    let setup = await Self.pendingSample()
    setup.installedApps.actionCancelled()
    await setup.installedApps.actionConfirmed(.remove(Self.sample))
    #expect(Self.uninstallCalls(setup.fake) == [.uninstall(Self.sample, self.id)])
  }

  @Test("명령이 실패하면 결과 줄을 보이고 목록을 다시 읽으며, 기기 목록은 다시 읽지 않는다")
  func commandFailureReloads() async {
    let setup = await Self.pendingSample { $0.setUninstallError(.appCommandFailed) }
    await setup.installedApps.actionConfirmed(.remove(Self.sample))
    #expect(setup.installedApps.draft?.message == .failed(.remove(Self.sample), .appCommandFailed))
    #expect(setup.installedApps.draft?.packages == .loaded([Self.sample, Self.shop]))
    #expect(setup.installedApps.draft?.selection == Self.sample)
    #expect(Self.packagesReadCount(setup.fake) == 2)
    #expect(Self.fetchCount(setup.fake) == 1)
  }

  @Test("기기 꺼짐·없어짐으로 실패하면 결과 줄과 목록 실패를 보이고 기기 목록을 다시 읽는다")
  func deviceGoneFailure() async {
    for error in [AndroidEmulatorError.deviceNotBooted, .deviceNotFound] {
      let setup = await Self.pendingSample { $0.setUninstallError(error) }
      await setup.installedApps.actionConfirmed(.remove(Self.sample))
      #expect(setup.installedApps.draft?.message == .failed(.remove(Self.sample), error))
      #expect(setup.installedApps.draft?.packages == .failed(error))
      #expect(Self.packagesReadCount(setup.fake) == 1)
      #expect(Self.fetchCount(setup.fake) == 2)
      #expect(Self.notices(setup.model).isEmpty)
    }
  }

  @Test("목록을 읽는 동안이나 대상이 목록에 없으면 확인을 받지 않는다")
  func confirmIgnoredWhileReadingOrMissing() async throws {
    let setup = await Self.opened()
    let installed = setup.installedApps
    try await installed.actionConfirmed(.remove(#require(AndroidPackageName("com.example.other"))))
    #expect(Self.uninstallCalls(setup.fake).isEmpty)

    setup.fake.suspendPackageLists()
    let refresh = Self.start { await installed.refreshTapped() }
    await Self.waitUntil { Self.packagesReadCount(setup.fake) == 2 }
    await installed.actionConfirmed(.remove(Self.sample))
    #expect(Self.uninstallCalls(setup.fake).isEmpty)
    #expect(installed.draft?.runningAction == nil)
    setup.fake.resumePackageLists()
    await refresh.value()
  }

  // MARK: - 초안

  @Test("확인 대기 중 목록 읽기가 시작되면 canConfirm 이 거짓이고, 대상이 빠진 목록이면 끝나도 거짓이다")
  func canConfirmFollowsReading() {
    var draft = AndroidInstalledAppsDraft(
      deviceID: self.id,
      device: AndroidDeviceLabel(.bootedTabletSample),
      session: 1
    )
    draft.packagesStarted()
    draft.packagesLoaded([Self.sample, Self.shop])
    draft.selectionChanged(Self.sample)
    draft.actionRequested(.remove(Self.sample))
    #expect(draft.canConfirm(.remove(Self.sample)))
    #expect(!draft.canConfirm(.remove(Self.shop)))

    draft.packagesStarted()
    #expect(!draft.canConfirm(.remove(Self.sample)))
    draft.packagesLoaded([Self.shop])
    #expect(!draft.canConfirm(.remove(Self.sample)))
    #expect(draft.selection == Self.shop)

    draft.actionStarted(.remove(Self.shop))
    #expect(!draft.canClose)
    #expect(!draft.canRefresh)
    #expect(!draft.canRequestAction)
    draft.selectionChanged(nil)
    #expect(draft.selection == Self.shop)
    draft.actionFailed(.remove(Self.shop), .appCommandFailed)
    #expect(draft.canClose)
    #expect(draft.packages == .loaded([Self.shop]))
  }
}
