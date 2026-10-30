import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Foundation
import Testing
import WorkspaceTesting
@testable import AndroidDevicesFeature

/// 녹화의 자동 멈춤(다시 읽기에서 기기가 없거나 꺼짐)과 앱 종료.
@MainActor
struct AndroidDevicesRecordingStopTests: AndroidRecordingTesting {
  @Test("새로 고침에서 기기가 꺼져 있으면 녹화를 멈추고 저장해 Finder 에서 보이며 기기 꺼짐 정보 알림을 띄운다")
  func refreshStopsWhenShutDown() async {
    let setup = await Self.loadedFixture()
    let tap = await Self.startRecording(Self.tablet, in: setup.model)
    setup.fake.setInventory(Self.inventory(Self.tablet, state: .shutdown))

    await setup.model.refreshButtonTapped()
    if let phase = setup.model.recordings.phase(on: Self.tablet) {
      #expect(phase == .stopping(startedAt: fixedNow, reason: .deviceStopped))
    }
    await tap.value()

    #expect(setup.workspace.calls == [.reserveRecordingFile(stem: Self.name.stem), .revealInFinder(Self.reserved)])
    #expect(Self.notices(setup.model) == [.recordingStoppedByDevice(Self.label)])
    #expect(!setup.model.isRecording)
  }

  @Test("새로 고침 목록에서 기기가 사라져도 녹화를 멈추고 저장한다")
  func refreshStopsWhenRemoved() async {
    let setup = await Self.loadedFixture()
    let tap = await Self.startRecording(Self.tablet, in: setup.model)
    setup.fake.setInventory(Self.inventory(Self.tablet, state: nil))

    await setup.model.refreshButtonTapped()
    await tap.value()

    #expect(setup.workspace.calls.last == .revealInFinder(Self.reserved))
    #expect(Self.notices(setup.model) == [.recordingStoppedByDevice(Self.label)])
  }

  @Test("새로 고침에서 켜는 중으로 읽혀도(adb 가 잠깐 답하지 않음) 녹화를 멈추지 않는다")
  func bootingKeepsRecording() async {
    let setup = await Self.loadedFixture()
    let tap = await Self.startRecording(Self.tablet, in: setup.model)
    setup.fake.setInventory(Self.inventory(Self.tablet, state: .booting))

    await setup.model.refreshButtonTapped()
    await Self.settle()
    #expect(setup.model.recordings.phase(on: Self.tablet) == .recording(startedAt: fixedNow))

    setup.model.recordingStopTapped(Self.tablet)
    await tap.value()
    #expect(setup.model.notices.isEmpty)
  }

  @Test("기기가 꺼져 멈췄는데 녹화를 가져오지 못하면 실패 알림 하나만 띄운다 (기기 꺼짐 정보 알림 없음)")
  func deviceStoppedButLost() async {
    let setup = await Self.loadedFixture { $0.setRecordingResult(.failure(.recordingLost)) }
    let tap = await Self.startRecording(Self.tablet, in: setup.model)
    setup.fake.setInventory(Self.inventory(Self.tablet, state: .shutdown))

    await setup.model.refreshButtonTapped()
    await tap.value()

    #expect(setup.workspace.calls.last == .removeReservedFile(Self.reserved))
    #expect(Self.notices(setup.model) == [.recordingFailed(Self.label, .emulator(.recordingLost))])
    #expect(AndroidDevicesText.title(for: Self.notices(setup.model).first)
      == "“Pixel Tablet” (API 37.0) 기기가 꺼지거나 연결이 끊겨 녹화를 저장하지 못했습니다")
  }

  @Test("appTerminationRequested 는 모든 녹화를 멈추고 저장·Finder 보이기가 끝난 뒤 돌아오며, 이후 녹화를 시작하지 않는다")
  func appTerminationStopsAll() async {
    let second = AndroidVirtualDevice.secondPhoneSample.with(state: .booted)
    let inventory = AndroidDeviceInventory(devices: [.bootedTabletSample, second], creationOptions: .sample)
    let setup = await Self.loadedFixture(inventory)
    let first = await Self.startRecording(Self.tablet, in: setup.model)
    let other = Self.start { await setup.model.recordTapped(second.id) }
    await Self.waitUntil { setup.model.recordings.phase(on: second.id) == .recording(startedAt: fixedNow) }
    #expect(setup.model.isRecording)

    await setup.model.appTerminationRequested()

    #expect(!setup.model.isRecording)
    #expect(setup.model.recordings == AndroidRecordingActivity())
    #expect(setup.workspace.calls.count {
      if case .revealInFinder = $0 {
        true
      } else {
        false
      }
    } == 2)
    #expect(setup.model.notices.isEmpty)
    await first.value()
    await other.value()

    await setup.model.recordTapped(Self.tablet)
    #expect(Self.recordCount(setup.fake) == 2)
    #expect(!setup.model.isRecording)
  }

  @Test("녹화가 없으면 appTerminationRequested 는 바로 돌아온다")
  func appTerminationWithoutRecording() async {
    let setup = await Self.loadedFixture()
    await setup.model.appTerminationRequested()
    #expect(setup.fake.calls == [.fetchDevices])
  }
}
