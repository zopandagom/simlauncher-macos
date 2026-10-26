import Core
import Foundation
import SimulatorTesting
import Testing
@testable import LauncherFeature

struct RecordingActivityTests {
  private static let states: [VirtualDevice.State] = [.shutdown, .booted, .booting, .shuttingDown, .unknown]
  private static let startedAt = Date(timeIntervalSince1970: 1_793_000_000)

  // MARK: - canStart

  @Test("작업이 없으면 쓸 수 있는 켜진 기기만 녹화할 수 있다", arguments: Self.states)
  func canStartFollowsDeviceRule(state: VirtualDevice.State) {
    let activity = RecordingActivity()

    for isAvailable in [true, false] {
      let device = Self.device(state: state, isAvailable: isAvailable)
      let expected = isAvailable && state == .booted
      #expect(activity.canStart(on: device, during: nil) == expected, "쓸 수 있음: \(isAvailable)")
    }
  }

  @Test("같은 기기의 앱 설치·링크 열기 중에는 녹화할 수 있고, 켜기·끄기·삭제·초기화 중에는 녹화할 수 없다")
  func canStartDuringDeviceTask() {
    let activity = RecordingActivity()
    let device = Self.device(state: .booted)

    #expect(activity.canStart(on: device, during: .installApp))
    #expect(activity.canStart(on: device, during: .openURL))
    #expect(!activity.canStart(on: device, during: .boot))
    #expect(!activity.canStart(on: device, during: .shutdown))
    #expect(!activity.canStart(on: device, during: .delete))
    #expect(!activity.canStart(on: device, during: .erase))
  }

  @Test("이미 녹화 중(시작 중·녹화 중·저장 중)인 기기는 다시 시작할 수 없고, 다른 기기는 따로 시작한다")
  func cannotStartWhileRecording() {
    var activity = RecordingActivity()
    let phone = Self.device(state: .booted)
    let pad = Self.device(id: SampleID.iPadOff, state: .booted)

    let began = activity.begin(on: phone, during: nil)
    #expect(began)
    #expect(!activity.canStart(on: phone, during: nil))
    let beganAgain = activity.begin(on: phone, during: nil)
    #expect(!beganAgain)
    activity.started(at: Self.startedAt, on: phone.id)
    #expect(!activity.canStart(on: phone, during: nil))
    _ = activity.requestStop(on: phone.id)
    #expect(!activity.canStart(on: phone, during: nil))
    let padBegan = activity.begin(on: pad, during: .installApp)
    #expect(padBegan)
    #expect(activity.phases == [phone.id: .stopping(startedAt: Self.startedAt, reason: .user), pad.id: .starting])
  }

  @Test("begin 이 거절되면 아무것도 바꾸지 않는다")
  func rejectedBeginChangesNothing() {
    var activity = RecordingActivity()

    let shutdownBegan = activity.begin(on: Self.device(state: .shutdown), during: nil)
    #expect(!shutdownBegan)
    let unavailableBegan = activity.begin(on: Self.device(state: .booted, isAvailable: false), during: nil)
    #expect(!unavailableBegan)
    let duringShutdownBegan = activity.begin(on: Self.device(state: .booted), during: .shutdown)
    #expect(!duringShutdownBegan)
    #expect(activity == RecordingActivity())
    #expect(!activity.isActive)
  }

  // MARK: - 전이

  @Test("begin → 시작 중, 시작 신호 → 녹화 중(그 시각), 중지 → 저장 중(시작 시각·사용자 이유)")
  func beginStartedStop() {
    var activity = RecordingActivity()
    let device = Self.device(state: .booted)

    _ = activity.begin(on: device, during: nil)
    #expect(activity.phase(on: device.id) == .starting)
    #expect(activity.isRecording(on: device.id))
    #expect(activity.isActive)
    #expect(activity.stopReason(on: device.id) == nil)

    activity.started(at: Self.startedAt, on: device.id)
    #expect(activity.phase(on: device.id) == .recording(startedAt: Self.startedAt))
    #expect(activity.stopReason(on: device.id) == nil)

    let stopped = activity.requestStop(on: device.id)
    #expect(stopped)
    #expect(activity.phase(on: device.id) == .stopping(startedAt: Self.startedAt, reason: .user))
    #expect(activity.stopReason(on: device.id) == .user)
    #expect(activity.isRecording(on: device.id))
  }

  @Test("시작 중에 멈추면 시작 시각 없이 저장 중이 된다")
  func stopWhileStarting() {
    var activity = RecordingActivity()
    let device = Self.device(state: .booted)
    _ = activity.begin(on: device, during: nil)

    let stopped = activity.requestStop(on: device.id)

    #expect(stopped)
    #expect(activity.phase(on: device.id) == .stopping(startedAt: nil, reason: .user))
  }

  @Test("저장 중에는 늦게 온 시작 신호를 무시하고, 다시 중지해도 false 이며 단계·이유가 그대로다")
  func stoppingIgnoresLateSignalAndSecondStop() {
    var activity = RecordingActivity()
    let device = Self.device(state: .booted)
    _ = activity.begin(on: device, during: nil)
    _ = activity.requestStop(on: device.id)

    activity.started(at: Self.startedAt, on: device.id)
    let stoppedAgain = activity.requestStop(on: device.id)

    #expect(!stoppedAgain)
    #expect(activity.phase(on: device.id) == .stopping(startedAt: nil, reason: .user))
  }

  @Test("녹화 중에 온 두 번째 시작 신호는 시각을 바꾸지 않는다")
  func secondSignalIgnored() {
    var activity = RecordingActivity()
    let device = Self.device(state: .booted)
    _ = activity.begin(on: device, during: nil)
    activity.started(at: Self.startedAt, on: device.id)

    activity.started(at: Self.startedAt.addingTimeInterval(5), on: device.id)

    #expect(activity.phase(on: device.id) == .recording(startedAt: Self.startedAt))
  }

  @Test("단계가 없으면 시작 신호·중지가 아무것도 바꾸지 않는다")
  func noPhaseIgnoresSignalAndStop() {
    var activity = RecordingActivity()
    let id = SampleID.iPhoneOn

    activity.started(at: Self.startedAt, on: id)
    let stopped = activity.requestStop(on: id)

    #expect(!stopped)
    #expect(activity == RecordingActivity())
  }

  @Test("처음 온 멈춤 이유만 남는다: 중지 뒤 목록 멈춤·전체 멈춤은 이유를 바꾸지 않고 고르지 않는다")
  func firstStopReasonWins() {
    var activity = RecordingActivity()
    let device = Self.device(state: .booted)
    _ = activity.begin(on: device, during: nil)
    activity.started(at: Self.startedAt, on: device.id)
    _ = activity.requestStop(on: device.id)

    let byList = activity.requestStops(notBootedIn: Self.list(state: .shutdown))
    let byTermination = activity.requestStopAll()

    #expect(byList.isEmpty)
    #expect(byTermination.isEmpty)
    #expect(activity.stopReason(on: device.id) == .user)
  }

  @Test("기기 꺼짐으로 멈춘 뒤 중지·전체 멈춤은 이유를 바꾸지 않는다")
  func deviceStoppedReasonWins() {
    var activity = RecordingActivity()
    let device = Self.device(state: .booted)
    _ = activity.begin(on: device, during: nil)
    activity.started(at: Self.startedAt, on: device.id)

    let byList = activity.requestStops(notBootedIn: Self.list(state: .shutdown))
    let byUser = activity.requestStop(on: device.id)
    let byTermination = activity.requestStopAll()

    #expect(byList == [device.id])
    #expect(!byUser)
    #expect(byTermination.isEmpty)
    #expect(activity.phase(on: device.id) == .stopping(startedAt: Self.startedAt, reason: .deviceStopped))
  }

  // MARK: - blocks

  @Test("녹화 중(저장 중 포함)이면 그 기기의 끄기·삭제·초기화만 막고, 다른 기기와 녹화 전에는 막지 않는다")
  func blocksOnlyShutdownDeleteErase() {
    var activity = RecordingActivity()
    let device = Self.device(state: .booted)
    let tasks: [DeviceTask] = [.boot, .shutdown, .delete, .erase, .installApp, .openURL]
    for task in tasks {
      #expect(!activity.blocks(task, on: device.id), "\(task)")
    }

    _ = activity.begin(on: device, during: nil)
    for task in tasks {
      let expected = task == .shutdown || task == .delete || task == .erase
      #expect(activity.blocks(task, on: device.id) == expected, "\(task)")
      #expect(!activity.blocks(task, on: SampleID.iPadOff), "\(task)")
    }
    _ = activity.requestStop(on: device.id)
    #expect(activity.blocks(.shutdown, on: device.id))
  }

  // MARK: - 목록·종료 멈춤

  @Test(
    "requestStops 는 목록에서 켜져 있지 않은(꺼짐·켜는 중·끄는 중·상태 모름) 기기를 고른다",
    arguments: [VirtualDevice.State.shutdown, .booting, .shuttingDown, .unknown]
  )
  func requestStopsPicksNotBooted(state: VirtualDevice.State) {
    var activity = RecordingActivity()
    let device = Self.device(state: .booted)
    _ = activity.begin(on: device, during: nil)

    let ids = activity.requestStops(notBootedIn: Self.list(state: state))

    #expect(ids == [device.id])
    #expect(activity.phase(on: device.id) == .stopping(startedAt: nil, reason: .deviceStopped))
  }

  @Test("requestStops 는 목록에서 사라진 기기를 고르고, 켜져 있는 기기는 고르지 않는다")
  func requestStopsPicksRemovedNotBooted() {
    var activity = RecordingActivity()
    let phone = Self.device(state: .booted)
    let pad = Self.device(id: SampleID.iPadOff, state: .booted)
    _ = activity.begin(on: phone, during: nil)
    _ = activity.begin(on: pad, during: nil)
    activity.started(at: Self.startedAt, on: pad.id)
    // phone 은 목록에 없고 pad 는 켜져 있다.
    let list = DeviceList(inventory: DeviceInventory(
      devices: [pad],
      runtimes: [SampleRuntime.iOS27],
      deviceTypes: []
    ))

    let ids = activity.requestStops(notBootedIn: list)

    #expect(ids == [phone.id])
    #expect(activity.phase(on: phone.id) == .stopping(startedAt: nil, reason: .deviceStopped))
    #expect(activity.phase(on: pad.id) == .recording(startedAt: Self.startedAt))
  }

  @Test("requestStopAll 은 시작 중·녹화 중인 모든 기기를 앱 종료 이유로 바꾸고, 저장 중인 기기는 빼고 이유를 그대로 둔다")
  func requestStopAll() {
    var activity = RecordingActivity()
    let phone = Self.device(state: .booted)
    let pad = Self.device(id: SampleID.iPadOff, state: .booted)
    let old = Self.device(id: SampleID.iPhoneIOS26, state: .booted)
    _ = activity.begin(on: phone, during: nil)
    _ = activity.begin(on: pad, during: nil)
    activity.started(at: Self.startedAt, on: pad.id)
    _ = activity.begin(on: old, during: nil)
    _ = activity.requestStop(on: old.id)

    let ids = activity.requestStopAll()

    #expect(Set(ids) == [phone.id, pad.id])
    #expect(activity.phase(on: phone.id) == .stopping(startedAt: nil, reason: .appTermination))
    #expect(activity.phase(on: pad.id) == .stopping(startedAt: Self.startedAt, reason: .appTermination))
    #expect(activity.phase(on: old.id) == .stopping(startedAt: nil, reason: .user))
  }

  // MARK: - end

  @Test("end 는 그 기기만 지우고, 두 번 불러도 무해하다")
  func endIsIdempotent() {
    var activity = RecordingActivity()
    let phone = Self.device(state: .booted)
    let pad = Self.device(id: SampleID.iPadOff, state: .booted)
    _ = activity.begin(on: phone, during: nil)
    _ = activity.begin(on: pad, during: nil)

    activity.end(on: phone.id)
    activity.end(on: phone.id)

    #expect(!activity.isRecording(on: phone.id))
    #expect(activity.phases == [pad.id: .starting])
    #expect(activity.canStart(on: phone, during: nil))
    activity.end(on: pad.id)
    #expect(!activity.isActive)
  }

  private static func device(
    id: VirtualDevice.ID = SampleID.iPhoneOn,
    state: VirtualDevice.State,
    isAvailable: Bool = true
  ) -> VirtualDevice {
    VirtualDevice(
      id: id,
      name: "iPhone 17 Pro",
      family: .phone,
      state: state,
      availability: isAvailable ? .available : .unavailable(.runtimeNotInstalled),
      runtime: SampleRuntime.iOS27
    )
  }

  /// 기본 기기(`SampleID.iPhoneOn`) 하나가 `state` 인 목록.
  private static func list(state: VirtualDevice.State) -> DeviceList {
    DeviceList(inventory: DeviceInventory(
      devices: [self.device(state: state)],
      runtimes: [SampleRuntime.iOS27],
      deviceTypes: []
    ))
  }
}
