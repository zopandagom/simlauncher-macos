import AppBundleTesting
import AppLogTesting
import Core
import DownloadTesting
import SimulatorInterface
import SimulatorTesting
import Testing
import WorkspaceTesting
@testable import LauncherFeature

/// 링크 열기 (이어서): 명령 실패와 진행 중. 타입 본문 길이 한도 때문에 나눈 같은 스위트의 나머지다.
extension LauncherOpenURLTests {
  // MARK: - 명령 실패

  @Test("켜기가 실패하면 알리고 링크를 열지 않으며, 다시 읽고 진행 중을 푼다")
  func bootFailure() async {
    let loaded = await Self.open(Self.raw, on: SampleID.iPhoneOff) { $0.setBootError(.commandFailed) }
    let model = loaded.model
    let simulator = loaded.simulator

    #expect(model.notices.map(\.notice) == [.bootFailed(Self.label(SampleID.iPhoneOff), .commandFailed)])
    #expect(simulator.calls == [.fetchInventory, .boot(SampleID.iPhoneOff), .fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("Simulator 앱을 열지 못해도 알리고 링크는 연다 (켜진 기기도 앱을 연다)", arguments: [
    SampleID.iPhoneOff, SampleID.iPhoneOn,
  ])
  func openAppFailureContinues(id: VirtualDevice.ID) async {
    let loaded = await Self.open(Self.raw, on: id) { $0.setOpenAppError(.simulatorAppNotFound) }
    let model = loaded.model
    let simulator = loaded.simulator

    #expect(model.notices.map(\.notice) == [.openAppFailed(Self.label(id), .simulatorAppNotFound)])
    #expect(simulator.calls.suffix(3) == [.openSimulatorApp, .openURL(Self.link, id), .fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("링크 열기가 실패하면 누른 시점의 기기로 원인을 알리고 다시 읽는다", arguments: [
    SimulatorError.urlNotHandled, .invalidURL, .deviceNotBooted, .commandFailed,
  ])
  func openURLFailure(error: SimulatorError) async {
    let loaded = await Self.open(Self.raw, on: SampleID.iPhoneOn) { $0.setOpenURLError(error) }
    let model = loaded.model
    let simulator = loaded.simulator

    #expect(model.notices.map(\.notice) == [.openURLFailed(Self.label(SampleID.iPhoneOn), .simulator(error))])
    #expect(simulator.calls.suffix(2) == [.openURL(Self.link, SampleID.iPhoneOn), .fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
  }

  // MARK: - 진행 중

  @Test("링크를 여는 동안 그 기기는 링크 열기 중이고 설치·켜기를 받지 않으며, 다른 기기 설치는 되고, 끝나면 풀린다")
  func openingBlocksSameDeviceOnly() async {
    let appBundle = AppBundleClientFake()
    let loaded = await Self.loadedModels(appBundle: appBundle) { $0.suspendOpenURLs() }
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    let id = SampleID.iPhoneOff
    sheets.openURLTapped(id)
    sheets.openURLTextChanged(Self.raw)
    let open = Task { await sheets.openURLConfirmTapped() }
    await Self.waitUntil { simulator.calls.contains(.openURL(Self.link, id)) }

    #expect(model.activity.task(on: id) == .openURL)
    let calls = simulator.calls.count
    let attempts = Self.start {
      await model.appFileSelected(LauncherInstallTests.picked, for: id)
      await model.bootButtonTapped(id)
    }
    await Self.waitUntil { attempts.isFinished || simulator.calls.count > calls }
    #expect(simulator.calls.count == calls)
    #expect(appBundle.calls.isEmpty)
    sheets.openURLTapped(id)
    #expect(sheets.openURLDraft == nil)

    await model.appFileSelected(LauncherInstallTests.picked, for: SampleID.iPhoneOn)
    #expect(simulator.calls.contains(.launch(LauncherInstallTests.sample.bundleID, SampleID.iPhoneOn)))
    #expect(model.activity.task(on: id) == .openURL)

    simulator.resumeOpenURLs()
    await open.value
    #expect(model.activity.task(on: id) == nil)
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(model.notices.isEmpty)
  }

  @Test("확인을 연달아 눌러도 링크는 한 번만 연다")
  func doubleConfirmOpensOnce() async {
    let loaded = await Self.loadedModels()
    let model = loaded.model
    let sheets = loaded.sheets
    let simulator = loaded.simulator
    sheets.openURLTapped(SampleID.iPhoneOn)
    sheets.openURLTextChanged(Self.raw)

    let first = Task { await sheets.openURLConfirmTapped() }
    let second = Task { await sheets.openURLConfirmTapped() }
    await first.value
    await second.value

    #expect(simulator.calls.filter { $0 == .openURL(Self.link, SampleID.iPhoneOn) }.count == 1)
    #expect(model.notices.isEmpty)
  }
}
