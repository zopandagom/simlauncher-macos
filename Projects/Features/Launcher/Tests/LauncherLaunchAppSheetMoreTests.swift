import Core
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

/// "앱 실행…" 시트 (이어서): 읽기 중 닫기·앱 밖에서 바뀐 기기·열 수 없는 경우. 타입 본문 길이 한도 때문에 나눈 같은 스위트의 나머지다.
extension LauncherLaunchAppSheetTests {
  @Test("목록을 읽는 중에 닫으면 결과를 버린다")
  func cancelWhileLoadingDiscardsResult() async {
    let loaded = await Self.loadedModels {
      $0.setInstalledApps([InstalledAppSamples.alpha], on: SampleID.iPhoneOn)
      $0.suspendInstalledApps()
    }
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    let tap = Self.start { await sheets.launchAppTapped(SampleID.iPhoneOn) }
    await Self.waitUntil { simulator.calls.contains(.installedApps(SampleID.iPhoneOn)) }

    sheets.launchAppCancelTapped()
    simulator.resumeInstalledApps()
    await tap.value()
    #expect(sheets.launchAppDraft == nil)
  }

  @Test("시트를 연 뒤 기기가 앱 밖에서 지워지면 읽기 실패를 보이고, 다시 시도는 준비 판정이 찾을 수 없다고 보인다")
  func deviceRemovedOutsideApp() async {
    let id = SampleID.iPhoneOn
    let loaded = await Self.loadedModels()
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    simulator.setInventory(Self.inventory(removing: id))

    await sheets.launchAppTapped(id)
    #expect(sheets.launchAppDraft?.apps == .failed(.simulator(.deviceNotFound), stage: .list))
    #expect(Self.device(id, in: model) == nil)

    await sheets.launchAppRetryTapped()
    #expect(sheets.launchAppDraft?.apps == .failed(.simulator(.deviceNotFound), stage: .list))
    #expect(simulator.calls.filter { $0 == .installedApps(id) }.count == 1)
    #expect(model.notices.isEmpty)
  }

  @Test("실패 뒤 기기가 켜는 중이 되면 다시 시도는 상태가 바뀌는 중이라고 보인다")
  func retryWhileDeviceBooting() async {
    let id = SampleID.iPhoneOn
    let loaded = await Self.loadedModels { $0.setInstalledAppsError(.commandFailed) }
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    await sheets.launchAppTapped(id)
    simulator.setInventory(Self.inventory(id, state: .booting))
    await model.refreshButtonTapped()

    await sheets.launchAppRetryTapped()
    #expect(sheets.launchAppDraft?.apps == .failed(.deviceNotReady(.stateChanging), stage: .list))
  }

  @Test("앱 밖에서 꺼진 기기는 읽기 실패 뒤 다시 읽은 목록이 꺼짐이라, 다시 시도가 켜는 중으로 시작해 켠다")
  func retryBootsDeviceShutDownOutsideApp() async {
    let id = SampleID.iPhoneOn
    let loaded = await Self.loadedModels {
      $0.setInstalledApps([InstalledAppSamples.alpha], on: SampleID.iPhoneOn)
    }
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    simulator.setInventory(Self.inventory(id, state: .shutdown))

    await sheets.launchAppTapped(id)
    #expect(sheets.launchAppDraft?.apps == .failed(.simulator(.deviceNotBooted), stage: .list))

    simulator.suspendBoots()
    let retry = Self.start { await sheets.launchAppRetryTapped() }
    await Self.waitUntil { simulator.calls.contains(.boot(id)) }
    #expect(sheets.launchAppDraft?.apps == .booting)
    simulator.resumeBoots()
    await retry.value()
    #expect(sheets.launchAppDraft?.apps == .loaded([InstalledAppSamples.alpha]))
  }

  @Test("쓸 수 없는·켜는 중·목록에 없는 기기와 목록을 읽기 전에는 시트를 열지 않는다")
  func blockedDevicesDoNotOpen() async {
    let loaded = await Self.loadedModels()
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    await sheets.launchAppTapped(SampleID.unavailableIPhone)
    await sheets.launchAppTapped(VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF"))
    #expect(sheets.launchAppDraft == nil)

    simulator.setInventory(Self.inventory(SampleID.iPhoneOff, state: .booting))
    await model.refreshButtonTapped()
    await sheets.launchAppTapped(SampleID.iPhoneOff)
    #expect(sheets.launchAppDraft == nil)
    #expect(!simulator.calls.contains {
      if case .installedApps = $0 {
        true
      } else {
        false
      }
    })
  }

  @Test("작업 중인 기기에서는 시트를 열지 않는다")
  func busyDeviceDoesNotOpen() async {
    let loaded = await Self.loadedModels { $0.suspendBoots() }
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    let boot = Self.start { await model.bootButtonTapped(SampleID.iPhoneOff) }
    await Self.waitUntil { simulator.calls.contains(.boot(SampleID.iPhoneOff)) }

    await sheets.launchAppTapped(SampleID.iPhoneOff)
    #expect(sheets.launchAppDraft == nil)

    simulator.resumeBoots()
    await boot.value()
  }

  @Test("만들기·URL 설치·링크 열기 시트나 확인 대화상자가 있으면 시트를 열지 않는다")
  func otherPresentationsBlockSheet() async {
    let loaded = await Self.loadedModels()
    let model = loaded.model
    let sheets = loaded.sheets

    model.createButtonTapped()
    await sheets.launchAppTapped(SampleID.iPhoneOn)
    #expect(sheets.launchAppDraft == nil)
    model.createCancelTapped()

    model.installFromURLMenuTapped(SampleID.iPhoneOff)
    await sheets.launchAppTapped(SampleID.iPhoneOn)
    #expect(sheets.launchAppDraft == nil)
    model.installURLCancelTapped()

    model.deleteButtonTapped(SampleID.iPhoneOff)
    await sheets.launchAppTapped(SampleID.iPhoneOn)
    #expect(sheets.launchAppDraft == nil)
    model.confirmationDismissed()

    sheets.openURLTapped(SampleID.iPhoneOff)
    await sheets.launchAppTapped(SampleID.iPhoneOn)
    #expect(sheets.launchAppDraft == nil)
    sheets.openURLCancelTapped()

    await sheets.launchAppTapped(SampleID.iPhoneOn)
    #expect(sheets.launchAppDraft != nil)
  }

  @Test("앱 실행 시트가 떠 있으면 + 버튼·삭제·초기화 확인·URL 설치·링크 열기 시트를 받지 않는다")
  func sheetBlocksOtherPresentations() async {
    let loaded = await Self.loadedModels()
    let model = loaded.model
    let sheets = loaded.sheets
    await sheets.launchAppTapped(SampleID.iPhoneOn)

    #expect(!model.canCreateDevice)
    #expect(model.isSheetOrDialogOpen)
    model.createButtonTapped()
    #expect(model.createDraft == nil)
    model.deleteButtonTapped(SampleID.iPhoneOff)
    model.eraseButtonTapped(SampleID.iPhoneOff)
    #expect(model.pendingConfirmation == nil)
    model.installFromURLMenuTapped(SampleID.iPhoneOff)
    #expect(model.installURLDraft == nil)
    sheets.openURLTapped(SampleID.iPhoneOff)
    #expect(sheets.openURLDraft == nil)

    sheets.launchAppSheetDismissed()
    #expect(model.canCreateDevice)
  }
}
