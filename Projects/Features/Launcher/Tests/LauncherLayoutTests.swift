import AppBundleTesting
import AppLogTesting
import Core
import DownloadTesting
import Foundation
import SimulatorInterface
import SimulatorTesting
import Synchronization
import Testing
import WorkspaceTesting
@testable import LauncherFeature

/// 행 "레이아웃 보기"(`IOSLayoutAvailability`, 문구)와 기기 수명 알림(`LauncherDeviceHooks`: 끄기 전후·목록 읽기).
struct LauncherLayoutTests: LauncherModelTesting {
  private nonisolated static let states: [VirtualDevice.State] = [.shutdown, .booted, .booting, .shuttingDown, .unknown]

  // MARK: - 누를 수 있는지

  @Test("작업이 없으면 쓸 수 있는 켜진 기기만 레이아웃을 볼 수 있다", arguments: Self.states)
  func canOpenFollowsDeviceRule(state: VirtualDevice.State) {
    for isAvailable in [true, false] {
      let device = Self.device(state: state, isAvailable: isAvailable)
      let expected = isAvailable && state == .booted
      #expect(IOSLayoutAvailability.canOpen(device: device, during: nil) == expected, "쓸 수 있음: \(isAvailable)")
    }
  }

  @Test("러너 최소 iOS 보다 낮은 켜진 기기는 열 수 없고, 툴팁 문구가 그 버전을 말한다")
  func olderOSCannotOpen() {
    let minimum = IOSLayoutRunner.minimumOSVersion
    let older = DeviceRuntime(
      id: DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.iOS-16-4"),
      platform: .iOS,
      version: OSVersion(major: minimum.major - 1, minor: 4),
      name: "iOS 16.4",
      isAvailable: true,
      supportedDeviceTypeIDs: []
    )
    let device = VirtualDevice(
      id: SampleID.iPhoneOn, name: "iPhone 14", family: .phone, state: .booted, availability: .available, runtime: older
    )

    #expect(!IOSLayoutAvailability.supportsRunner(device))
    #expect(!IOSLayoutAvailability.canOpen(device: device, during: nil))
    #expect(IOSLayoutAvailability.supportsRunner(Self.device(state: .booted)))
    #expect(LauncherText.layoutUnsupportedOS.contains("iOS \(minimum.major)"))
  }

  @Test("같은 기기의 앱 설치·링크 열기·앱 실행 중에는 열 수 있고, 켜기·끄기·삭제·초기화 중에는 열 수 없다")
  func canOpenDuringDeviceTask() {
    let device = Self.device(state: .booted)

    #expect(IOSLayoutAvailability.canOpen(device: device, during: .installApp))
    #expect(IOSLayoutAvailability.canOpen(device: device, during: .openURL))
    #expect(IOSLayoutAvailability.canOpen(device: device, during: .launchApp))
    #expect(!IOSLayoutAvailability.canOpen(device: device, during: .boot))
    #expect(!IOSLayoutAvailability.canOpen(device: device, during: .shutdown))
    #expect(!IOSLayoutAvailability.canOpen(device: device, during: .delete))
    #expect(!IOSLayoutAvailability.canOpen(device: device, during: .erase))
  }

  @Test("막힌 이유 툴팁은 꺼짐·쓸 수 없음이 서로 다르고, 스크린샷 문구가 아니라 레이아웃을 말한다")
  func blockReasonsMentionLayout() {
    let notBooted = LauncherText.layoutBlockReason(.notBooted)
    let unavailable = LauncherText.layoutBlockReason(.unavailable)

    #expect(notBooted != unavailable)
    for reason in LauncherTextCatalog.screenshotBlockReasons {
      #expect(LauncherText.layoutBlockReason(reason).contains("레이아웃"))
      #expect(LauncherText.layoutBlockReason(reason) != LauncherText.screenshotBlockReason(reason))
    }
  }

  // MARK: - 끄기 전후 알림

  @Test("끄기는 willShutDown → simctl shutdown → didShutDown 순서로 같은 기기 ID 를 알린 뒤 목록을 다시 읽는다")
  func shutdownNotifiesAroundShutdown() async {
    let hooked = await Self.hookedModel()
    let model = hooked.model
    let fake = hooked.fake
    let recorder = hooked.recorder
    recorder.reset()

    await model.shutdownButtonTapped(SampleID.iPhoneOn)

    #expect(
      recorder.events == [
        .willShutDown(SampleID.iPhoneOn, shutdownCalled: false),
        .didShutDown(SampleID.iPhoneOn, shutdownCalled: true),
        .listed([]),
      ]
    )
    #expect(fake.calls == [.fetchInventory, .shutdown(SampleID.iPhoneOn), .fetchInventory])
  }

  @Test("끄기가 실패해도 didShutDown 을 부르고, 다시 읽은 목록의 켜진 기기를 알린다")
  func shutdownFailureStillNotifiesDidShutDown() async {
    let hooked = await Self.hookedModel { $0.setShutdownError(.commandFailed) }
    let model = hooked.model
    let recorder = hooked.recorder
    recorder.reset()

    await model.shutdownButtonTapped(SampleID.iPhoneOn)

    #expect(
      recorder.events == [
        .willShutDown(SampleID.iPhoneOn, shutdownCalled: false),
        .didShutDown(SampleID.iPhoneOn, shutdownCalled: true),
        .listed([SampleID.iPhoneOn]),
      ]
    )
    #expect(model.notices.map(\.notice) == [.shutdownFailed(Self.label(SampleID.iPhoneOn), .commandFailed)])
  }

  @Test("끄기를 부르지 않는 경우(꺼진 기기)에는 끄기 알림도 없다")
  func ignoredShutdownDoesNotNotify() async {
    let hooked = await Self.hookedModel()
    let model = hooked.model
    let recorder = hooked.recorder
    recorder.reset()

    await model.shutdownButtonTapped(SampleID.iPhoneOff)

    #expect(recorder.events.isEmpty)
  }

  // MARK: - 목록 읽기 알림

  @Test("목록을 읽을 때마다 켜진 기기 ID 집합만 알린다 (꺼진·켜는 중 기기는 빠진다)")
  func listedReportsBootedDevicesOnEveryRead() async {
    let hooked = await Self.hookedModel()
    let model = hooked.model
    let fake = hooked.fake
    let recorder = hooked.recorder
    #expect(recorder.events == [.listed([SampleID.iPhoneOn])])

    fake.setInventory(Self.inventory(states: [SampleID.iPhoneOff: .booting, SampleID.iPadOff: .booted]))
    await model.refreshButtonTapped()

    #expect(recorder.events == [.listed([SampleID.iPhoneOn]), .listed([SampleID.iPhoneOn, SampleID.iPadOff])])
  }

  @Test("목록 읽기가 실패하면 알리지 않는다")
  func failedReadDoesNotNotify() async {
    let hooked = await Self.hookedModel()
    let model = hooked.model
    let fake = hooked.fake
    let recorder = hooked.recorder
    recorder.reset()

    fake.setFetchError(.commandFailed)
    await model.refreshButtonTapped()

    #expect(recorder.events.isEmpty)
  }

  @Test("처음 읽기가 실패하면 알리지 않고, 다음 읽기가 성공하면 알린다")
  func firstFailedReadThenSuccess() async {
    let hooked = await Self.hookedModel { $0.setFetchError(.commandFailed) }
    let model = hooked.model
    let fake = hooked.fake
    let recorder = hooked.recorder
    #expect(recorder.events.isEmpty)

    fake.setFetchError(nil)
    await model.refreshButtonTapped()

    #expect(recorder.events == [.listed([SampleID.iPhoneOn])])
  }
}

// MARK: - 도움

extension LauncherLayoutTests {
  /// 훅이 받은 알림. 끄기 알림은 그 시점에 Simulator Fake 가 `shutdown` 을 받았는지를 함께 적는다 (순서 확인).
  enum Event: Equatable {
    case willShutDown(VirtualDevice.ID, shutdownCalled: Bool)
    case didShutDown(VirtualDevice.ID, shutdownCalled: Bool)
    case listed(Set<VirtualDevice.ID>)
  }

  final class Recorder: Sendable {
    private let state = Mutex<[Event]>([])

    var events: [Event] {
      self.state.withLock { $0 }
    }

    func append(_ event: Event) {
      self.state.withLock { $0.append(event) }
    }

    func reset() {
      self.state.withLock { $0.removeAll() }
    }
  }

  struct HookedModel {
    let model: LauncherModel
    let fake: SimulatorClientFake
    let recorder: Recorder
  }

  /// 샘플 목록 Fake 와 기록하는 훅으로 만들고 첫 목록까지 읽은 Model.
  static func hookedModel(
    _ configure: (SimulatorClientFake) -> Void = { _ in }
  ) async -> HookedModel {
    let fake = SimulatorClientFake(inventory: .sample)
    configure(fake)
    let recorder = Recorder()
    let shutdownCalled: @Sendable (VirtualDevice.ID) -> Bool = { id in
      fake.calls.contains(.shutdown(id))
    }
    let hooks = LauncherDeviceHooks(
      willShutDown: { recorder.append(.willShutDown($0, shutdownCalled: shutdownCalled($0))) },
      didShutDown: { recorder.append(.didShutDown($0, shutdownCalled: shutdownCalled($0))) },
      listed: { recorder.append(.listed($0)) }
    )
    let model = LauncherModel(
      simulator: fake,
      appBundle: AppBundleClientFake(),
      download: DownloadClientFake(),
      workspace: WorkspaceClientFake(),
      appLog: AppLogClientFake.forwarding(to: fake),
      deviceHooks: hooks
    )
    await model.onAppear()
    return HookedModel(model: model, fake: fake, recorder: recorder)
  }

  /// 샘플 목록에서 지정한 기기의 상태만 바꾼 목록.
  static func inventory(states: [VirtualDevice.ID: VirtualDevice.State]) -> DeviceInventory {
    let sample = DeviceInventory.sample
    let devices = sample.devices.map { device in
      guard let state = states[device.id] else { return device }
      return VirtualDevice(
        id: device.id,
        name: device.name,
        family: device.family,
        state: state,
        availability: device.availability,
        runtime: device.runtime
      )
    }
    return DeviceInventory(devices: devices, runtimes: sample.runtimes, deviceTypes: sample.deviceTypes)
  }

  private static func device(state: VirtualDevice.State, isAvailable: Bool = true) -> VirtualDevice {
    VirtualDevice(
      id: SampleID.iPhoneOn,
      name: "iPhone 17 Pro",
      family: .phone,
      state: state,
      availability: isAvailable ? .available : .unavailable(.runtimeNotInstalled),
      runtime: SampleRuntime.iOS27
    )
  }
}
