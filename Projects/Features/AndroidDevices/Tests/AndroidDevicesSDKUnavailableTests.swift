import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Foundation
import Testing
@testable import AndroidDevicesFeature

/// Android 도구(SDK)를 쓸 수 없어 잠금 파일만으로 읽은 목록(`sdkAvailable == false`): 꺼진 기기의 삭제만 되고, 켜기·끄기·초기화·
/// 앱 작업·캡처는 시작하지 않으며, 켜는 중이 없어 자동 다시 읽기도 돌지 않는다. 녹화 중 기기가 꺼짐으로 읽히면 녹화를 멈춘다.
@MainActor
struct AndroidDevicesSDKUnavailableTests: AndroidRecordingTesting {
  private static let shutDown = AndroidVirtualDevice.sdkUnavailableShutdownSample
  private static let booted = AndroidVirtualDevice.sdkUnavailableBootedSample
  private static let inventory = AndroidDeviceInventory.sdkUnavailableSample(devices: [shutDown, booted])

  /// Fake 호출 중 첫 목록 읽기 뒤의 것 (목록 읽기는 뺀다).
  private static func commands(_ fake: AndroidEmulatorClientFake) -> [AndroidEmulatorClientFake.Call] {
    fake.calls.filter { $0 != .fetchDevices }
  }

  @Test("켜기·선택한 기기 켜기·끄기(잠금으로 켜진 기기)·초기화는 시작하지 않고 Client 를 부르지 않는다")
  func deviceCommandsBlocked() async {
    let setup = await Self.loadedFixture(Self.inventory)
    #expect(setup.model.isSDKUnavailable)
    await setup.model.bootTapped(Self.shutDown.id)
    setup.model.selectionChanged([Self.shutDown.id, Self.booted.id])
    #expect(!setup.model.canBootSelection)
    await setup.model.bootSelectedTapped()
    await setup.model.shutdownTapped(Self.booted.id)
    setup.model.eraseTapped(Self.shutDown.id)
    #expect(setup.model.confirmation == nil)
    await setup.model.confirmationConfirmTapped(
      AndroidDeviceConfirmation(action: .erase, deviceID: Self.shutDown.id, device: AndroidDeviceLabel(Self.shutDown))
    )
    #expect(Self.commands(setup.fake).isEmpty)
    #expect(setup.model.notices.isEmpty)
    #expect(setup.model.activity == AndroidDeviceActivity())
  }

  @Test("켜진 기기의 앱 설치는 쓸 수 없는 기기라고 알리고, 앱 실행·링크 열기 시트·스크린샷·녹화는 시작하지 않는다")
  func appActionsAndCaptureBlocked() async {
    let setup = await Self.loadedFixture(Self.inventory)
    setup.model.selectionChanged([Self.booted.id])
    #expect(!setup.model.canInstallOnSelection)
    await setup.model.appFileSelected(URL(filePath: "/tmp/app.apk"), for: Self.booted.id)
    #expect(Self.notices(setup.model) == [.installFailed(
      AndroidDeviceLabel(Self.booted),
      .deviceNotReady(.unavailable)
    )])
    #expect(setup.model.appSheetTarget(Self.booted.id, for: .launchApp) == nil)
    #expect(setup.model.appSheetTarget(Self.booted.id, for: .openURL) == nil)
    await setup.model.screenshotTapped(Self.booted.id)
    await setup.model.recordTapped(Self.booted.id)
    #expect(Self.commands(setup.fake).isEmpty)
    #expect(setup.workspace.calls.isEmpty)
    #expect(!setup.model.isRecording)
  }

  @Test("꺼진 기기는 삭제 확인 뒤 Client 의 삭제를 부르고 다시 읽는다. 잠금으로 켜진 기기는 확인을 띄우지 않는다")
  func deleteShutdownDevice() async {
    let setup = await Self.loadedFixture(Self.inventory)
    setup.model.deleteTapped(Self.booted.id)
    #expect(setup.model.confirmation == nil)
    setup.model.deleteTapped(Self.shutDown.id)
    let confirmation = AndroidDeviceConfirmation(
      action: .delete, deviceID: Self.shutDown.id, device: AndroidDeviceLabel(Self.shutDown)
    )
    #expect(setup.model.confirmation == confirmation)
    setup.fake.setInventory(.sdkUnavailableSample(devices: [Self.booted]))
    await setup.model.confirmationConfirmTapped(confirmation)
    #expect(Self.commands(setup.fake) == [.delete(Self.shutDown.id)])
    #expect(Self.fetchCount(setup.fake) == 2)
    #expect(Self.list(setup.model)?.devices == [Self.booted])
    #expect(setup.model.isSDKUnavailable)
    #expect(setup.model.notices.isEmpty)
  }

  @Test("잠금으로 켜진 기기만 있어도 켜는 중이 없어 자동 다시 읽기를 시작하지 않는다")
  func noAutoRefresh() async {
    let setup = await Self.loadedFixture(Self.inventory)
    await Self.settle()
    #expect(setup.sleeper.requested.isEmpty)
    #expect(Self.fetchCount(setup.fake) == 1)
  }

  @Test("녹화 중 Android 도구가 사라진 목록에서 기기가 꺼짐(잠금 없음)으로 읽히면 녹화를 멈추고 저장한다")
  func recordingStopsWhenShutDownWithoutSDK() async {
    let setup = await Self.loadedFixture()
    let tap = await Self.startRecording(Self.tablet, in: setup.model)
    setup.fake.setInventory(.sdkUnavailableSample(devices: [Self.booted.with(state: .shutdown)]))

    await setup.model.refreshButtonTapped()
    await tap.value()

    #expect(setup.model.isSDKUnavailable)
    #expect(setup.workspace.calls.last == .revealInFinder(Self.reserved))
    #expect(Self.notices(setup.model) == [.recordingStoppedByDevice(Self.label)])
    #expect(!setup.model.isRecording)
  }

  @Test("녹화 중 Android 도구가 사라져도 잠금으로 켜짐으로 읽히면 녹화를 계속한다")
  func recordingContinuesWhenLockHeld() async {
    let setup = await Self.loadedFixture()
    let tap = await Self.startRecording(Self.tablet, in: setup.model)
    setup.fake.setInventory(.sdkUnavailableSample(devices: [Self.booted]))

    await setup.model.refreshButtonTapped()
    await Self.settle()
    #expect(setup.model.isSDKUnavailable)
    #expect(setup.model.recordings.phase(on: Self.tablet) == .recording(startedAt: fixedNow))

    setup.model.recordingStopTapped(Self.tablet)
    await tap.value()
    #expect(setup.model.notices.isEmpty)
  }
}
