import Core
import SimulatorTesting
import Testing
@testable import LauncherFeature

struct DeviceActivityTests {
  private static let states: [VirtualDevice.State] = [.shutdown, .booted, .booting, .shuttingDown, .unknown]
  private static let tasks: [DeviceTask] = [.boot, .shutdown, .delete, .erase]

  @Test(
    "진행 중인 작업이 없으면 작업별 기기 규칙대로 시작할 수 있다",
    arguments: Self.tasks, Self.states
  )
  func canStartFollowsDeviceRule(task: DeviceTask, state: VirtualDevice.State) {
    let activity = DeviceActivity()

    for isAvailable in [true, false] {
      let device = Self.device(state: state, isAvailable: isAvailable)
      let expected = switch task {
      case .boot: isAvailable && state == .shutdown
      case .shutdown: state == .booted
      case .delete: state == .shutdown
      case .erase: isAvailable && state == .shutdown
      }
      #expect(activity.canStart(task, on: device) == expected, "쓸 수 있음: \(isAvailable)")
    }
  }

  @Test("begin 은 허용되면 기록하고 true 를 돌려준다")
  func beginRecordsTask() {
    var activity = DeviceActivity()
    let device = Self.device(state: .shutdown)

    let began = activity.begin(.boot, on: device)

    #expect(began)
    #expect(activity.task(on: device.id) == .boot)
    #expect(activity.tasks == [device.id: .boot])
    #expect(activity.busyDeviceIDs == [device.id])
  }

  @Test("같은 기기에 진행 중인 작업이 있으면 어떤 작업이든 false 이고 기존 작업을 덮어쓰지 않는다", arguments: Self.tasks)
  func beginRejectsBusyDevice(task: DeviceTask) {
    var activity = DeviceActivity()
    let device = Self.device(state: .shutdown)
    _ = activity.begin(.delete, on: device)
    // 진행 중 확인이 없어도 허용될 상태로 바꿔, 막는 이유가 진행 중 작업뿐이게 한다.
    let changed = Self.device(state: task == .shutdown ? .booted : .shutdown)

    #expect(!activity.canStart(task, on: changed))
    let began = activity.begin(task, on: changed)
    #expect(!began)
    #expect(activity.tasks == [device.id: .delete])
  }

  @Test("기기 규칙이 막으면 false 이고 아무것도 기록하지 않는다")
  func beginRejectsBlockedDevice() {
    var activity = DeviceActivity()

    let began = activity.begin(.boot, on: Self.device(state: .booted))

    #expect(!began)
    #expect(activity.tasks.isEmpty)
  }

  @Test("다른 기기의 작업은 서로 막지 않는다")
  func devicesAreIndependent() {
    var activity = DeviceActivity()
    let first = Self.device(id: SampleID.iPhoneOff, state: .shutdown)
    let second = Self.device(id: SampleID.iPadOff, state: .shutdown)

    let firstBegan = activity.begin(.boot, on: first)
    let secondBegan = activity.begin(.erase, on: second)

    #expect(firstBegan && secondBegan)
    #expect(activity.tasks == [first.id: .boot, second.id: .erase])
    #expect(activity.busyDeviceIDs == [first.id, second.id])
  }

  @Test("end 는 그 기기만 지우고, 기록이 없는 기기는 아무것도 바꾸지 않는다")
  func endRemovesOnlyThatDevice() {
    var activity = DeviceActivity()
    let first = Self.device(id: SampleID.iPhoneOff, state: .shutdown)
    let second = Self.device(id: SampleID.iPadOff, state: .shutdown)
    _ = activity.begin(.boot, on: first)
    _ = activity.begin(.delete, on: second)

    activity.end(on: first.id)
    #expect(activity.tasks == [second.id: .delete])
    #expect(activity.task(on: first.id) == nil)

    activity.end(on: first.id)
    activity.end(on: SampleID.watch)
    #expect(activity.tasks == [second.id: .delete])

    let beganAgain = activity.begin(.boot, on: first)
    #expect(beganAgain)
  }

  private static func device(
    id: VirtualDevice.ID = SampleID.iPhoneOff,
    state: VirtualDevice.State,
    isAvailable: Bool = true
  ) -> VirtualDevice {
    VirtualDevice(
      id: id,
      name: "iPhone 17",
      family: .phone,
      state: state,
      availability: isAvailable ? .available : .unavailable(.runtimeNotInstalled),
      runtime: SampleRuntime.iOS27
    )
  }
}
