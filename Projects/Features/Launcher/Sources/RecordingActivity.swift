import Core
import Foundation

/// 기기 하나의 녹화 단계.
public enum RecordingPhase: Hashable, Sendable {
  /// 예약·실행 전 확인·시작 신호를 기다리는 중. 멈출 수 있다.
  case starting
  /// 시작 신호를 받았다. 경과 시간은 이 시각부터.
  case recording(startedAt: Date)
  /// 멈추기를 요청했고 마무리·저장(Finder 보이기까지)을 기다린다. 시작 신호 전에 멈췄으면 startedAt 은 nil.
  case stopping(startedAt: Date?, reason: RecordingStopReason)
}

/// 녹화를 멈춘 이유. 흐름 끝의 알림을 고른다.
public enum RecordingStopReason: Hashable, Sendable {
  /// 행의 "중지".
  case user
  /// 다시 읽은 목록에서 기기가 켜져 있지 않거나 없다 (저장되면 정보 알림).
  case deviceStopped
  /// 앱 종료 요청.
  case appTermination
}

/// 기기별 녹화 단계. 기기 작업(`DeviceActivity`)과 따로 두어 앱 설치·링크 열기 중에도 녹화할 수 있다.
/// 이 화면이 지금 돌리는 작업(세션 상태)이라 Core 가 아니라 Feature 에 둔다. 기기만 보는 허용 규칙은 스크린샷과 같은
/// Core 의 `screenshotAvailability` 를 쓴다. 바꾸는 메서드는 Model 만 부른다 (View 는 `model.recordings` 를 읽기만 한다).
/// 멈춘 이유는 처음 온 것만 남는다 (멈추는 중에 온 다른 멈춤 요청은 아무것도 바꾸지 않는다).
public struct RecordingActivity: Hashable, Sendable {
  public private(set) var phases: [VirtualDevice.ID: RecordingPhase] = [:]

  public init() {}

  public func phase(on id: VirtualDevice.ID) -> RecordingPhase? {
    self.phases[id]
  }

  /// 단계가 있으면 true (저장 중 포함).
  public func isRecording(on id: VirtualDevice.ID) -> Bool {
    self.phases[id] != nil
  }

  /// 어느 기기든 단계가 있으면 true (저장 중 포함). 앱 종료 확인이 읽는다.
  public var isActive: Bool {
    !self.phases.isEmpty
  }

  /// 이 기기에서 녹화 중이 아니고, `screenshotAvailability == .allowed` 이고, 같은 기기의 기기 작업이 없거나
  /// `.installApp`·`.openURL` 이면 true. 작업은 모든 케이스를 적는 허용 목록이다 (`default` 없음: 새 `DeviceTask` 케이스가
  /// 생기면 컴파일러가 여기서 멈춘다). `.boot` 는 `ScreenshotActivity.canStart` 와 같은 이유로 막는다.
  public func canStart(on device: VirtualDevice, during task: DeviceTask?) -> Bool {
    guard !self.isRecording(on: device.id), device.screenshotAvailability == .allowed else { return false }
    return switch task {
    case .none, .installApp, .openURL: true
    case .boot, .shutdown, .delete, .erase: false
    }
  }

  /// 이 기기가 녹화 중(저장 중 포함)이면 끄기·삭제·초기화를 막는다. 작업은 모든 케이스를 적는다 (`default` 없음).
  /// `.boot` 는 녹화가 켜진 기기에만 있어 해당 없고, `.installApp`·`.openURL` 은 녹화 중에도 한다.
  public func blocks(_ task: DeviceTask, on id: VirtualDevice.ID) -> Bool {
    guard self.isRecording(on: id) else { return false }
    return switch task {
    case .shutdown, .delete, .erase: true
    case .boot, .installApp, .openURL: false
    }
  }

  /// 지금 멈추는 중이면 그 이유, 아니면 nil.
  public func stopReason(on id: VirtualDevice.ID) -> RecordingStopReason? {
    guard case let .stopping(_, reason) = self.phases[id] else { return nil }
    return reason
  }

  /// `canStart` 가 true 면 `.starting` 으로 기록하고 true, 아니면 아무것도 바꾸지 않고 false.
  mutating func begin(on device: VirtualDevice, during task: DeviceTask?) -> Bool {
    guard self.canStart(on: device, during: task) else { return false }
    self.phases[device.id] = .starting
    return true
  }

  /// 시작 신호. `.starting` 일 때만 `.recording(startedAt:)` 으로 바꾼다 (멈추는 중에 늦게 온 신호는 무시).
  mutating func started(at date: Date, on id: VirtualDevice.ID) {
    guard self.phases[id] == .starting else { return }
    self.phases[id] = .recording(startedAt: date)
  }

  /// 행의 "중지". 시작 중·녹화 중이면 `.stopping(reason: .user)` 으로 바꾸고 true (호출한 쪽이 녹화 Task 를 취소한다).
  /// 단계가 없거나 이미 멈추는 중이면 false.
  mutating func requestStop(on id: VirtualDevice.ID) -> Bool {
    self.requestStop(on: id, reason: .user)
  }

  /// 단계가 시작 중·녹화 중이고 `list` 에서 그 기기가 없거나 `.booted` 가 아니면 `.stopping(reason: .deviceStopped)` 으로
  /// 바꾸고 그 id 들을 돌려준다 (simctl 은 기기가 꺼져도 끝나지 않는다, 측정).
  mutating func requestStops(notBootedIn list: DeviceList) -> [VirtualDevice.ID] {
    let ids = self.phases.keys.filter { list.device(id: $0)?.state != .booted }
    return ids.filter { self.requestStop(on: $0, reason: .deviceStopped) }
  }

  /// 시작 중·녹화 중인 모든 기기를 `.stopping(reason: .appTermination)` 으로 바꾸고 그 id 들을 돌려준다 (앱 종료).
  mutating func requestStopAll() -> [VirtualDevice.ID] {
    let ids = Array(self.phases.keys)
    return ids.filter { self.requestStop(on: $0, reason: .appTermination) }
  }

  /// 그 기기의 녹화 기록을 지운다. 없으면 아무것도 하지 않는다.
  mutating func end(on id: VirtualDevice.ID) {
    self.phases[id] = nil
  }

  private mutating func requestStop(on id: VirtualDevice.ID, reason: RecordingStopReason) -> Bool {
    switch self.phases[id] {
    case .starting:
      self.phases[id] = .stopping(startedAt: nil, reason: reason)
      return true
    case let .recording(startedAt):
      self.phases[id] = .stopping(startedAt: startedAt, reason: reason)
      return true
    case .stopping, .none:
      return false
    }
  }
}
