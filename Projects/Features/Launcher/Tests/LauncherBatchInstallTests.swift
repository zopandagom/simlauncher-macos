import AppBundleInterface
import AppBundleTesting
import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

/// 툴바 "선택한 기기에 앱 설치" > "파일에서 고르기…" (`selectedAppFileChosen(_:)`).
@MainActor
struct LauncherBatchInstallTests: LauncherModelTesting {
  static let picked = URL(filePath: "/Users/tester/Downloads/My App.app", directoryHint: .isDirectory)
  static let pickedZip = URL(filePath: "/Users/tester/Downloads/My App.zip", directoryHint: .notDirectory)
  static let first = ExtractedApp.fake(index: 1)
  static let sample = AppBundleInfo.sample

  static func installs(in simulator: SimulatorClientFake) -> Set<SimulatorClientFake.Call> {
    Set(simulator.calls.filter {
      if case .install = $0 {
        true
      } else {
        false
      }
    })
  }

  static func launches(in simulator: SimulatorClientFake) -> Set<SimulatorClientFake.Call> {
    Set(simulator.calls.filter {
      if case .launch = $0 {
        true
      } else {
        false
      }
    })
  }

  static func report(
    _ entries: [(VirtualDevice.ID, BatchDeviceResult)],
    appError: SimulatorError? = nil
  ) -> LauncherNotice {
    .batchFinished(BatchReport(
      action: .install,
      entries: entries.map { BatchReport.Entry(device: label($0.0), result: $0.1) },
      simulatorAppError: appError
    ))
  }

  // MARK: - 성공 흐름

  @Test("zip 은 한 번 풀고 한 번 검사해 기기마다 설치·실행하고, 푼 폴더를 한 번 지우며 모두 성공이면 알림이 없다")
  func zipExtractsOnceAndInstallsEach() async {
    let appBundle = AppBundleClientFake()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)
    model.selectionChanged([SampleID.iPhoneOn, SampleID.iPhoneOff])

    await model.selectedAppFileChosen(Self.pickedZip)

    #expect(appBundle.calls == [
      .extractApp(Self.pickedZip), .inspect(Self.first.app), .removeExtracted(Self.first),
    ])
    #expect(Self.installs(in: simulator) == [
      .install(Self.sample.location, SampleID.iPhoneOn), .install(Self.sample.location, SampleID.iPhoneOff),
    ])
    #expect(Self.launches(in: simulator) == [
      .launch(Self.sample.bundleID, SampleID.iPhoneOn), .launch(Self.sample.bundleID, SampleID.iPhoneOff),
    ])
    #expect(Self.bootCount(SampleID.iPhoneOff, in: simulator) == 1)
    #expect(Self.bootCount(SampleID.iPhoneOn, in: simulator) == 0)
    #expect(model.notices.isEmpty)
    #expect(model.activity == DeviceActivity())
  }

  @Test("최소 iOS 버전이 높은 앱이면 맞는 기기에만 설치하고, 결과 알림에 거절 이유를 넣는다")
  func rejectsOnlyOlderRuntime() async throws {
    let info = AppBundleInfo.requiring(OSVersion(major: 27))
    let appBundle = AppBundleClientFake(info: info)
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)
    let problem = try #require(info.installProblem(on: SampleRuntime.iOS26, hostArchitecture: .arm64))
    model.selectionChanged([SampleID.iPhoneIOS26, SampleID.iPhoneOn])

    await model.selectedAppFileChosen(Self.picked)

    #expect(appBundle.calls == [.inspect(Self.picked)])
    #expect(Self.installs(in: simulator) == [.install(info.location, SampleID.iPhoneOn)])
    #expect(Self.bootCount(SampleID.iPhoneIOS26, in: simulator) == 0)
    #expect(model.notices.map(\.notice) == [
      Self.report([(SampleID.iPhoneOn, .succeeded), (SampleID.iPhoneIOS26, .installFailed(.rejected(problem)))]),
    ])
    #expect(model.activity == DeviceActivity())
  }

  @Test("다른 작업 중인 기기는 이유(.deviceBusy)와 함께 건너뛰고 나머지에 설치한다")
  func skipsBusyDevice() async {
    let (model, simulator) = await Self.loadedModel { $0.suspendBoots() }
    let boot = Task { await model.bootButtonTapped(SampleID.iPhoneOff) }
    await Self.waitUntil { simulator.calls.contains(.boot(SampleID.iPhoneOff)) }
    model.selectionChanged([SampleID.iPhoneOff, SampleID.iPhoneOn])

    await model.selectedAppFileChosen(Self.picked)

    #expect(Self.installs(in: simulator) == [.install(Self.sample.location, SampleID.iPhoneOn)])
    #expect(model.notices.map(\.notice) == [
      Self.report([(SampleID.iPhoneOff, .installFailed(.deviceBusy)), (SampleID.iPhoneOn, .succeeded)]),
    ])
    #expect(model.activity.task(on: SampleID.iPhoneOff) == .boot)

    simulator.resumeBoots()
    await boot.value
    #expect(model.activity == DeviceActivity())
  }

  // MARK: - 기기별로 끝남 (비판 🔴1)

  @Test("먼저 끝난 기기는 행이 바로 풀리고, 그 기기에 새로 시작한 작업을 묶음의 끝이 지우지 않는다")
  func finishedDeviceIsReleasedAndNewTaskSurvives() async {
    let (model, simulator) = await Self.loadedModel { simulator in
      simulator.suspendBoots()
      simulator.suspendOpenURLs()
    }
    model.selectionChanged([SampleID.iPhoneOff, SampleID.iPhoneOn])
    let batch = Self.start { await model.selectedAppFileChosen(Self.picked) }
    await Self.waitUntil {
      simulator.calls.contains(.launch(Self.sample.bundleID, SampleID.iPhoneOn))
        && model.activity.task(on: SampleID.iPhoneOn) == nil
    }
    #expect(model.activity.task(on: SampleID.iPhoneOff) == .installApp)
    #expect(!batch.isFinished)

    // 풀린 기기에서 링크 열기를 시작해 멈춰 둔다.
    model.openURLButtonTapped(SampleID.iPhoneOn)
    model.openURLTextChanged(LauncherOpenURLTests.raw)
    let open = Self.start { await model.openURLConfirmTapped() }
    await Self.waitUntil { simulator.calls.contains(.openURL(LauncherOpenURLTests.link, SampleID.iPhoneOn)) }
    #expect(model.activity.task(on: SampleID.iPhoneOn) == .openURL)

    simulator.resumeBoots()
    await batch.value()
    #expect(model.activity.task(on: SampleID.iPhoneOn) == .openURL)
    #expect(model.activity.task(on: SampleID.iPhoneOff) == nil)
    #expect(model.notices.isEmpty)

    simulator.resumeOpenURLs()
    await open.value()
    #expect(model.activity == DeviceActivity())
  }

  @Test("녹화 중인 기기에도 설치·실행하고 녹화는 그대로 이어진다")
  func installsOnRecordingDevice() async {
    let (model, simulator) = await Self.loadedModel()
    let id = SampleID.iPhoneOn
    let recording = Self.start { await model.recordButtonTapped(id) }
    await Self.waitUntil { model.recordings.phase(on: id) != nil && model.recordings.phase(on: id) != .starting }
    let phase = model.recordings.phase(on: id)
    model.selectionChanged([id, SampleID.iPhoneOff])

    await model.selectedAppFileChosen(Self.picked)

    #expect(Self.launches(in: simulator) == [
      .launch(Self.sample.bundleID, id), .launch(Self.sample.bundleID, SampleID.iPhoneOff),
    ])
    #expect(model.recordings.phase(on: id) == phase)
    #expect(model.notices.isEmpty)

    model.recordingStopTapped(id)
    await recording.value()
  }

  // MARK: - 한 대·없음

  @Test("고른 기기가 한 대면 행 메뉴와 같다: 검사 실패는 기존 설치 실패 알림 하나다")
  func singleSelectionMatchesRow() async {
    let selected = AppBundleClientFake()
    selected.setInspectError(.ipaFile)
    let (model, _) = await Self.loadedModel(appBundle: selected)
    model.selectionChanged([SampleID.iPhoneOn])
    await model.selectedAppFileChosen(Self.picked)

    let row = AppBundleClientFake()
    row.setInspectError(.ipaFile)
    let (rowModel, _) = await Self.loadedModel(appBundle: row)
    await rowModel.appFileSelected(Self.picked, for: SampleID.iPhoneOn)

    #expect(model.notices.map(\.notice) == [.installFailed(Self.label(SampleID.iPhoneOn), .bundle(.ipaFile))])
    #expect(model.notices.map(\.notice) == rowModel.notices.map(\.notice))
    #expect(selected.calls == row.calls)
  }

  @Test("고른 한 대가 다른 작업 중이면 행과 같이 알림 없이 끝난다")
  func singleBusySelectionIsSilent() async {
    let appBundle = AppBundleClientFake()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle) { $0.suspendBoots() }
    let boot = Task { await model.bootButtonTapped(SampleID.iPhoneOff) }
    await Self.waitUntil { simulator.calls.contains(.boot(SampleID.iPhoneOff)) }
    model.selectionChanged([SampleID.iPhoneOff])

    await model.selectedAppFileChosen(Self.picked)

    #expect(appBundle.calls.isEmpty)
    #expect(model.notices.isEmpty)
    simulator.resumeBoots()
    await boot.value
  }

  @Test("고른 기기가 없으면 아무것도 하지 않는다")
  func noSelectionDoesNothing() async {
    let appBundle = AppBundleClientFake()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)

    await model.selectedAppFileChosen(Self.picked)

    #expect(appBundle.calls.isEmpty)
    #expect(simulator.calls == [.fetchInventory])
    #expect(model.notices.isEmpty)
  }

  // MARK: - 실패

  @Test("Simulator 앱을 열지 못하면 설치는 계속하고 결과 알림에 그 에러를 한 번만 넣는다")
  func openAppFailureAppearsOnce() async {
    let (model, simulator) = await Self.loadedModel { $0.setOpenAppError(.simulatorAppNotFound) }
    model.selectionChanged([SampleID.iPhoneOn, SampleID.iPhoneOff])

    await model.selectedAppFileChosen(Self.picked)

    #expect(Self.launches(in: simulator).count == 2)
    #expect(model.notices.map(\.notice) == [
      Self.report([(SampleID.iPhoneOff, .succeeded), (SampleID.iPhoneOn, .succeeded)], appError: .simulatorAppNotFound),
    ])
  }

  @Test("검사가 실패하면 공통 단계 실패 알림 하나이고 어느 기기에도 설치하지 않는다")
  func inspectFailureIsOneNotice() async {
    let appBundle = AppBundleClientFake()
    appBundle.setInspectError(.macOSApp)
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)
    model.selectionChanged([SampleID.iPhoneOn, SampleID.iPhoneOff])

    await model.selectedAppFileChosen(Self.picked)

    #expect(model.notices.map(\.notice) == [
      .batchInstallFailed([Self.label(SampleID.iPhoneOff), Self.label(SampleID.iPhoneOn)], .bundle(.macOSApp)),
    ])
    #expect(simulator.calls == [.fetchInventory])
    #expect(model.activity == DeviceActivity())
  }

  @Test("zip 을 풀지 못하면 공통 단계 실패 알림 하나이고 검사·설치하지 않는다")
  func extractFailureIsOneNotice() async {
    let appBundle = AppBundleClientFake()
    appBundle.setExtractError(.zipUnreadable)
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)
    model.selectionChanged([SampleID.iPhoneOn, SampleID.iPhoneOff])

    await model.selectedAppFileChosen(Self.pickedZip)

    #expect(model.notices.map(\.notice) == [
      .batchInstallFailed([Self.label(SampleID.iPhoneOff), Self.label(SampleID.iPhoneOn)], .bundle(.zipUnreadable)),
    ])
    #expect(appBundle.calls == [.extractApp(Self.pickedZip)])
    #expect(simulator.calls == [.fetchInventory])
    #expect(model.activity == DeviceActivity())
  }
}
