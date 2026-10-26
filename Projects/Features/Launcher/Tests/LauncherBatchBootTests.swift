import Core
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

/// 툴바 "선택한 기기 켜기".
@MainActor
struct LauncherBatchBootTests: LauncherModelTesting {
  @Test("고른 기기 중 켤 수 있는 꺼진 기기만 켜고, 모두 성공하면 알림이 없고 기록이 남지 않는다")
  func bootsOnlyBootableDevices() async {
    let (model, simulator) = await Self.loadedModel()
    model.selectionChanged([SampleID.iPhoneOff, SampleID.iPhoneOn, SampleID.iPadOff, SampleID.unavailableIPhone])

    await model.bootSelectedTapped()

    let boots = simulator.calls.filter {
      if case .boot = $0 {
        true
      } else {
        false
      }
    }
    #expect(Set(boots) == [.boot(SampleID.iPhoneOff), .boot(SampleID.iPadOff)])
    #expect(boots.count == 2)
    #expect(Self.device(SampleID.iPhoneOff, in: model)?.state == .booted)
    #expect(Self.device(SampleID.iPadOff, in: model)?.state == .booted)
    #expect(model.notices.isEmpty)
    #expect(model.activity == DeviceActivity())
  }

  @Test("여러 대는 동시에 켜는 중이 된다")
  func bootsConcurrently() async {
    let (model, simulator) = await Self.loadedModel { $0.suspendBoots() }
    model.selectionChanged([SampleID.iPhoneOff, SampleID.iPadOff])

    let boot = Task { await model.bootSelectedTapped() }
    await Self.waitUntil {
      simulator.calls.contains(.boot(SampleID.iPhoneOff)) && simulator.calls.contains(.boot(SampleID.iPadOff))
    }
    #expect(model.activity.task(on: SampleID.iPhoneOff) == .boot)
    #expect(model.activity.task(on: SampleID.iPadOff) == .boot)

    simulator.resumeBoots()
    await boot.value
    #expect(model.activity == DeviceActivity())
  }

  @Test("먼저 켜진 기기는 다시 읽은 뒤 풀려, 다른 기기를 켜는 동안에도 켜짐으로 보이고 다시 켤 수 없다")
  func firstBootedDeviceShowsBootedBeforeOthersFinish() async {
    let (model, simulator) = await Self.loadedModel { $0.suspendBoot(of: SampleID.iPadOff) }
    model.selectionChanged([SampleID.iPhoneOff, SampleID.iPadOff])

    let boot = Task { await model.bootSelectedTapped() }
    // iPad 켜기가 멈춘 채 묶음이 시작된 뒤 iPhone 만 먼저 풀리기를 기다린다.
    await Self.waitUntil {
      simulator.calls.contains(.boot(SampleID.iPadOff)) && model.activity.task(on: SampleID.iPhoneOff) == nil
    }
    #expect(Self.device(SampleID.iPhoneOff, in: model)?.state == .booted)
    #expect(model.activity.task(on: SampleID.iPadOff) == .boot)
    #expect(!model.canBootSelection)

    simulator.resumeBoot(of: SampleID.iPadOff)
    await boot.value
    #expect(Self.device(SampleID.iPadOff, in: model)?.state == .booted)
    #expect(model.notices.isEmpty)
    #expect(model.activity == DeviceActivity())
  }

  @Test("모두 켜지 못하면 기기별 켜기 실패가 든 결과 알림 하나만 쌓는다")
  func allFailuresMakeOneReport() async {
    let (model, _) = await Self.loadedModel { $0.setBootError(.deviceNotFound) }
    model.selectionChanged([SampleID.iPadOff, SampleID.iPhoneOff, SampleID.iPhoneOn])

    await model.bootSelectedTapped()

    #expect(model.notices.map(\.notice) == [
      .batchFinished(BatchReport(
        action: .boot,
        entries: [
          BatchReport.Entry(device: Self.label(SampleID.iPhoneOff), result: .bootFailed(.deviceNotFound)),
          BatchReport.Entry(device: Self.label(SampleID.iPadOff), result: .bootFailed(.deviceNotFound)),
        ],
        simulatorAppError: nil
      )),
    ])
    #expect(model.activity == DeviceActivity())
  }

  @Test("켤 기기가 한 대면 행의 켜기와 같다: 실패하면 기존 켜기 실패 알림 하나다")
  func singleBootUsesRowNotice() async {
    let (model, simulator) = await Self.loadedModel { $0.setBootError(.deviceNotFound) }
    model.selectionChanged([SampleID.iPhoneOff, SampleID.iPhoneOn])

    await model.bootSelectedTapped()

    #expect(model.notices.map(\.notice) == [.bootFailed(Self.label(SampleID.iPhoneOff), .deviceNotFound)])
    #expect(Self.bootCount(SampleID.iPhoneOff, in: simulator) == 1)
    #expect(model.activity == DeviceActivity())
  }

  @Test("켤 기기가 없으면(선택 없음·모두 켜짐) 아무 명령도 하지 않는다")
  func nothingToBoot() async {
    let (model, simulator) = await Self.loadedModel()
    await model.bootSelectedTapped()
    model.selectionChanged([SampleID.iPhoneOn])
    await model.bootSelectedTapped()

    #expect(simulator.calls == [.fetchInventory])
    #expect(model.notices.isEmpty)
  }
}
