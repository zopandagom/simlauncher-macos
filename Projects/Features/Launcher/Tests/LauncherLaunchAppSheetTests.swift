import Core
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

/// "앱 실행…" 시트: 여는 조건, 켜기·목록 읽기, 실패와 다시 시도, 겹침. 두 Model 은 App 처럼 잇는다 (`loadedModels`).
@MainActor
struct LauncherLaunchAppSheetTests: LauncherModelTesting {
  // MARK: - 켜진 기기

  @Test("켜진 기기는 누르자마자 시트를 불러오는 중으로 열고, 목록을 읽어 보인다 (켜지 않고 Simulator 앱도 열지 않는다)")
  func bootedDeviceLoadsApps() async {
    let loaded = await Self.loadedModels {
      $0.setInstalledApps(InstalledAppSamples.two, on: SampleID.iPhoneOn)
      $0.suspendInstalledApps()
    }
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    let tap = Self.start { await sheets.launchAppTapped(SampleID.iPhoneOn) }
    await Self.waitUntil { simulator.calls.contains(.installedApps(SampleID.iPhoneOn)) }

    #expect(sheets.launchAppDraft?.deviceID == SampleID.iPhoneOn)
    #expect(sheets.launchAppDraft?.device == Self.label(SampleID.iPhoneOn))
    #expect(sheets.launchAppDraft?.apps == .loading)
    #expect(model.activity.task(on: SampleID.iPhoneOn) == nil)

    simulator.resumeInstalledApps()
    await tap.value()
    #expect(sheets.launchAppDraft?.apps == .loaded(InstalledAppSamples.two))
    #expect(simulator.calls == [.fetchInventory, .installedApps(SampleID.iPhoneOn)])
    #expect(model.notices.isEmpty)
  }

  @Test("설치한 앱이 없으면 빈 목록이다")
  func emptyList() async {
    let loaded = await Self.loadedModels()
    let sheets = loaded.sheets
    await sheets.launchAppTapped(SampleID.iPhoneOn)
    #expect(sheets.launchAppDraft?.apps == .loaded([]))
    #expect(sheets.launchAppDraft?.canSubmit == false)
  }

  @Test("목록 읽기가 실패하면 기기 목록을 다시 읽은 뒤 시트에 이유를 보이고 알림은 쌓지 않으며, 다시 시도하면 다시 읽는다")
  func listFailureThenRetry() async {
    let loaded = await Self.loadedModels {
      $0.setInstalledApps([InstalledAppSamples.alpha], on: SampleID.iPhoneOn)
      $0.setInstalledAppsError(.commandFailed)
    }
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    await sheets.launchAppTapped(SampleID.iPhoneOn)

    #expect(sheets.launchAppDraft?.apps == .failed(.simulator(.commandFailed), stage: .list))
    #expect(simulator.calls == [.fetchInventory, .installedApps(SampleID.iPhoneOn), .fetchInventory])
    #expect(model.notices.isEmpty)

    simulator.setInstalledAppsError(nil)
    await sheets.launchAppRetryTapped()
    #expect(sheets.launchAppDraft?.apps == .loaded([InstalledAppSamples.alpha]))
    #expect(sheets.launchAppDraft?.selection == InstalledAppSamples.alpha.bundleID)
    #expect(Self.bootCount(SampleID.iPhoneOn, in: simulator) == 0)
  }

  @Test("다시 시도는 실패 상태일 때만 한다")
  func retryOnlyWhenFailed() async {
    let loaded = await Self.loadedModels()
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    await sheets.launchAppRetryTapped()
    await sheets.launchAppTapped(SampleID.iPhoneOn)
    await sheets.launchAppRetryTapped()
    #expect(simulator.calls == [.fetchInventory, .installedApps(SampleID.iPhoneOn)])
  }

  // MARK: - 꺼진 기기

  @Test("꺼진 기기는 누르자마자 시트를 켜는 중으로 열고 행은 켜는 중이며, 켜지면 목록을 읽고 Simulator 앱은 열지 않는다")
  func shutdownDeviceBootsThenLoads() async {
    let id = SampleID.iPhoneOff
    let loaded = await Self.loadedModels {
      $0.setInstalledApps([InstalledAppSamples.alpha], on: id)
      $0.suspendBoots()
    }
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    let tap = Self.start { await sheets.launchAppTapped(id) }
    await Self.waitUntil { simulator.calls.contains(.boot(id)) }

    #expect(sheets.launchAppDraft?.apps == .booting)
    #expect(model.activity.task(on: id) == .boot)

    simulator.resumeBoots()
    await tap.value()
    #expect(sheets.launchAppDraft?.apps == .loaded([InstalledAppSamples.alpha]))
    #expect(simulator.calls == [.fetchInventory, .boot(id), .fetchInventory, .installedApps(id)])
    #expect(!simulator.calls.contains(.openSimulatorApp))
    #expect(Self.device(id, in: model)?.state == .booted)
    #expect(model.activity.task(on: id) == nil)
    #expect(model.notices.isEmpty)
  }

  @Test("켜기가 실패하면 다시 읽고 시트에 켜기 실패를 보이며 알림은 쌓지 않고, 다시 시도하면 다시 켠다")
  func bootFailureThenRetry() async {
    let id = SampleID.iPhoneOff
    let loaded = await Self.loadedModels { $0.setBootError(.commandFailed) }
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    await sheets.launchAppTapped(id)

    #expect(sheets.launchAppDraft?.apps == .failed(.simulator(.commandFailed), stage: .boot))
    #expect(simulator.calls == [.fetchInventory, .boot(id), .fetchInventory])
    #expect(model.notices.isEmpty)
    #expect(model.activity.task(on: id) == nil)

    simulator.setBootError(nil)
    simulator.suspendBoots()
    let retry = Self.start { await sheets.launchAppRetryTapped() }
    await Self.waitUntil { Self.bootCount(id, in: simulator) == 2 }
    #expect(sheets.launchAppDraft?.apps == .booting)
    simulator.resumeBoots()
    await retry.value()
    #expect(sheets.launchAppDraft?.apps == .loaded([]))
  }

  @Test("켜는 중에 시트를 닫으면 켜기는 끝까지 가서 기록이 풀리고, 목록은 읽지 않는다")
  func cancelWhileBooting() async {
    let id = SampleID.iPhoneOff
    let loaded = await Self.loadedModels { $0.suspendBoots() }
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    let tap = Self.start { await sheets.launchAppTapped(id) }
    await Self.waitUntil { simulator.calls.contains(.boot(id)) }

    sheets.launchAppCancelTapped()
    #expect(sheets.launchAppDraft == nil)
    #expect(model.activity.task(on: id) == .boot)
    #expect(model.canCreateDevice)

    simulator.resumeBoots()
    await tap.value()
    #expect(model.activity.task(on: id) == nil)
    #expect(Self.device(id, in: model)?.state == .booted)
    #expect(!simulator.calls.contains(.installedApps(id)))
    #expect(sheets.launchAppDraft == nil)
    #expect(model.notices.isEmpty)
  }

  @Test("켜는 중에 닫고 다른 기기의 시트를 열면, 늦게 끝난 앞 켜기가 새 시트를 바꾸지 않는다")
  func lateBootDoesNotTouchNewDraft() async {
    let loaded = await Self.loadedModels {
      $0.setInstalledApps([InstalledAppSamples.alpha], on: SampleID.iPhoneOff)
      $0.setInstalledApps([InstalledAppSamples.beta], on: SampleID.iPhoneOn)
      $0.suspendBoot(of: SampleID.iPhoneOff)
    }
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    let first = Self.start { await sheets.launchAppTapped(SampleID.iPhoneOff) }
    await Self.waitUntil { simulator.calls.contains(.boot(SampleID.iPhoneOff)) }
    sheets.launchAppSheetDismissed()

    await sheets.launchAppTapped(SampleID.iPhoneOn)
    #expect(sheets.launchAppDraft?.apps == .loaded([InstalledAppSamples.beta]))

    simulator.resumeBoot(of: SampleID.iPhoneOff)
    await first.value()
    #expect(sheets.launchAppDraft?.deviceID == SampleID.iPhoneOn)
    #expect(sheets.launchAppDraft?.apps == .loaded([InstalledAppSamples.beta]))
    #expect(!simulator.calls.contains(.installedApps(SampleID.iPhoneOff)))
  }

  // MARK: - 겹침

  @Test("켜진 기기에서 두 번 눌러도 시트는 하나이고 목록은 한 번만 읽는다")
  func doubleTapOnBootedDevice() async {
    let loaded = await Self.loadedModels { $0.suspendInstalledApps() }
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    let first = Self.start { await sheets.launchAppTapped(SampleID.iPhoneOn) }
    let second = Self.start { await sheets.launchAppTapped(SampleID.iPhoneOn) }
    await Self.waitUntil { second.isFinished }
    simulator.resumeInstalledApps()
    await first.value()

    #expect(simulator.calls.filter { $0 == .installedApps(SampleID.iPhoneOn) }.count == 1)
    #expect(sheets.launchAppDraft?.apps == .loaded([]))
  }

  @Test("꺼진 기기에서 두 번 눌러도 한 번만 켠다")
  func doubleTapOnShutdownDevice() async {
    let id = SampleID.iPhoneOff
    let loaded = await Self.loadedModels { $0.suspendBoots() }
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    let first = Self.start { await sheets.launchAppTapped(id) }
    let second = Self.start { await sheets.launchAppTapped(id) }
    await Self.waitUntil { second.isFinished && simulator.calls.contains(.boot(id)) }
    simulator.resumeBoots()
    await first.value()

    #expect(Self.bootCount(id, in: simulator) == 1)
  }
}
