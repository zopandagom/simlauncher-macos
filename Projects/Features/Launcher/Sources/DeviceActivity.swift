import Core
import DownloadInterface

/// 기기 하나에서 진행 중인 작업. 같은 기기의 작업은 겹치지 않는다.
public enum DeviceTask: Hashable, Sendable {
  case boot, shutdown, delete, erase
  /// 앱 설치 흐름 전체 ((URL 이면 받기 → 풀기 → 받은 파일 지우기 →) (zip 이면 풀기 →) 검사 → 필요하면 켜기 →
  /// Simulator 앱 열기 → 설치 → 실행 → 다시 읽기 (→ zip·URL 이면 임시 폴더 정리)). 받는 동안은 `DownloadStage` 도 있다.
  case installApp
  /// 링크 열기 흐름 전체 (필요하면 켜기 → Simulator 앱 열기 → 링크 열기 → 다시 읽기).
  case openURL
}

/// URL 설치의 받기 단계. 받기가 끝나면(성공) 단계가 사라지고 task `.installApp` 만 남는다(풀기·검사·설치·실행).
public enum DownloadStage: Hashable, Sendable {
  /// 받는 중. 응답 전이면 nil. 취소할 수 있다.
  case receiving(DownloadProgress?)
  /// 취소를 눌렀고 받기가 끝나기를 기다린다.
  case cancelling
}

/// 기기별 진행 작업과 "지금 이 기기에서 이 작업을 시작할 수 있나" 판정. Model 가드가 쓴다.
/// 이 화면이 지금 돌리는 작업(세션 상태)이라 Core 가 아니라 Feature 에 둔다. 기기만 보는 규칙은 Core 의 것을 부른다.
/// 바꾸는 메서드는 Model 만 부른다 (View 는 `model.activity` 를 읽기만 한다. 행은 `task(on:)` 와 받기 단계
/// `downloadStage(on:)` 로 진행 중 표시를 고른다).
public struct DeviceActivity: Hashable, Sendable {
  public private(set) var tasks: [VirtualDevice.ID: DeviceTask] = [:]
  /// URL 설치의 받기 단계. 있으면 그 기기의 task 는 `.installApp` 이다.
  public private(set) var downloads: [VirtualDevice.ID: DownloadStage] = [:]

  public init() {}

  /// 작업이 진행 중인 기기.
  public var busyDeviceIDs: Set<VirtualDevice.ID> {
    Set(self.tasks.keys)
  }

  public func task(on id: VirtualDevice.ID) -> DeviceTask? {
    self.tasks[id]
  }

  /// 진행 중인 작업이 없고 기기 규칙이 허용하면 true. 기기 규칙: boot = 쓸 수 있고 `.shutdown`,
  /// shutdown = `.booted`, delete = `deleteAvailability == .allowed`, erase = `eraseAvailability == .allowed`,
  /// installApp·openURL = `appInstallAvailability == .allowed` (링크 열기도 설치와 같이 꺼져 있으면 켜고 연다).
  public func canStart(_ task: DeviceTask, on device: VirtualDevice) -> Bool {
    guard self.tasks[device.id] == nil else { return false }
    return switch task {
    case .boot: device.availability == .available && device.state == .shutdown
    case .shutdown: device.state == .booted
    case .delete: device.deleteAvailability == .allowed
    case .erase: device.eraseAvailability == .allowed
    case .installApp, .openURL: device.appInstallAvailability == .allowed
    }
  }

  /// `canStart` 가 true 면 기록하고 true, 아니면 아무것도 바꾸지 않고 false.
  mutating func begin(_ task: DeviceTask, on device: VirtualDevice) -> Bool {
    guard self.canStart(task, on: device) else { return false }
    self.tasks[device.id] = task
    return true
  }

  /// 그 기기의 작업 기록과 받기 단계를 지운다. 없으면 아무것도 하지 않는다.
  mutating func end(on id: VirtualDevice.ID) {
    self.tasks[id] = nil
    self.downloads[id] = nil
  }
}

// MARK: - 받기 단계

extension DeviceActivity {
  public func downloadStage(on id: VirtualDevice.ID) -> DownloadStage? {
    self.downloads[id]
  }

  /// `begin(.installApp)` 이 true 면 받기 단계 `.receiving(nil)` 도 기록하고 true, 아니면 아무것도 바꾸지 않고 false.
  mutating func beginDownload(on device: VirtualDevice) -> Bool {
    guard self.begin(.installApp, on: device) else { return false }
    self.downloads[device.id] = .receiving(nil)
    return true
  }

  /// 받는 중일 때만 진행을 바꾼다 (취소 중·받기가 끝난 뒤 온 값은 무시한다).
  mutating func downloadProgressed(_ progress: DownloadProgress, on id: VirtualDevice.ID) {
    guard case .receiving = self.downloads[id] else { return }
    self.downloads[id] = .receiving(progress)
  }

  /// 받는 중이면 `.cancelling` 으로 바꾸고 true. 아니면(취소 중·받기가 끝남·작업 없음) 아무것도 바꾸지 않고 false.
  mutating func requestDownloadCancel(on id: VirtualDevice.ID) -> Bool {
    guard case .receiving = self.downloads[id] else { return false }
    self.downloads[id] = .cancelling
    return true
  }

  func isDownloadCancelRequested(on id: VirtualDevice.ID) -> Bool {
    self.downloads[id] == .cancelling
  }

  /// 받기 단계만 지운다 (task `.installApp` 은 남는다).
  mutating func downloadEnded(on id: VirtualDevice.ID) {
    self.downloads[id] = nil
  }
}
