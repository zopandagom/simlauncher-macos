import AppBundleTesting
import Core
import DownloadTesting
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing
import WorkspaceInterface
import WorkspaceTesting
@testable import LauncherFeature

/// 녹화 Model 테스트가 함께 쓰는 도움 함수 (`LauncherRecordingTests`·`LauncherRecordingStopTests`).
@MainActor
protocol LauncherRecordingTesting: LauncherModelTesting {}

@MainActor
extension LauncherRecordingTesting {
  /// "녹화" 를 누른 시각이자 시작 신호 시각 (Model 의 `now` 를 고정한다).
  static var pressedAt: Date {
    Date(timeIntervalSince1970: 1_793_000_000)
  }

  /// 켜진 iPhone 17 Pro (iOS 27.0) 를 고정 시각에 녹화한 파일 이름.
  static var name: RecordingFileName {
    RecordingFileName(deviceName: "iPhone 17 Pro", runtimeName: "iOS 27.0", startedAt: pressedAt, timeZone: .current)
  }

  /// Workspace Fake 가 `name` 의 attempt 번호로 예약하는 파일.
  static func reserved(_ attempt: Int = 1) -> URL {
    WorkspaceClientFake.moviesFolder.appending(
      path: self.name.fileName(attempt: attempt)!,
      directoryHint: .notDirectory
    )
  }

  static func model(
    workspace: WorkspaceClientFake = WorkspaceClientFake(),
    _ configure: (SimulatorClientFake) -> Void = { _ in }
  ) async -> (LauncherModel, SimulatorClientFake) {
    await loadedModel(workspace: workspace, now: self.pressedAt, configure)
  }

  static func fetchCount(in simulator: SimulatorClientFake) -> Int {
    simulator.calls.filter { $0 == .fetchInventory }.count
  }

  static func recordCalls(in simulator: SimulatorClientFake) -> [SimulatorClientFake.Call] {
    simulator.calls.filter {
      if case .recordVideo = $0 {
        true
      } else {
        false
      }
    }
  }

  static func revealCount(in workspace: WorkspaceClientFake) -> Int {
    workspace.calls.filter {
      if case .revealInFinder = $0 {
        true
      } else {
        false
      }
    }.count
  }

  /// 켜진 기기의 녹화를 시작하고 녹화 중(시작 신호를 받음)이 될 때까지 기다린다. 돌려준 Task 는 녹화가 끝날 때 끝난다.
  static func startRecording(_ id: VirtualDevice.ID, in model: LauncherModel) async -> Task<Void, Never> {
    let task = Task { await model.recordButtonTapped(id) }
    await Self.waitUntil { model.recordings.phase(on: id) == .recording(startedAt: Self.pressedAt) }
    return task
  }
}

/// 녹화 시작·중지·겹침·막힘·시작 실패.
@MainActor
struct LauncherRecordingTests: LauncherRecordingTesting {
  // MARK: - 성공

  @Test("녹화를 누르면 시작 중이고, 시작 신호를 받으면 주입한 시각부터 녹화 중이다")
  func startingThenRecording() async {
    let workspace = WorkspaceClientFake()
    let (model, simulator) = await Self.model(workspace: workspace) { $0.suspendRecordings() }
    let id = SampleID.iPhoneOn

    let tap = Task { await model.recordButtonTapped(id) }
    await Self.waitUntil { Self.recordCalls(in: simulator).count == 1 }
    #expect(model.recordings.phase(on: id) == .starting)
    #expect(Self.recordCalls(in: simulator) == [.recordVideo(id, Self.reserved())])
    #expect(workspace.calls == [.reserveRecordingFile(stem: Self.name.stem)])

    simulator.resumeRecordings()
    await Self.waitUntil { model.recordings.phase(on: id) == .recording(startedAt: Self.pressedAt) }

    model.recordingStopTapped(id)
    await tap.value
  }

  @Test("중지하면 저장 중이 되고, 끝나면 Finder 에서 보이며 알림·다시 읽기 없이 녹화 상태가 비워진다")
  func stopSavesAndReveals() async {
    let workspace = WorkspaceClientFake()
    let (model, simulator) = await Self.model(workspace: workspace)
    let id = SampleID.iPhoneOn
    let tap = await Self.startRecording(id, in: model)
    let fetches = Self.fetchCount(in: simulator)

    model.recordingStopTapped(id)
    #expect(model.recordings.phase(on: id) == .stopping(startedAt: Self.pressedAt, reason: .user))

    await tap.value
    let file = Self.reserved()
    #expect(workspace.calls == [.reserveRecordingFile(stem: Self.name.stem), .revealInFinder(file)])
    #expect(workspace.reservedFiles == [file])
    #expect(model.notices.isEmpty)
    #expect(Self.fetchCount(in: simulator) == fetches)
    #expect(model.recordings == RecordingActivity())
  }

  @Test("두 기기를 따로 녹화하고, 한 기기를 멈춰도 다른 기기는 녹화 중이다")
  func twoDevicesIndependently() async {
    let workspace = WorkspaceClientFake()
    let inventory = Self.inventory(SampleID.iPadOff, state: .booted)
    let (model, simulator) = await Self.model(workspace: workspace) { $0.setInventory(inventory) }
    let phone = await Self.startRecording(SampleID.iPhoneOn, in: model)
    let pad = await Self.startRecording(SampleID.iPadOff, in: model)
    #expect(Self.recordCalls(in: simulator).count == 2)

    model.recordingStopTapped(SampleID.iPhoneOn)
    await phone.value
    #expect(model.recordings.phase(on: SampleID.iPadOff) == .recording(startedAt: Self.pressedAt))
    #expect(Self.revealCount(in: workspace) == 1)

    model.recordingStopTapped(SampleID.iPadOff)
    await pad.value
    #expect(Self.revealCount(in: workspace) == 2)
    #expect(!model.recordings.isActive)
    #expect(model.notices.isEmpty)
  }

  // MARK: - 겹침

  @Test("녹화 중 같은 기기를 다시 누르면 바로 끝나고 recordVideo 는 한 번이다")
  func secondTapIsIgnored() async {
    let workspace = WorkspaceClientFake()
    let (model, simulator) = await Self.model(workspace: workspace)
    let id = SampleID.iPhoneOn
    let tap = await Self.startRecording(id, in: model)

    let again = Self.start { await model.recordButtonTapped(id) }
    await Self.waitUntil { again.isFinished || Self.recordCalls(in: simulator).count > 1 }
    #expect(again.isFinished)
    #expect(Self.recordCalls(in: simulator).count == 1)
    #expect(workspace.calls == [.reserveRecordingFile(stem: Self.name.stem)])

    model.recordingStopTapped(id)
    await tap.value
  }

  @Test("중지를 연타해도 이유는 그대로이고 한 번만 저장한다")
  func secondStopIsIgnored() async {
    let workspace = WorkspaceClientFake()
    let (model, _) = await Self.model(workspace: workspace)
    let id = SampleID.iPhoneOn
    let tap = await Self.startRecording(id, in: model)

    model.recordingStopTapped(id)
    model.recordingStopTapped(id)
    #expect(model.recordings.phase(on: id) == .stopping(startedAt: Self.pressedAt, reason: .user))

    await tap.value
    #expect(Self.revealCount(in: workspace) == 1)
    #expect(model.notices.isEmpty)
  }

  @Test("녹화 중이 아닌 기기의 중지는 아무것도 바꾸지 않는다")
  func stopWithoutRecordingDoesNothing() async {
    let (model, _) = await Self.model()

    model.recordingStopTapped(SampleID.iPhoneOn)

    #expect(model.recordings == RecordingActivity())
  }

  @Test("녹화 중에도 같은 기기에 앱 설치·링크 열기·스크린샷을 하고, 녹화는 이어진다")
  func installOpenURLScreenshotDuringRecording() async {
    let workspace = WorkspaceClientFake()
    let (model, simulator) = await Self.model(workspace: workspace)
    let id = SampleID.iPhoneOn
    let tap = await Self.startRecording(id, in: model)

    await model.appFileSelected(LauncherInstallTests.picked, for: id)
    model.openURLButtonTapped(id)
    model.openURLTextChanged(LauncherOpenURLTests.raw)
    await model.openURLConfirmTapped()
    await model.screenshotButtonTapped(id)

    #expect(LauncherInstallTests.installCount(in: simulator) == 1)
    #expect(simulator.calls.contains(.openURL(LauncherOpenURLTests.link, id)))
    #expect(simulator.calls.contains {
      if case .screenshot(id, _) = $0 {
        true
      } else {
        false
      }
    })
    #expect(model.recordings.phase(on: id) == .recording(startedAt: Self.pressedAt))
    #expect(model.notices.isEmpty)

    model.recordingStopTapped(id)
    await tap.value
  }

  // MARK: - 막힘

  @Test(
    "꺼진·쓸 수 없는·목록에 없는 기기는 아무것도 부르지 않는다",
    arguments: [
      SampleID.iPhoneOff,
      SampleID.unavailableIPhone,
      VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF"),
    ]
  )
  func blockedDeviceCallsNothing(id: VirtualDevice.ID) async {
    let workspace = WorkspaceClientFake()
    let (model, simulator) = await Self.model(workspace: workspace)
    let before = simulator.calls

    await model.recordButtonTapped(id)

    #expect(workspace.calls.isEmpty)
    #expect(simulator.calls == before)
    #expect(model.recordings == RecordingActivity())
  }

  @Test("끄는 중인(기기 작업 끄기) 기기는 녹화를 시작하지 않는다")
  func blockedDuringShutdown() async {
    let workspace = WorkspaceClientFake()
    let (model, simulator) = await Self.model(workspace: workspace)
    let id = SampleID.iPhoneOn
    simulator.setDelay(.milliseconds(200))
    let shutdown = Task { await model.shutdownButtonTapped(id) }
    await Self.waitUntil { model.activity.task(on: id) == .shutdown }

    let tap = Self.start { await model.recordButtonTapped(id) }
    await Self.waitUntil { tap.isFinished || !workspace.calls.isEmpty }
    #expect(tap.isFinished)
    #expect(workspace.calls.isEmpty)
    #expect(Self.recordCalls(in: simulator).isEmpty)
    await shutdown.value
  }

  @Test("녹화 중이면 끄기를 시작하지 않는다")
  func shutdownBlockedWhileRecording() async {
    let (model, simulator) = await Self.model()
    let id = SampleID.iPhoneOn
    let tap = await Self.startRecording(id, in: model)

    await model.shutdownButtonTapped(id)

    #expect(!simulator.calls.contains(.shutdown(id)))
    #expect(model.activity.task(on: id) == nil)
    model.recordingStopTapped(id)
    await tap.value
  }

  @Test("녹화가 끝나기 전(저장 중)이면 목록에서 꺼진 기기라도 삭제·초기화 확인을 띄우지 않고 확인한 삭제도 하지 않는다")
  func deleteEraseBlockedWhileRecording() async {
    let workspace = WorkspaceClientFake()
    workspace.suspendReserves()
    let (model, simulator) = await Self.model(workspace: workspace)
    let id = SampleID.iPhoneOn
    let tap = Task { await model.recordButtonTapped(id) }
    await Self.waitUntil { !workspace.calls.isEmpty }
    // 예약을 기다리는 동안 기기가 꺼진 목록을 읽어 녹화가 저장 중이 된다 (흐름은 예약에 멈춰 끝나지 않는다).
    simulator.setInventory(Self.inventory(id, state: .shutdown))
    await model.refreshButtonTapped()
    #expect(model.recordings.phase(on: id) == .stopping(startedAt: nil, reason: .deviceStopped))

    model.deleteButtonTapped(id)
    #expect(model.pendingConfirmation == nil)
    model.eraseButtonTapped(id)
    #expect(model.pendingConfirmation == nil)
    await model.confirmationConfirmed(DeviceConfirmation(action: .delete, deviceID: id, device: Self.label(id)))
    #expect(!simulator.calls.contains(.delete(id)))
    #expect(model.activity.task(on: id) == nil)

    workspace.resumeReserves()
    await tap.value
    // 녹화가 끝나면 다시 삭제 확인을 띄울 수 있다.
    model.deleteButtonTapped(id)
    #expect(model.pendingConfirmation?.deviceID == id)
  }

  @Test("목록을 읽기 전에는 아무것도 부르지 않는다")
  func beforeLoadCallsNothing() async {
    let workspace = WorkspaceClientFake()
    let simulator = SimulatorClientFake(inventory: .sample)
    let model = LauncherModel(
      simulator: simulator,
      appBundle: AppBundleClientFake(),
      download: DownloadClientFake(),
      workspace: workspace
    )

    await model.recordButtonTapped(SampleID.iPhoneOn)

    #expect(workspace.calls.isEmpty)
    #expect(simulator.calls.isEmpty)
  }

  // MARK: - 시작 실패

  @Test("예약 실패: 동영상 폴더 알림, 녹화 명령·지우기 없음, 다시 읽지 않고 녹화 상태가 풀린다")
  func reserveFailure() async {
    let workspace = WorkspaceClientFake()
    workspace.setReserveError(.folderUnavailable)
    let (model, simulator) = await Self.model(workspace: workspace)
    let id = SampleID.iPhoneOn
    let fetches = Self.fetchCount(in: simulator)

    await model.recordButtonTapped(id)

    #expect(workspace.calls == [.reserveRecordingFile(stem: Self.name.stem)])
    #expect(Self.recordCalls(in: simulator).isEmpty)
    #expect(model.notices.map(\.notice) == [.recordingFailed(Self.label(id), .workspace(.folderUnavailable))])
    #expect(Self.fetchCount(in: simulator) == fetches)
    #expect(!model.recordings.isActive)
  }

  @Test("시작 실패(다른 녹화가 있음): 예약 파일을 지우고 알림 뒤 한 번 다시 읽는다")
  func startFailureInProgress() async {
    let workspace = WorkspaceClientFake()
    let (model, simulator) = await Self.model(workspace: workspace) { $0.setRecordingStartError(.recordingInProgress) }
    let id = SampleID.iPhoneOn
    let fetches = Self.fetchCount(in: simulator)

    await model.recordButtonTapped(id)

    let file = Self.reserved()
    #expect(Self.recordCalls(in: simulator) == [.recordVideo(id, file)])
    #expect(workspace.calls == [.reserveRecordingFile(stem: Self.name.stem), .removeReservedFile(file)])
    #expect(model.notices.map(\.notice) == [.recordingFailed(Self.label(id), .simulator(.recordingInProgress))])
    #expect(Self.fetchCount(in: simulator) == fetches + 1)
    #expect(!model.recordings.isActive)
  }
}
