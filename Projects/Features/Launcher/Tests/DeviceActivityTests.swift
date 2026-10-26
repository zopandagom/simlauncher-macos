import Core
import DownloadInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

struct DeviceActivityTests {
  private static let states: [VirtualDevice.State] = [.shutdown, .booted, .booting, .shuttingDown, .unknown]
  private static let tasks: [DeviceTask] = [.boot, .shutdown, .delete, .erase, .installApp, .openURL]

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
      case .installApp, .openURL: isAvailable && (state == .shutdown || state == .booted)
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

  // MARK: - 받기 단계

  @Test("beginDownload 는 앱 설치를 시작할 수 있을 때만 task .installApp 과 응답 전 받는 중(.receiving(nil))을 기록한다")
  func beginDownloadRecordsTaskAndStage() {
    var activity = DeviceActivity()
    let device = Self.device(state: .shutdown)

    let began = activity.beginDownload(on: device)
    #expect(began)
    #expect(activity.task(on: device.id) == .installApp)
    #expect(activity.downloadStage(on: device.id) == .receiving(nil))

    // 같은 기기에 다른 작업이 있으면 아무것도 바꾸지 않는다.
    let beganAgain = activity.beginDownload(on: device)
    #expect(!beganAgain)
    #expect(activity.downloadStage(on: device.id) == .receiving(nil))

    var other = DeviceActivity()
    let beganBooting = other.beginDownload(on: Self.device(state: .booting))
    #expect(!beganBooting)
    #expect(other == DeviceActivity())
    let bootBegan = other.begin(.boot, on: device)
    #expect(bootBegan)
    let beganWhileBooting = other.beginDownload(on: device)
    #expect(!beganWhileBooting)
    #expect(other.downloadStage(on: device.id) == nil)
    #expect(other.task(on: device.id) == .boot)
  }

  @Test("진행은 받는 중일 때만 바뀌고, 취소 중이나 받기가 끝난 뒤 온 값은 무시한다")
  func progressOnlyWhileReceiving() {
    var activity = DeviceActivity()
    let device = Self.device(state: .booted)
    let progress = DownloadProgress(receivedBytes: 512, expectedBytes: 1024)
    _ = activity.beginDownload(on: device)

    activity.downloadProgressed(progress, on: device.id)
    #expect(activity.downloadStage(on: device.id) == .receiving(progress))

    _ = activity.requestDownloadCancel(on: device.id)
    activity.downloadProgressed(DownloadProgress(receivedBytes: 1024, expectedBytes: 1024), on: device.id)
    #expect(activity.downloadStage(on: device.id) == .cancelling)

    var ended = DeviceActivity()
    _ = ended.beginDownload(on: device)
    ended.downloadEnded(on: device.id)
    ended.downloadProgressed(progress, on: device.id)
    #expect(ended.downloadStage(on: device.id) == nil)
    ended.downloadProgressed(progress, on: SampleID.iPadOff)
    #expect(ended.downloads.isEmpty)
  }

  @Test("취소 요청은 받는 중일 때만 .cancelling 으로 바꾸고 true, 취소 중·받기 끝남·작업 없음이면 바꾸지 않고 false")
  func requestCancelOnlyWhileReceiving() {
    var activity = DeviceActivity()
    let device = Self.device(state: .booted)
    let cancelledIdle = activity.requestDownloadCancel(on: device.id)
    #expect(!cancelledIdle)
    #expect(!activity.isDownloadCancelRequested(on: device.id))

    _ = activity.beginDownload(on: device)
    #expect(!activity.isDownloadCancelRequested(on: device.id))
    let cancelled = activity.requestDownloadCancel(on: device.id)
    #expect(cancelled)
    #expect(activity.isDownloadCancelRequested(on: device.id))
    let cancelledAgain = activity.requestDownloadCancel(on: device.id)
    #expect(!cancelledAgain)
    #expect(activity.downloadStage(on: device.id) == .cancelling)

    var ended = DeviceActivity()
    _ = ended.beginDownload(on: device)
    ended.downloadEnded(on: device.id)
    let cancelledEnded = ended.requestDownloadCancel(on: device.id)
    #expect(!cancelledEnded)
    #expect(ended.downloadStage(on: device.id) == nil)
    #expect(ended.task(on: device.id) == .installApp)
  }

  @Test("downloadEnded 는 단계만 지우고 task 는 남기며, end 는 둘 다 지운다")
  func endingClearsStage() {
    var activity = DeviceActivity()
    let device = Self.device(state: .booted)
    _ = activity.beginDownload(on: device)

    activity.downloadEnded(on: device.id)
    #expect(activity.downloadStage(on: device.id) == nil)
    #expect(activity.task(on: device.id) == .installApp)

    var cancelled = DeviceActivity()
    _ = cancelled.beginDownload(on: device)
    _ = cancelled.requestDownloadCancel(on: device.id)
    cancelled.end(on: device.id)
    #expect(cancelled == DeviceActivity())
    activity.end(on: device.id)
    #expect(activity == DeviceActivity())
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

// MARK: - 여러 기기 묶음

extension DeviceActivityTests {
  private static let list = DeviceList(inventory: .sample)

  private static func sample(_ id: VirtualDevice.ID) -> VirtualDevice {
    self.list.device(id: id)!
  }

  private static func target(_ id: VirtualDevice.ID) -> TargetDevice {
    TargetDevice(self.sample(id))
  }

  @Test("beginInstall 은 대상마다 판정해 준비된 기기만 시작하고, 건너뛴 이유(없음·상태·작업 중)를 요청 순서로 돌려준다")
  func beginInstallJudgesEachTarget() {
    var activity = DeviceActivity()
    _ = activity.begin(.boot, on: Self.sample(SampleID.iPhoneOff))
    let missing = TargetDevice(
      id: VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF"),
      label: LauncherNotice.Device(name: "지운 기기", runtimeName: "iOS 27.0")
    )
    guard case let .blocked(reason) = Self.sample(SampleID.unavailableIPhone).appInstallAvailability else {
      Issue.record("샘플의 쓸 수 없는 기기가 설치를 막지 않는다")
      return
    }
    let targets = [
      Self.target(SampleID.iPhoneOff), Self.target(SampleID.iPhoneOn),
      Self.target(SampleID.unavailableIPhone), missing,
    ]

    let start = activity.beginInstall(on: targets, in: .loaded(Self.list), downloading: false)

    #expect(start.requested == targets)
    #expect(start.begun == [Self.sample(SampleID.iPhoneOn)])
    #expect(start.skipped == [
      InstallStart.Skip(target: Self.target(SampleID.iPhoneOff), failure: .deviceBusy),
      InstallStart.Skip(target: Self.target(SampleID.unavailableIPhone), failure: .deviceNotReady(reason)),
      InstallStart.Skip(target: missing, failure: .simulator(.deviceNotFound)),
    ])
    #expect(!start.isSingle)
    #expect(activity.task(on: SampleID.iPhoneOn) == .installApp)
    #expect(activity.task(on: SampleID.iPhoneOff) == .boot)
    #expect(activity.downloadStage(on: SampleID.iPhoneOn) == nil)

    var unloaded = DeviceActivity()
    let none = unloaded.beginInstall(on: [Self.target(SampleID.iPhoneOn)], in: .loading, downloading: true)
    #expect(none.begun.isEmpty)
    #expect(none.skipped == [
      InstallStart.Skip(target: Self.target(SampleID.iPhoneOn), failure: .simulator(.deviceNotFound)),
    ])
    #expect(none.isSingle)
    #expect(unloaded == DeviceActivity())
  }

  @Test("받기 묶음은 시작한 기기 모두가 같은 진행을 보이고, 한 기기의 취소가 그 묶음만 함께 멈춘다")
  func downloadGroupSharesProgressAndCancel() {
    var activity = DeviceActivity()
    let group = activity.beginInstall(
      on: [Self.target(SampleID.iPhoneOff), Self.target(SampleID.iPhoneOn)],
      in: .loaded(Self.list),
      downloading: true
    )
    let otherBegan = activity.beginDownload(on: Self.sample(SampleID.iPadOff))
    let ids = group.begun.map(\.id)
    let progress = DownloadProgress(receivedBytes: 512, expectedBytes: 1024)
    #expect(otherBegan)
    #expect(ids == [SampleID.iPhoneOff, SampleID.iPhoneOn])
    #expect(activity.downloadGroupSize(on: SampleID.iPhoneOff) == 2)
    #expect(activity.downloadGroupSize(on: SampleID.iPadOff) == 1)
    #expect(activity.downloadGroupSize(on: SampleID.iPhoneIOS26) == 0)

    activity.downloadProgressed(progress, on: ids)
    #expect(activity.downloadStage(on: SampleID.iPhoneOff) == .receiving(progress))
    #expect(activity.downloadStage(on: SampleID.iPhoneOn) == .receiving(progress))
    #expect(activity.downloadStage(on: SampleID.iPadOff) == .receiving(nil))

    let cancelled = activity.requestDownloadCancel(on: SampleID.iPhoneOn)
    #expect(cancelled)
    #expect(activity.isDownloadCancelRequested(on: SampleID.iPhoneOff))
    #expect(activity.downloadStage(on: SampleID.iPhoneOn) == .cancelling)
    #expect(activity.downloadStage(on: SampleID.iPadOff) == .receiving(nil))
    #expect(activity.downloadGroupSize(on: SampleID.iPhoneOff) == 0)
  }

  @Test("end(on:) 는 묶음 번호도 지워 남은 기기의 묶음 크기가 줄고, 묶음을 모두 끝내면 처음과 같다")
  func endClearsDownloadGroup() {
    var activity = DeviceActivity()
    let start = activity.beginInstall(
      on: [Self.target(SampleID.iPhoneOff), Self.target(SampleID.iPhoneOn)],
      in: .loaded(Self.list),
      downloading: true
    )

    activity.end(on: SampleID.iPhoneOff)
    #expect(activity.downloadGroupSize(on: SampleID.iPhoneOn) == 1)
    let cancelled = activity.requestDownloadCancel(on: SampleID.iPhoneOn)
    #expect(cancelled)
    #expect(activity.downloadStage(on: SampleID.iPhoneOff) == nil)

    activity.end(on: start.begun.map(\.id), owner: start.owner)
    #expect(activity == DeviceActivity())

    var ended = DeviceActivity()
    let other = ended.beginInstall(
      on: [Self.target(SampleID.iPhoneOff), Self.target(SampleID.iPhoneOn)],
      in: .loaded(Self.list),
      downloading: true
    )
    ended.downloadEnded(on: other.begun.map(\.id))
    #expect(ended.downloads.isEmpty)
    #expect(ended.task(on: SampleID.iPhoneOn) == .installApp)
    #expect(ended.downloadGroupSize(on: SampleID.iPhoneOn) == 0)
  }

  @Test("beginAll 은 시작할 수 있는 기기만 시작하고 건너뛴 기기를 알리지 않는다")
  func beginAllStartsOnlyAllowed() {
    var activity = DeviceActivity()
    let devices = [
      Self.sample(SampleID.iPhoneOff), Self.sample(SampleID.iPhoneOn), Self.sample(SampleID.unavailableIPhone),
    ]

    let start = activity.beginAll(.boot, on: devices)

    #expect(start.requested == devices.map(TargetDevice.init))
    #expect(start.begun == [Self.sample(SampleID.iPhoneOff)])
    #expect(start.skipped.isEmpty)
    #expect(activity.tasks == [SampleID.iPhoneOff: .boot])
  }

  @Test("소유자 번호: 묶음의 끝은 먼저 풀린 기기에 새로 시작한 작업을 지우지 않고, 다른 번호로는 아무것도 지우지 않는다")
  func endWithOwnerKeepsNewerTask() {
    var activity = DeviceActivity()
    let first = Self.device(id: SampleID.iPhoneOff, state: .shutdown)
    let second = Self.device(id: SampleID.iPadOff, state: .shutdown)
    let start = activity.beginAll(.boot, on: [first, second])

    // 먼저 끝난 기기가 풀린 뒤 그 기기에서 새 작업을 시작한다.
    activity.end(on: [first.id], owner: start.owner)
    #expect(activity.task(on: first.id) == nil)
    let shutdownBegan = activity.begin(.shutdown, on: Self.device(id: first.id, state: .booted))
    #expect(shutdownBegan)

    activity.end(on: [second.id], owner: start.owner + 1)
    #expect(activity.task(on: second.id) == .boot)

    activity.end(on: [first.id, second.id], owner: start.owner)
    #expect(activity.tasks == [first.id: .shutdown])

    activity.end(on: first.id)
    #expect(activity == DeviceActivity())
  }
}
