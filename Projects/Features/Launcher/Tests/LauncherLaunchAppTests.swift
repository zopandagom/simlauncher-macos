import AppLogInterface
import AppLogTesting
import Core
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

/// "앱 실행…" 시트에서 고른 앱의 실행: 대상 재확인·진행 기록·켜기·로그 받기와 함께 실행·실패 알림. 두 Model 은 App 처럼 잇는다.
@MainActor
struct LauncherLaunchAppTests: LauncherModelTesting {
  @Test("실행하면 시트가 닫히고 Simulator 앱을 연 뒤 로그 받기와 함께 실행해, 그 기기의 로그 보기를 누를 수 있다")
  func launchCreatesLogSession() async {
    let appLog = AppLogClientFake()
    let id = SampleID.iPhoneOn
    let loaded = await Self.loadedModels(appLog: appLog) {
      $0.setInstalledApps([InstalledAppSamples.alpha], on: id)
    }
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    await sheets.launchAppTapped(id)

    await sheets.launchAppConfirmTapped()

    #expect(sheets.launchAppDraft == nil)
    // 설치가 아니라 같은 앱의 앞 세션을 미리 알리지 않는다 (`replacementWillStart` 없음).
    #expect(appLog.calls == [.launchIOSApp(InstalledAppSamples.alpha.bundleID, id)])
    let session = appLog.sessions.first
    #expect(session?.appName == "Alpha")
    #expect(session?.deviceName == Self.device(id, in: model)?.name)
    #expect(simulator.calls == [.fetchInventory, .installedApps(id), .openSimulatorApp, .fetchInventory])
    await Self.waitUntil { model.logDevices == [id] }
    #expect(model.notices.isEmpty)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("실행하는 동안 그 기기는 앱 실행 중이고 다른 작업을 받지 않으며 스크린샷은 되고, 끝나면 풀린다")
  func launchingMarksDevice() async throws {
    let (stream, gate) = AsyncStream<Void>.makeStream()
    let appLog = AppLogClientFake { _, _ async throws(AppLogLaunchError) in
      for await _ in stream {
        break
      }
    }
    let id = SampleID.iPhoneOn
    let loaded = await Self.loadedModels(appLog: appLog) {
      $0.setInstalledApps([InstalledAppSamples.alpha], on: id)
    }
    let model = loaded.model
    let sheets = loaded.sheets
    await sheets.launchAppTapped(id)
    let launch = Self.start { await sheets.launchAppConfirmTapped() }
    await Self.waitUntil { !appLog.calls.isEmpty }

    #expect(model.activity.task(on: id) == .launchApp)
    #expect(try model.screenshots.canStart(on: #require(Self.device(id, in: model)), during: .launchApp))
    await sheets.launchAppTapped(id)
    #expect(sheets.launchAppDraft == nil)

    gate.yield()
    await launch.value()
    #expect(model.activity.task(on: id) == nil)
  }

  @Test("시트를 연 뒤 기기가 꺼졌으면 켜고 Simulator 앱을 연 뒤 실행한다")
  func bootsDeviceShutDownAfterSheet() async {
    let id = SampleID.iPhoneOn
    let loaded = await Self.loadedModels {
      $0.setInstalledApps([InstalledAppSamples.alpha], on: id)
    }
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    await sheets.launchAppTapped(id)
    simulator.setInventory(Self.inventory(id, state: .shutdown))
    await model.refreshButtonTapped()

    await sheets.launchAppConfirmTapped()

    #expect(simulator.calls.suffix(4) == [
      .boot(id), .openSimulatorApp, .launch(InstalledAppSamples.alpha.bundleID, id), .fetchInventory,
    ])
    #expect(model.notices.isEmpty)
  }

  @Test("실행이 실패하면 누른 시점의 기기로 원인을 알리고 다시 읽는다", arguments: [
    SimulatorError.appNotInstalled, .appLaunchFailed, .deviceNotBooted, .commandFailed,
  ])
  func launchFailure(error: SimulatorError) async {
    let id = SampleID.iPhoneOn
    let loaded = await Self.loadedModels {
      $0.setInstalledApps([InstalledAppSamples.alpha], on: id)
      $0.setLaunchError(error)
    }
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    await sheets.launchAppTapped(id)
    await sheets.launchAppConfirmTapped()

    #expect(model.notices.map(\.notice) == [.installedAppLaunchFailed(Self.label(id), .simulator(error))])
    #expect(simulator.calls.suffix(2) == [.launch(InstalledAppSamples.alpha.bundleID, id), .fetchInventory])
    #expect(model.logDevices.isEmpty)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("켜기가 실패하면 켜기 실패를 알리고 실행하지 않는다")
  func bootFailureStopsLaunch() async {
    let id = SampleID.iPhoneOn
    let loaded = await Self.loadedModels {
      $0.setInstalledApps([InstalledAppSamples.alpha], on: id)
      $0.setBootError(.commandFailed)
    }
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    await sheets.launchAppTapped(id)
    simulator.setInventory(Self.inventory(id, state: .shutdown))
    await model.refreshButtonTapped()

    await sheets.launchAppConfirmTapped()

    #expect(model.notices.map(\.notice) == [.bootFailed(Self.label(id), .commandFailed)])
    #expect(!simulator.calls.contains(.launch(InstalledAppSamples.alpha.bundleID, id)))
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("Simulator 앱을 열지 못해도 알리고 실행은 한다")
  func openAppFailureContinues() async {
    let id = SampleID.iPhoneOn
    let loaded = await Self.loadedModels {
      $0.setInstalledApps([InstalledAppSamples.alpha], on: id)
      $0.setOpenAppError(.simulatorAppNotFound)
    }
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    await sheets.launchAppTapped(id)
    await sheets.launchAppConfirmTapped()

    #expect(model.notices.map(\.notice) == [.openAppFailed(Self.label(id), .simulatorAppNotFound)])
    #expect(simulator.calls.contains(.launch(InstalledAppSamples.alpha.bundleID, id)))
  }

  @Test("실행 시점에 기기가 목록에 없으면 찾을 수 없다고 알리고, 켜는 중이면 상태가 바뀌는 중이라고 알리며 명령을 실행하지 않는다")
  func targetRecheckedBeforeLaunch() async {
    let id = SampleID.iPhoneOn
    let loaded = await Self.loadedModels {
      $0.setInstalledApps([InstalledAppSamples.alpha], on: id)
    }
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    await sheets.launchAppTapped(id)
    simulator.setInventory(Self.inventory(removing: id))
    await model.refreshButtonTapped()
    await sheets.launchAppConfirmTapped()

    simulator.setInventory(Self.inventory(id, state: .booting))
    await model.refreshButtonTapped()
    await model.launchAppRequested(Self.request(on: id))

    #expect(model.notices.map(\.notice) == [
      .installedAppLaunchFailed(Self.label(id), .simulator(.deviceNotFound)),
      .installedAppLaunchFailed(Self.label(id), .deviceNotReady(.stateChanging)),
    ])
    #expect(!simulator.calls.contains(.openSimulatorApp))
    #expect(!simulator.calls.contains {
      if case .launch = $0 {
        true
      } else {
        false
      }
    })
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("같은 기기에서 다른 작업이 진행 중이면 알림 없이 아무것도 하지 않는다")
  func busyDeviceIgnoresRequest() async {
    let id = SampleID.iPhoneOff
    let loaded = await Self.loadedModels { $0.suspendBoots() }
    let model = loaded.model
    let simulator = loaded.simulator
    let boot = Self.start { await model.bootButtonTapped(id) }
    await Self.waitUntil { simulator.calls.contains(.boot(id)) }

    await model.launchAppRequested(Self.request(on: id))

    #expect(model.activity.task(on: id) == .boot)
    #expect(model.notices.isEmpty)
    #expect(!simulator.calls.contains(.launch(InstalledAppSamples.alpha.bundleID, id)))
    simulator.resumeBoots()
    await boot.value()
  }

  @Test("실행을 연달아 눌러도 한 번만 실행하고, 고르지 않았으면 실행하지 않는다")
  func doubleConfirmLaunchesOnce() async {
    let id = SampleID.iPhoneOn
    let loaded = await Self.loadedModels {
      $0.setInstalledApps(InstalledAppSamples.two, on: id)
    }
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    await sheets.launchAppTapped(id)
    await sheets.launchAppConfirmTapped()
    #expect(sheets.launchAppDraft != nil)
    #expect(!simulator.calls.contains {
      if case .launch = $0 {
        true
      } else {
        false
      }
    })

    sheets.launchAppSelectionChanged(InstalledAppSamples.beta.bundleID)
    let first = Self.start { await sheets.launchAppConfirmTapped() }
    let second = Self.start { await sheets.launchAppConfirmTapped() }
    await first.value()
    await second.value()

    #expect(simulator.calls.filter { $0 == .launch(InstalledAppSamples.beta.bundleID, id) }.count == 1)
  }
}

extension LauncherLaunchAppTests {
  /// 시트를 거치지 않은 실행 요청 (`alpha`, 누른 시점의 기기 라벨).
  static func request(on id: VirtualDevice.ID) -> LaunchAppRequest {
    LaunchAppRequest(deviceID: id, device: label(id), app: InstalledAppSamples.alpha)
  }
}
