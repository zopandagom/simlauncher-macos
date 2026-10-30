import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Foundation
import Testing
import WorkspaceInterface
import WorkspaceTesting
@testable import AndroidDevicesFeature

/// 녹화 Model 테스트가 함께 쓰는 도움 함수.
@MainActor
protocol AndroidRecordingTesting: AndroidDevicesTesting {}

@MainActor
extension AndroidRecordingTesting {
  static var tablet: AndroidVirtualDevice.ID {
    AndroidVirtualDevice.bootedTabletSample.id
  }

  static var label: AndroidDeviceLabel {
    AndroidDeviceLabel(.bootedTabletSample)
  }

  /// 켜진 태블릿을 고정 시각에 녹화한 파일 이름 (런타임 자리 "API 37.0", 확장자 mp4).
  static var name: RecordingFileName {
    RecordingFileName(
      deviceName: "Pixel Tablet", runtimeName: "API 37.0", startedAt: fixedNow, timeZone: .current, container: .mpeg4
    )
  }

  /// Workspace Fake 가 `name` 으로 예약하는 파일.
  static var reserved: URL {
    WorkspaceClientFake.moviesFolder.appending(path: self.name.fileName(attempt: 1)!, directoryHint: .notDirectory)
  }

  /// 같은 목록에서 한 기기의 상태만 바꾼 목록 (`state` 가 nil 이면 그 기기를 뺀다).
  static func inventory(
    _ id: AndroidVirtualDevice.ID,
    state: AndroidVirtualDevice.State?,
    base: AndroidDeviceInventory = .sample
  ) -> AndroidDeviceInventory {
    let devices = base.devices.compactMap { device -> AndroidVirtualDevice? in
      guard device.id == id else { return device }
      return state.map { device.with(state: $0) }
    }
    return AndroidDeviceInventory(devices: devices, creationOptions: base.creationOptions)
  }

  static func recordCount(_ fake: AndroidEmulatorClientFake) -> Int {
    fake.calls.count {
      if case .recordScreen = $0 {
        true
      } else {
        false
      }
    }
  }

  /// 녹화를 시작하고 녹화 중(시작 신호를 받음)이 될 때까지 기다린다. 돌려준 작업은 녹화 흐름이 끝날 때 끝난다.
  static func startRecording(_ id: AndroidVirtualDevice.ID, in model: AndroidDevicesModel) async -> TrackedTask {
    let task = Self.start { await model.recordTapped(id) }
    await Self.waitUntil { model.recordings.phase(on: id) == .recording(startedAt: fixedNow) }
    return task
  }
}

/// 녹화 시작·중지·결과·실패.
@MainActor
struct AndroidDevicesRecordingTests: AndroidRecordingTesting {
  @Test("녹화를 누르면 시작 중이고(예약 이름은 API 자리·mp4), 시작 신호를 받으면 주입한 시각부터 녹화 중이다")
  func startingThenRecording() async {
    let setup = await Self.loadedFixture { $0.suspendRecordings() }
    #expect(Self.reserved.lastPathComponent.hasPrefix("Pixel Tablet (API 37.0) "))
    #expect(Self.reserved.pathExtension == "mp4")
    let tap = Self.start { await setup.model.recordTapped(Self.tablet) }
    await Self.waitUntil { Self.recordCount(setup.fake) == 1 }
    #expect(setup.model.recordings.phase(on: Self.tablet) == .starting)
    #expect(setup.fake.calls.last == .recordScreen(Self.tablet, Self.reserved))
    #expect(setup.workspace.calls == [.reserveRecordingFile(stem: Self.name.stem)])
    #expect(setup.model.isRecording)

    setup.fake.resumeRecordings()
    await Self.waitUntil { setup.model.recordings.phase(on: Self.tablet) == .recording(startedAt: fixedNow) }
    setup.model.recordingStopTapped(Self.tablet)
    await tap.value()
  }

  @Test("중지하면 저장 중이 되고, 끝나면 Finder 에서 보이며 알림·다시 읽기 없이 녹화 상태가 비워진다")
  func stopSavesAndReveals() async {
    let setup = await Self.loadedFixture()
    let tap = await Self.startRecording(Self.tablet, in: setup.model)

    setup.model.recordingStopTapped(Self.tablet)
    #expect(setup.model.recordings.phase(on: Self.tablet) == .stopping(startedAt: fixedNow, reason: .user))
    setup.model.recordingStopTapped(Self.tablet)
    await tap.value()

    #expect(setup.workspace.calls == [.reserveRecordingFile(stem: Self.name.stem), .revealInFinder(Self.reserved)])
    #expect(setup.model.notices.isEmpty)
    #expect(Self.fetchCount(setup.fake) == 1)
    #expect(setup.model.recordings == AndroidRecordingActivity())
    #expect(!setup.model.isRecording)
  }

  @Test("녹화 중 같은 기기를 다시 누르면 바로 끝나고 녹화 명령은 한 번이다")
  func doubleTap() async {
    let setup = await Self.loadedFixture()
    let tap = await Self.startRecording(Self.tablet, in: setup.model)
    await setup.model.recordTapped(Self.tablet)
    #expect(Self.recordCount(setup.fake) == 1)
    setup.model.recordingStopTapped(Self.tablet)
    await tap.value()
  }

  @Test("시작 신호 전에 중지하면 알림 없이 빈 예약 파일을 지운다")
  func stopBeforeStart() async {
    let setup = await Self.loadedFixture { $0.setRecordingSignalsStart(false) }
    let tap = Self.start { await setup.model.recordTapped(Self.tablet) }
    await Self.waitUntil { Self.recordCount(setup.fake) == 1 }
    setup.model.recordingStopTapped(Self.tablet)
    #expect(setup.model.recordings.phase(on: Self.tablet) == .stopping(startedAt: nil, reason: .user))
    await tap.value()
    #expect(setup.workspace.calls == [
      .reserveRecordingFile(stem: Self.name.stem), .removeReservedFile(Self.reserved),
    ])
    #expect(setup.model.notices.isEmpty)
    #expect(!setup.model.isRecording)
  }

  @Test("꺼진·켜는 중·쓸 수 없는 기기와 목록을 읽기 전에는 아무것도 부르지 않는다")
  func blockedDevices() async {
    let unloaded = Self.fixture()
    await unloaded.model.recordTapped(Self.tablet)
    #expect(unloaded.fake.calls.isEmpty)

    let inventory = AndroidDeviceInventory(
      devices: [.phoneSample, .bootingSample, .unsupportedNameSample], creationOptions: .sample
    )
    let setup = await Self.loadedFixture(inventory)
    for id in inventory.devices.map(\.id) {
      await setup.model.recordTapped(id)
    }
    #expect(setup.workspace.calls.isEmpty)
    #expect(setup.fake.calls == [.fetchDevices])
  }

  // MARK: - 결과

  @Test("3분 제한에 닿아 스스로 끝나면 Finder 에서 보이고 정보 알림 뒤 다시 읽는다")
  func savedAtTimeLimit() async {
    let setup = await Self.loadedFixture { $0.setRecordingEndsByItself(.success(.savedAtTimeLimit)) }
    await setup.model.recordTapped(Self.tablet)
    #expect(setup.workspace.calls.last == .revealInFinder(Self.reserved))
    #expect(Self.notices(setup.model) == [.recordingAtTimeLimit(Self.label)])
    #expect(Self.fetchCount(setup.fake) == 2)
    #expect(!setup.model.isRecording)
  }

  @Test("녹화가 실패로 끝났지만 화면을 가져왔으면 지우지 않고 Finder 에서 보이며 중간에 끝남 알림 뒤 다시 읽는다")
  func savedAfterFailure() async {
    let setup = await Self.loadedFixture { $0.setRecordingEndsByItself(.success(.savedAfterFailure)) }
    await setup.model.recordTapped(Self.tablet)
    #expect(setup.workspace.calls == [.reserveRecordingFile(stem: Self.name.stem), .revealInFinder(Self.reserved)])
    #expect(Self.notices(setup.model) == [.recordingInterrupted(Self.label)])
    #expect(Self.fetchCount(setup.fake) == 2)
  }

  @Test(
    "녹화 실패(시작·빈 녹화·가져오기): 예약 파일을 지우고 알림 뒤 한 번 다시 읽는다",
    arguments: [
      AndroidEmulatorError.recordingFailed, .recordingEmpty, .deviceNotBooted, .adbUnavailable, .recordingLost,
    ]
  )
  func endsWithError(_ error: AndroidEmulatorError) async {
    let setup = await Self.loadedFixture { $0.setRecordingEndsByItself(.failure(error)) }
    await setup.model.recordTapped(Self.tablet)
    #expect(setup.workspace.calls == [
      .reserveRecordingFile(stem: Self.name.stem), .removeReservedFile(Self.reserved),
    ])
    #expect(Self.notices(setup.model) == [.recordingFailed(Self.label, .emulator(error))])
    #expect(Self.fetchCount(setup.fake) == 2)
    #expect(!setup.model.isRecording)
  }

  @Test(
    "멈춘 뒤 Mac 에 쓰지 못함·가져오기 시간 초과: (0바이트로 남은) 예약 파일을 지우고 알림 뒤 다시 읽는다",
    arguments: [AndroidEmulatorError.captureFileUnwritable, .recordingTransferTimedOut]
  )
  func stopThenTransferFails(_ error: AndroidEmulatorError) async {
    let setup = await Self.loadedFixture { $0.setRecordingResult(.failure(error)) }
    let tap = await Self.startRecording(Self.tablet, in: setup.model)
    setup.model.recordingStopTapped(Self.tablet)
    await tap.value()
    #expect(setup.workspace.calls.last == .removeReservedFile(Self.reserved))
    #expect(Self.notices(setup.model) == [.recordingFailed(Self.label, .emulator(error))])
    #expect(Self.fetchCount(setup.fake) == 2)
  }

  @Test("예약 실패: 동영상 폴더 알림, 녹화 명령·지우기 없음, 다시 읽지 않고 녹화 상태가 풀린다")
  func reserveFails() async {
    let setup = await Self.loadedFixture()
    setup.workspace.setReserveError(.fileNameUnavailable)
    await setup.model.recordTapped(Self.tablet)
    #expect(setup.workspace.calls == [.reserveRecordingFile(stem: Self.name.stem)])
    #expect(Self.recordCount(setup.fake) == 0)
    #expect(Self.notices(setup.model) == [.recordingFailed(Self.label, .workspace(.fileNameUnavailable))])
    #expect(Self.fetchCount(setup.fake) == 1)
    #expect(!setup.model.isRecording)
  }

  @Test("Finder 실패: 저장한 파일은 지우지 않고 Finder 실패 알림만 띄운다")
  func revealFails() async {
    let setup = await Self.loadedFixture()
    setup.workspace.setRevealError(.fileNotFound)
    let tap = await Self.startRecording(Self.tablet, in: setup.model)
    setup.model.recordingStopTapped(Self.tablet)
    await tap.value()
    #expect(setup.workspace.reservedFiles == [Self.reserved])
    #expect(Self.notices(setup.model) == [.recordingRevealFailed(Self.label, .fileNotFound)])
  }

  // MARK: - 겹침·막기

  @Test("녹화 중에도 같은 기기에 스크린샷·앱 설치를 하고, 녹화는 이어진다")
  func appActionsDuringRecording() async {
    let setup = await Self.loadedFixture()
    let tap = await Self.startRecording(Self.tablet, in: setup.model)

    await setup.model.screenshotTapped(Self.tablet)
    await setup.model.appFileSelected(URL(filePath: "/tmp/app.apk"), for: Self.tablet)
    #expect(Self.count(.screenshot(Self.tablet, setup.workspace.reservedFiles[1]), in: setup.fake) == 1)
    #expect(setup.fake.calls.contains {
      if case .install(_, Self.tablet) = $0 {
        true
      } else {
        false
      }
    })
    #expect(setup.model.recordings.phase(on: Self.tablet) == .recording(startedAt: fixedNow))

    setup.model.recordingStopTapped(Self.tablet)
    await tap.value()
  }

  @Test("녹화 중이면 끄기를 시작하지 않고, 확인한 삭제·초기화도 하지 않는다 (알림 없음)")
  func blocksShutdownDeleteErase() async {
    let setup = await Self.loadedFixture()
    let tap = await Self.startRecording(Self.tablet, in: setup.model)

    await setup.model.shutdownTapped(Self.tablet)
    for action in [AndroidDeviceConfirmation.Action.delete, .erase] {
      await setup.model.confirmationConfirmTapped(
        AndroidDeviceConfirmation(action: action, deviceID: Self.tablet, device: Self.label)
      )
    }
    #expect(!setup.fake.calls.contains(.shutdown(Self.tablet)))
    #expect(setup.model.activity.task(on: Self.tablet) == nil)
    #expect(setup.model.notices.isEmpty)

    setup.model.recordingStopTapped(Self.tablet)
    await tap.value()
    await setup.model.shutdownTapped(Self.tablet)
    #expect(setup.fake.calls.contains(.shutdown(Self.tablet)))
  }

  @Test("저장 중이면 목록에서 꺼진 기기라도 삭제·초기화 확인을 띄우지 않는다")
  func blocksConfirmationWhileStopping() async {
    let setup = await Self.loadedFixture { $0.suspendRecordings() }
    let tap = Self.start { await setup.model.recordTapped(Self.tablet) }
    await Self.waitUntil { Self.recordCount(setup.fake) == 1 }
    setup.fake.setInventory(Self.inventory(Self.tablet, state: .shutdown))
    await setup.model.refreshButtonTapped()
    #expect(setup.model.recordings.phase(on: Self.tablet) == .stopping(startedAt: nil, reason: .deviceStopped))

    setup.model.deleteTapped(Self.tablet)
    setup.model.eraseTapped(Self.tablet)
    #expect(setup.model.confirmation == nil)

    setup.fake.resumeRecordings()
    await tap.value()
    setup.model.deleteTapped(Self.tablet)
    #expect(setup.model.confirmation?.action == .delete)
  }
}
