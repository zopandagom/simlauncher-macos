import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing
import WorkspaceInterface
import WorkspaceTesting
@testable import LauncherFeature

/// 녹화를 멈춘 뒤 결과(시작 신호 전 멈춤 포함), 기기 꺼짐 자동 멈춤, 앱 종료.
@MainActor
struct LauncherRecordingStopTests: LauncherRecordingTesting {
  // MARK: - 시작 신호 전 멈춤

  @Test("시작 신호 전에 중지하면 알림 없이 빈 예약 파일을 지운다")
  func stopBeforeSignalRemovesReservedFile() async {
    let workspace = WorkspaceClientFake()
    let (model, simulator) = await Self.model(workspace: workspace) { $0.setRecordingSignalsStart(false) }
    let id = SampleID.iPhoneOn
    let tap = Task { await model.recordButtonTapped(id) }
    await Self.waitUntil { Self.recordCalls(in: simulator).count == 1 }
    #expect(model.recordings.phase(on: id) == .starting)
    let fetches = Self.fetchCount(in: simulator)

    model.recordingStopTapped(id)
    #expect(model.recordings.phase(on: id) == .stopping(startedAt: nil, reason: .user))
    await tap.value

    let file = Self.reserved()
    #expect(workspace.calls == [.reserveRecordingFile(stem: Self.name.stem), .removeReservedFile(file)])
    #expect(workspace.reservedFiles.isEmpty)
    #expect(model.notices.isEmpty)
    #expect(Self.fetchCount(in: simulator) == fetches)
    #expect(!model.recordings.isActive)
  }

  @Test("예약 중에 중지하면 녹화 명령은 시작하지 않고(시작 전 취소) 알림 없이 빈 예약 파일을 지운다")
  func stopDuringReserve() async {
    let workspace = WorkspaceClientFake()
    workspace.suspendReserves()
    let (model, simulator) = await Self.model(workspace: workspace)
    let id = SampleID.iPhoneOn
    let tap = Task { await model.recordButtonTapped(id) }
    await Self.waitUntil { !workspace.calls.isEmpty }

    model.recordingStopTapped(id)
    workspace.resumeReserves()
    await tap.value

    let file = Self.reserved()
    #expect(workspace.calls == [.reserveRecordingFile(stem: Self.name.stem), .removeReservedFile(file)])
    #expect(model.notices.isEmpty)
    #expect(!model.recordings.isActive)
    #expect(Self.recordCalls(in: simulator).count == 1)
  }

  // MARK: - 멈춘 뒤 결과

  @Test("멈춘 뒤 저장된 화면이 없음: 빈 예약 파일을 지우고 알림 뒤 다시 읽는다")
  func emptyAfterStop() async {
    let workspace = WorkspaceClientFake()
    let (model, simulator) = await Self.model(workspace: workspace) {
      $0.setRecordingStopOutcome(.failure(.recordingEmpty))
    }
    let id = SampleID.iPhoneOn
    let tap = await Self.startRecording(id, in: model)
    let fetches = Self.fetchCount(in: simulator)

    model.recordingStopTapped(id)
    await tap.value

    let file = Self.reserved()
    #expect(workspace.calls == [.reserveRecordingFile(stem: Self.name.stem), .removeReservedFile(file)])
    #expect(model.notices.map(\.notice) == [.recordingFailed(Self.label(id), .simulator(.recordingEmpty))])
    #expect(Self.fetchCount(in: simulator) == fetches + 1)
  }

  @Test("멈춘 뒤 저장을 마치지 못함: 예약 파일을 지우지 않고 알림 뒤 다시 읽는다")
  func unfinishedAfterStopKeepsFile() async {
    let workspace = WorkspaceClientFake()
    let (model, simulator) = await Self.model(workspace: workspace) {
      $0.setRecordingStopOutcome(.failure(.recordingUnfinished))
    }
    let id = SampleID.iPhoneOn
    let tap = await Self.startRecording(id, in: model)
    let fetches = Self.fetchCount(in: simulator)

    model.recordingStopTapped(id)
    await tap.value

    let file = Self.reserved()
    #expect(workspace.calls == [.reserveRecordingFile(stem: Self.name.stem)])
    #expect(workspace.reservedFiles == [file])
    #expect(model.notices.map(\.notice) == [.recordingFailed(Self.label(id), .simulator(.recordingUnfinished))])
    #expect(Self.fetchCount(in: simulator) == fetches + 1)
  }

  @Test("녹화가 중간에 끝났지만 화면이 남음: 지우지 않고 Finder 에서 보이며 중간에 끝남 알림 뒤 다시 읽는다")
  func savedAfterFailureRevealsAndKeepsFile() async {
    let workspace = WorkspaceClientFake()
    let (model, simulator) = await Self.model(workspace: workspace) {
      $0.setRecordingStopOutcome(.success(.savedAfterFailure))
    }
    let id = SampleID.iPhoneOn
    let tap = await Self.startRecording(id, in: model)
    let fetches = Self.fetchCount(in: simulator)

    model.recordingStopTapped(id)
    await tap.value

    let file = Self.reserved()
    #expect(workspace.calls == [.reserveRecordingFile(stem: Self.name.stem), .revealInFinder(file)])
    #expect(workspace.reservedFiles == [file])
    #expect(model.notices.map(\.notice) == [.recordingInterrupted(Self.label(id))])
    #expect(Self.fetchCount(in: simulator) == fetches + 1)
  }

  @Test("Finder 실패: 저장한 파일은 지우지 않고 Finder 실패 알림만 띄운다")
  func revealFailure() async {
    let workspace = WorkspaceClientFake()
    workspace.setRevealError(.fileNotFound)
    let (model, simulator) = await Self.model(workspace: workspace)
    let id = SampleID.iPhoneOn
    let tap = await Self.startRecording(id, in: model)
    let fetches = Self.fetchCount(in: simulator)

    model.recordingStopTapped(id)
    await tap.value

    let file = Self.reserved()
    #expect(workspace.calls == [.reserveRecordingFile(stem: Self.name.stem), .revealInFinder(file)])
    #expect(workspace.reservedFiles == [file])
    #expect(model.notices.map(\.notice) == [.recordingRevealFailed(Self.label(id), .fileNotFound)])
    #expect(Self.fetchCount(in: simulator) == fetches)
  }

  // MARK: - 기기 꺼짐 자동 멈춤

  @Test("새로 고침에서 기기가 꺼져 있으면 녹화를 멈추고 저장해 Finder 에서 보이며 기기 꺼짐 정보 알림을 띄운다")
  func refreshStopsWhenDeviceTurnedOff() async {
    let workspace = WorkspaceClientFake()
    let (model, simulator) = await Self.model(workspace: workspace)
    let id = SampleID.iPhoneOn
    let tap = await Self.startRecording(id, in: model)
    simulator.setInventory(Self.inventory(id, state: .shutdown))

    await model.refreshButtonTapped()
    // 아직 저장이 끝나지 않았으면 저장 중이다 (Fake 의 멈춤은 다음 차례에 끝난다).
    if let phase = model.recordings.phase(on: id) {
      #expect(phase == .stopping(startedAt: Self.pressedAt, reason: .deviceStopped))
    }
    await tap.value

    let file = Self.reserved()
    #expect(workspace.calls == [.reserveRecordingFile(stem: Self.name.stem), .revealInFinder(file)])
    #expect(model.notices.map(\.notice) == [.recordingStoppedByDevice(Self.label(id))])
    #expect(!model.recordings.isActive)
  }

  @Test("새로 고침 목록에서 기기가 사라져도 녹화를 멈추고 저장한다")
  func refreshStopsWhenDeviceRemoved() async {
    let workspace = WorkspaceClientFake()
    let (model, simulator) = await Self.model(workspace: workspace)
    let id = SampleID.iPhoneOn
    let tap = await Self.startRecording(id, in: model)
    simulator.setInventory(Self.inventory(removing: id))

    await model.refreshButtonTapped()
    await tap.value

    #expect(workspace.calls.last == .revealInFinder(Self.reserved()))
    #expect(model.notices.map(\.notice) == [.recordingStoppedByDevice(Self.label(id))])
    #expect(!model.recordings.isActive)
  }

  @Test("새로 고침에서 기기가 켜져 있으면 녹화를 멈추지 않는다")
  func refreshKeepsRecordingWhenBooted() async {
    let (model, _) = await Self.model()
    let id = SampleID.iPhoneOn
    let tap = await Self.startRecording(id, in: model)

    await model.refreshButtonTapped()

    #expect(model.recordings.phase(on: id) == .recording(startedAt: Self.pressedAt))
    model.recordingStopTapped(id)
    await tap.value
  }

  @Test("시작 중에 새로 고침 목록이 꺼짐이면 멈추고, 시작 신호 전이라 알림 없이 빈 예약 파일을 지운다")
  func refreshStopsWhileStarting() async {
    let workspace = WorkspaceClientFake()
    let (model, simulator) = await Self.model(workspace: workspace) { $0.setRecordingSignalsStart(false) }
    let id = SampleID.iPhoneOn
    let tap = Task { await model.recordButtonTapped(id) }
    await Self.waitUntil { Self.recordCalls(in: simulator).count == 1 }
    simulator.setInventory(Self.inventory(id, state: .shutdown))

    await model.refreshButtonTapped()
    if let phase = model.recordings.phase(on: id) {
      #expect(phase == .stopping(startedAt: nil, reason: .deviceStopped))
    }
    await tap.value

    #expect(workspace.calls == [.reserveRecordingFile(stem: Self.name.stem), .removeReservedFile(Self.reserved())])
    #expect(model.notices.isEmpty)
    #expect(!model.recordings.isActive)
  }

  @Test("기기가 꺼져 멈췄는데 저장을 마치지 못하면 실패 알림 하나만 띄운다 (기기 꺼짐 알림 없음)")
  func deviceStoppedButUnfinished() async {
    let workspace = WorkspaceClientFake()
    let (model, simulator) = await Self.model(workspace: workspace) {
      $0.setRecordingStopOutcome(.failure(.recordingUnfinished))
    }
    let id = SampleID.iPhoneOn
    let tap = await Self.startRecording(id, in: model)
    simulator.setInventory(Self.inventory(id, state: .shutdown))

    await model.refreshButtonTapped()
    await tap.value

    #expect(model.notices.map(\.notice) == [.recordingFailed(Self.label(id), .simulator(.recordingUnfinished))])
    #expect(workspace.reservedFiles == [Self.reserved()])
  }

  // MARK: - 앱 종료

  @Test("appTerminationRequested 는 모든 녹화를 멈추고 저장·Finder 보이기가 끝난 뒤 돌아오며, 기기 꺼짐 알림은 없다")
  func terminationStopsAllAndWaits() async {
    let workspace = WorkspaceClientFake()
    let inventory = Self.inventory(SampleID.iPadOff, state: .booted)
    let (model, _) = await Self.model(workspace: workspace) { $0.setInventory(inventory) }
    let phone = await Self.startRecording(SampleID.iPhoneOn, in: model)
    let pad = await Self.startRecording(SampleID.iPadOff, in: model)

    await model.appTerminationRequested()

    // 돌아온 시점에 기록이 이미 지워져 있어야 App 이 다시 종료할 때 녹화 확인을 또 띄우지 않는다.
    #expect(!model.isRecording)
    #expect(!model.recordings.isActive)
    #expect(Self.revealCount(in: workspace) == 2)
    #expect(model.notices.isEmpty)
    await phone.value
    await pad.value
  }

  @Test("이미 저장 중인 녹화도 appTerminationRequested 가 끝까지 기다리고, 멈춘 이유는 그대로다")
  func terminationWaitsForStoppingRecording() async {
    let workspace = WorkspaceClientFake()
    workspace.suspendReserves()
    let (model, _) = await Self.model(workspace: workspace)
    let id = SampleID.iPhoneOn
    let tap = Task { await model.recordButtonTapped(id) }
    await Self.waitUntil { !workspace.calls.isEmpty }
    model.recordingStopTapped(id)

    let termination = Self.start { await model.appTerminationRequested() }
    for _ in 0 ..< 20 {
      await Task.yield()
    }
    #expect(!termination.isFinished)
    #expect(model.recordings.stopReason(on: id) == .user)

    workspace.resumeReserves()
    await termination.value()
    #expect(workspace.calls.last == .removeReservedFile(Self.reserved()))
    await tap.value
  }

  @Test("isRecording 은 녹화 중과 저장 중에 true 이고 끝나면 false 다")
  func isRecordingWhileStopping() async {
    let workspace = WorkspaceClientFake()
    workspace.suspendReserves()
    let (model, _) = await Self.model(workspace: workspace)
    let id = SampleID.iPhoneOn
    #expect(!model.isRecording)
    let tap = Task { await model.recordButtonTapped(id) }
    await Self.waitUntil { !workspace.calls.isEmpty }
    #expect(model.isRecording)

    model.recordingStopTapped(id)
    #expect(model.isRecording)

    workspace.resumeReserves()
    await tap.value
    #expect(!model.isRecording)
  }

  @Test("종료 요청 뒤에는 녹화를 시작하지 않는다")
  func noRecordingAfterTermination() async {
    let workspace = WorkspaceClientFake()
    let (model, simulator) = await Self.model(workspace: workspace)
    await model.appTerminationRequested()

    let tap = Self.start { await model.recordButtonTapped(SampleID.iPhoneOn) }
    await Self.waitUntil { tap.isFinished || !workspace.calls.isEmpty }

    #expect(tap.isFinished)
    #expect(workspace.calls.isEmpty)
    #expect(Self.recordCalls(in: simulator).isEmpty)
    #expect(!model.recordings.isActive)
  }
}
