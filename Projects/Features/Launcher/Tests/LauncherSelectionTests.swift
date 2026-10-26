import Core
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

/// 목록 다중 선택(`selection`)과 툴바가 읽는 선택 읽기 API.
@MainActor
struct LauncherSelectionTests: LauncherModelTesting {
  @Test("selectionChanged 는 받은 집합을 그대로 둔다")
  func selectionChangedAssigns() async {
    let (model, _) = await Self.loadedModel()

    model.selectionChanged([SampleID.iPhoneOn, SampleID.iPadOff])
    #expect(model.selection == [SampleID.iPhoneOn, SampleID.iPadOff])

    model.selectionChanged([])
    #expect(model.selection.isEmpty)
  }

  @Test("다시 읽은 목록에서 사라진 기기는 선택에서 빠지고, 다시 읽기가 실패하면 그대로다")
  func reloadPrunesSelection() async {
    let (model, simulator) = await Self.loadedModel()
    model.selectionChanged([SampleID.iPhoneOn, SampleID.iPadOff])

    simulator.setFetchError(.developerToolsUnavailable)
    simulator.setInventory(Self.inventory(removing: SampleID.iPadOff))
    await model.refreshButtonTapped()
    #expect(model.selection == [SampleID.iPhoneOn, SampleID.iPadOff])

    simulator.setFetchError(nil)
    await model.refreshButtonTapped()
    #expect(model.selection == [SampleID.iPhoneOn])
    #expect(model.selectedDevices.map(\.id) == [SampleID.iPhoneOn])
  }

  @Test("selectedDevices 는 고른 기기만 지금 목록 순서(섹션 → 행)로 돌려주고, 목록이 없으면 비어 있다")
  func selectedDevicesFollowListOrder() async {
    let (model, _) = await Self.loadedModel()

    model.selectionChanged([SampleID.unavailableIPhone, SampleID.iPhoneIOS26, SampleID.iPadOff, SampleID.iPhoneOff])

    #expect(model.selectedDevices.map(\.id) == [
      SampleID.iPhoneOff, SampleID.iPadOff, SampleID.iPhoneIOS26, SampleID.unavailableIPhone,
    ])

    let (failed, _) = await Self.loadedModel { $0.setFetchError(.developerToolsUnavailable) }
    failed.selectionChanged([SampleID.iPhoneOn])
    #expect(failed.selectedDevices.isEmpty)
    #expect(!failed.canInstallOnSelection)
    #expect(!failed.canBootSelection)
  }

  @Test("canInstallOnSelection 은 고른 기기 중 하나라도 앱 설치를 시작할 수 있을 때만 true 다")
  func canInstallOnSelection() async {
    let (model, simulator) = await Self.loadedModel { $0.suspendBoots() }
    #expect(!model.canInstallOnSelection)

    model.selectionChanged([SampleID.unavailableIPhone])
    #expect(!model.canInstallOnSelection)

    // 다른 작업 중인 기기만 남으면 false.
    let boot = Task { await model.bootButtonTapped(SampleID.iPhoneOff) }
    await Self.waitUntil { simulator.calls.contains(.boot(SampleID.iPhoneOff)) }
    model.selectionChanged([SampleID.iPhoneOff, SampleID.unavailableIPhone])
    #expect(!model.canInstallOnSelection)

    model.selectionChanged([SampleID.iPhoneOff, SampleID.unavailableIPhone, SampleID.iPhoneOn])
    #expect(model.canInstallOnSelection)

    simulator.resumeBoots()
    await boot.value
  }

  @Test("canBootSelection 은 고른 기기 중 켤 수 있는 꺼진 기기가 있을 때만 true 다")
  func canBootSelection() async {
    let (model, _) = await Self.loadedModel()
    #expect(!model.canBootSelection)

    model.selectionChanged([SampleID.iPhoneOn, SampleID.unavailableIPhone])
    #expect(!model.canBootSelection)

    model.selectionChanged([SampleID.iPhoneOn, SampleID.iPadOff])
    #expect(model.canBootSelection)
  }
}
