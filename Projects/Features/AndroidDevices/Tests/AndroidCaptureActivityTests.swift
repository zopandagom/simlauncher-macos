import AndroidEmulatorTesting
import Core
import Foundation
import Testing
@testable import AndroidDevicesFeature

/// 스크린샷·녹화 기록(`AndroidScreenshotActivity`·`AndroidRecordingActivity`)의 허용 규칙과 전이.
struct AndroidCaptureActivityTests {
  private let tablet = AndroidVirtualDevice.bootedTabletSample
  private let started = Date(timeIntervalSince1970: 1000)

  static let allTasks: [AndroidDeviceTask?] = [
    nil,
    .boot,
    .shutdown,
    .delete,
    .erase,
    .installApp,
    .launchApp,
    .openURL,
  ]

  /// 작업 중에도 캡처할 수 있는 작업 (기기 작업이 없거나 앱 작업).
  private static func allowsCapture(_ task: AndroidDeviceTask?) -> Bool {
    switch task {
    case .none, .installApp, .launchApp, .openURL: true
    case .boot, .shutdown, .delete, .erase: false
    }
  }

  // MARK: - 스크린샷

  @Test("스크린샷: 쓸 수 있는 켜진 기기만, 작업이 없거나 앱 작업 중일 때만 찍는다", arguments: Self.allTasks)
  func screenshotRules(_ task: AndroidDeviceTask?) {
    let activity = AndroidScreenshotActivity()
    #expect(activity.canStart(on: self.tablet, during: task) == Self.allowsCapture(task))
    #expect(!activity.canStart(on: .phoneSample, during: task))
    #expect(!activity.canStart(on: self.tablet.with(state: .booting), during: task))
    #expect(!activity.canStart(on: .unsupportedNameSample, during: task))
  }

  @Test("스크린샷: begin 은 같은 기기를 한 번만 기록하고, end 뒤에는 다시 찍는다")
  func screenshotTransitions() {
    var activity = AndroidScreenshotActivity()
    let began = activity.begin(on: self.tablet, during: nil)
    #expect(began)
    #expect(activity.isTaking(on: self.tablet.id))
    let beganAgain = activity.begin(on: self.tablet, during: nil)
    #expect(!beganAgain)
    let beganOff = activity.begin(on: .phoneSample, during: nil)
    #expect(!beganOff)
    #expect(activity.deviceIDs == [self.tablet.id])
    activity.end(on: self.tablet.id)
    activity.end(on: self.tablet.id)
    #expect(activity == AndroidScreenshotActivity())
    let beganAfterEnd = activity.begin(on: self.tablet, during: .installApp)
    #expect(beganAfterEnd)
  }

  // MARK: - 녹화: 허용·막기

  @Test("녹화: 쓸 수 있는 켜진 기기만, 작업이 없거나 앱 작업 중일 때만 시작한다", arguments: Self.allTasks)
  func recordingRules(_ task: AndroidDeviceTask?) {
    let activity = AndroidRecordingActivity()
    #expect(activity.canStart(on: self.tablet, during: task) == Self.allowsCapture(task))
    #expect(!activity.canStart(on: .phoneSample, during: task))
    #expect(!activity.canStart(on: self.tablet.with(state: .booting), during: task))
    #expect(!activity.canStart(on: .unsupportedNameSample, during: task))
  }

  @Test("녹화 중(저장 중 포함)이면 그 기기의 끄기·삭제·초기화만 막고, 다른 기기와 녹화 전에는 막지 않는다")
  func recordingBlocks() {
    var activity = AndroidRecordingActivity()
    for task in Self.allTasks.compactMap(\.self) {
      #expect(!activity.blocks(task, on: self.tablet.id))
    }
    let began = activity.begin(on: self.tablet, during: nil)
    #expect(began)
    let beganAgain = activity.begin(on: self.tablet, during: nil)
    #expect(!beganAgain)
    _ = activity.requestStop(on: self.tablet.id)
    for task in Self.allTasks.compactMap(\.self) {
      let blocked = [AndroidDeviceTask.shutdown, .delete, .erase].contains(task)
      #expect(activity.blocks(task, on: self.tablet.id) == blocked, "\(task)")
      #expect(!activity.blocks(task, on: AndroidVirtualDevice.phoneSample.id))
    }
  }

  // MARK: - 녹화: 전이

  @Test("begin → 시작 중, 시작 신호 → 녹화 중(그 시각), 중지 → 저장 중(시작 시각·사용자 이유), end → 없음")
  func recordingTransitions() {
    var activity = AndroidRecordingActivity()
    let id = self.tablet.id
    let began = activity.begin(on: self.tablet, during: .launchApp)
    #expect(began)
    #expect(activity.phase(on: id) == .starting)
    #expect(activity.isActive)
    activity.started(at: self.started, on: id)
    activity.started(at: Date(timeIntervalSince1970: 2000), on: id)
    #expect(activity.phase(on: id) == .recording(startedAt: self.started))
    #expect(activity.stopReason(on: id) == nil)
    let stopped = activity.requestStop(on: id)
    #expect(stopped)
    #expect(activity.phase(on: id) == .stopping(startedAt: self.started, reason: .user))
    #expect(activity.stopReason(on: id) == .user)
    let stoppedAgain = activity.requestStop(on: id)
    #expect(!stoppedAgain)
    activity.started(at: Date(timeIntervalSince1970: 3000), on: id)
    #expect(activity.phase(on: id) == .stopping(startedAt: self.started, reason: .user))
    activity.end(on: id)
    #expect(!activity.isActive)
    let stoppedAfterEnd = activity.requestStop(on: id)
    #expect(!stoppedAfterEnd)
  }

  @Test("시작 중에 멈추면 시작 시각 없이 저장 중이 된다")
  func stopWhileStarting() {
    var activity = AndroidRecordingActivity()
    _ = activity.begin(on: self.tablet, during: nil)
    let stopped = activity.requestStop(on: self.tablet.id)
    #expect(stopped)
    #expect(activity.phase(on: self.tablet.id) == .stopping(startedAt: nil, reason: .user))
  }

  @Test("목록에서 없거나 꺼진 기기는 기기 꺼짐으로 멈추고, 켜짐·켜는 중으로 읽힌 기기는 멈추지 않는다")
  func requestStopsOnlyWhenGoneOrShutDown() {
    let second = AndroidVirtualDevice.secondPhoneSample.with(state: .booted)
    let third = AndroidVirtualDevice(
      id: .init("Third"), displayName: "셋째", systemImage: .sample, formFactor: .phone, state: .booted,
      availability: .available
    )
    var activity = AndroidRecordingActivity()
    for device in [self.tablet, second, third] {
      _ = activity.begin(on: device, during: nil)
    }
    // 태블릿은 켜는 중(adb 가 잠깐 답하지 않음), 둘째는 꺼짐, 셋째는 목록에 없음.
    let list = AndroidDeviceList(devices: [self.tablet.with(state: .booting), second.with(state: .shutdown)])
    let stopped = activity.requestStops(shutDownIn: list)
    #expect(Set(stopped) == [second.id, third.id])
    #expect(activity.phase(on: self.tablet.id) == .starting)
    #expect(activity.stopReason(on: second.id) == .deviceStopped)
    #expect(activity.stopReason(on: third.id) == .deviceStopped)
    // 이미 멈추는 중이면 다시 고르지 않는다.
    let stoppedAgain = activity.requestStops(shutDownIn: list)
    #expect(stoppedAgain.isEmpty)
  }

  @Test("처음 온 멈춤 이유만 남는다: 중지 뒤 목록 멈춤·전체 멈춤은 이유를 바꾸지 않고, 전체 멈춤은 남은 기기만 고른다")
  func firstReasonWins() {
    let second = AndroidVirtualDevice.secondPhoneSample.with(state: .booted)
    var activity = AndroidRecordingActivity()
    _ = activity.begin(on: self.tablet, during: nil)
    _ = activity.begin(on: second, during: nil)
    let stopped = activity.requestStop(on: self.tablet.id)
    #expect(stopped)
    let stoppedByList = activity.requestStops(shutDownIn: AndroidDeviceList(devices: [second]))
    #expect(stoppedByList.isEmpty)
    let stoppedAll = activity.requestStopAll()
    #expect(stoppedAll == [second.id])
    #expect(activity.stopReason(on: self.tablet.id) == .user)
    #expect(activity.stopReason(on: second.id) == .appTermination)
    let stoppedAllAgain = activity.requestStopAll()
    #expect(stoppedAllAgain.isEmpty)
  }
}
