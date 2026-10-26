import Core
import DownloadInterface

/// 기기 하나에서 진행 중인 작업. 같은 기기의 작업은 겹치지 않는다.
public enum DeviceTask: Hashable, Sendable {
  case boot, shutdown, delete, erase
  /// 앱 설치 흐름 전체 ((URL·카탈로그 버전이면 받기 → 풀기 → 받은 파일 지우기 →) (zip 이면 풀기 →) 검사 → 필요하면 켜기 →
  /// Simulator 앱 열기 → 설치 → 실행 → 다시 읽기 (→ zip·URL·카탈로그 버전이면 임시 폴더 정리)). 받는 동안은 `DownloadStage` 도 있다.
  case installApp
  /// 링크 열기 흐름 전체 (필요하면 켜기 → Simulator 앱 열기 → 링크 열기 → 다시 읽기).
  case openURL
}

/// URL·카탈로그 버전 설치의 받기 단계. 받기가 끝나면(성공) 단계가 사라지고 task `.installApp` 만 남는다(풀기·검사·설치·실행).
/// 여러 기기 설치는 받기 묶음 하나로 받아, 대상 기기 모두가 같은 단계를 보이고 함께 취소된다.
public enum DownloadStage: Hashable, Sendable {
  /// 받는 중. 응답 전이면 nil. 취소할 수 있다.
  case receiving(DownloadProgress?)
  /// 취소를 눌렀고 받기가 끝나기를 기다린다.
  case cancelling
}

/// 기기별 진행 작업과 "지금 이 기기에서 이 작업을 시작할 수 있나" 판정. Model 가드가 쓴다.
/// 이 화면이 지금 돌리는 작업(세션 상태)이라 Core 가 아니라 Feature 에 둔다. 기기만 보는 규칙은 Core 의 것을 부른다.
/// 바꾸는 메서드는 Model 만 부른다 (View 는 `model.activity` 를 읽기만 한다. 행은 `task(on:)` 와 받기 단계
/// `downloadStage(on:)`, 받기 묶음 크기 `downloadGroupSize(on:)` 로 진행 중 표시를 고른다).
/// 여러 기기 묶음이 시작한 기록에는 소유자 번호를 붙여, 먼저 끝나 풀린 기기에 새로 시작한 작업을 묶음의 끝이 지우지 않게 한다.
/// 같음 비교는 기록만 본다 (다음 번호는 보지 않는다).
public struct DeviceActivity: Hashable, Sendable {
  public private(set) var tasks: [VirtualDevice.ID: DeviceTask] = [:]
  /// URL 설치의 받기 단계. 있으면 그 기기의 task 는 `.installApp` 이다.
  public private(set) var downloads: [VirtualDevice.ID: DownloadStage] = [:]
  /// 받는 기기의 받기 묶음 번호. 같은 번호의 기기는 같은 받기를 보이고 함께 취소된다.
  private var downloadGroups: [VirtualDevice.ID: Int] = [:]
  private var nextDownloadGroup = 0
  /// 여러 기기 묶음이 시작한 기록의 소유자 번호. 한 기기 경로(`begin`)의 기록에는 없다.
  private var owners: [VirtualDevice.ID: Int] = [:]
  private var nextOwner = 0

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

  /// 그 기기의 작업 기록과 받기 단계(묶음 번호 포함)·소유자 번호를 지운다. 없으면 아무것도 하지 않는다.
  mutating func end(on id: VirtualDevice.ID) {
    self.tasks[id] = nil
    self.downloads[id] = nil
    self.downloadGroups[id] = nil
    self.owners[id] = nil
  }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.tasks == rhs.tasks && lhs.downloads == rhs.downloads && lhs.downloadGroups == rhs.downloadGroups
      && lhs.owners == rhs.owners
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(self.tasks)
    hasher.combine(self.downloads)
    hasher.combine(self.downloadGroups)
    hasher.combine(self.owners)
  }
}

// MARK: - 묶음 소유자

extension DeviceActivity {
  /// 기록이 있는 기기들에 새 소유자 번호를 붙이고 그 번호를 돌려준다 (기기가 없어도 번호를 돌려준다).
  mutating func own(_ ids: [VirtualDevice.ID]) -> Int {
    self.nextOwner += 1
    for id in ids where self.tasks[id] != nil {
      self.owners[id] = self.nextOwner
    }
    return self.nextOwner
  }

  /// 그 기기의 기록이 이 소유자 번호일 때만 지운다 (작업·받기 단계·묶음 번호·소유자). 다르거나 없으면 아무것도 하지 않는다.
  mutating func end(on ids: [VirtualDevice.ID], owner: Int) {
    for id in ids where self.owners[id] == owner {
      self.end(on: id)
    }
  }
}

// MARK: - 받기 단계

extension DeviceActivity {
  public func downloadStage(on id: VirtualDevice.ID) -> DownloadStage? {
    self.downloads[id]
  }

  /// `begin(.installApp)` 이 true 면 받기 단계 `.receiving(nil)` 도 기록하고 true, 아니면 아무것도 바꾸지 않고 false (1대 묶음).
  mutating func beginDownload(on device: VirtualDevice) -> Bool {
    !self.beginDownload(on: [device]).isEmpty
  }

  /// 기기마다 `begin(.installApp)` 이 true 면 받기 단계 `.receiving(nil)` 을 기록하고, 시작한 기기 모두에 같은 묶음 번호를 붙인다.
  /// 시작한 기기를 넘긴 순서로 돌려준다.
  mutating func beginDownload(on devices: [VirtualDevice]) -> [VirtualDevice] {
    var begun: [VirtualDevice] = []
    for device in devices where self.begin(.installApp, on: device) {
      begun.append(device)
    }
    guard !begun.isEmpty else { return [] }
    self.nextDownloadGroup += 1
    for device in begun {
      self.downloads[device.id] = .receiving(nil)
      self.downloadGroups[device.id] = self.nextDownloadGroup
    }
    return begun
  }

  /// 받는 중일 때만 진행을 바꾼다 (취소 중·받기가 끝난 뒤 온 값은 무시한다).
  mutating func downloadProgressed(_ progress: DownloadProgress, on id: VirtualDevice.ID) {
    guard case .receiving = self.downloads[id] else { return }
    self.downloads[id] = .receiving(progress)
  }

  /// 받기 묶음의 기기마다 받는 중일 때만 진행을 바꾼다.
  mutating func downloadProgressed(_ progress: DownloadProgress, on ids: [VirtualDevice.ID]) {
    for id in ids {
      self.downloadProgressed(progress, on: id)
    }
  }

  /// 받는 중이면 같은 받기 묶음의 받는 중인 기기 모두를 `.cancelling` 으로 바꾸고 true.
  /// 아니면(취소 중·받기가 끝남·작업 없음) 아무것도 바꾸지 않고 false.
  mutating func requestDownloadCancel(on id: VirtualDevice.ID) -> Bool {
    guard case .receiving = self.downloads[id] else { return false }
    for member in self.downloadGroupMembers(of: id) {
      self.downloads[member] = .cancelling
    }
    return true
  }

  /// 같은 받기 묶음에서 받는 중인 기기 수. 받는 중이 아니면 0. 행 취소 툴팁이 2 이상이면 묶음 문구를 보인다.
  public func downloadGroupSize(on id: VirtualDevice.ID) -> Int {
    guard case .receiving = self.downloads[id] else { return 0 }
    return self.downloadGroupMembers(of: id).count(where: { member in
      if case .receiving = self.downloads[member] {
        true
      } else {
        false
      }
    })
  }

  func isDownloadCancelRequested(on id: VirtualDevice.ID) -> Bool {
    self.downloads[id] == .cancelling
  }

  /// 받기 단계만 지운다 (task `.installApp` 은 남는다).
  mutating func downloadEnded(on id: VirtualDevice.ID) {
    self.downloads[id] = nil
    self.downloadGroups[id] = nil
  }

  /// 받기 묶음의 받기 단계만 지운다.
  mutating func downloadEnded(on ids: [VirtualDevice.ID]) {
    for id in ids {
      self.downloadEnded(on: id)
    }
  }

  /// 그 기기와 같은 받기 묶음의 기기 (그 기기 포함). 묶음 번호가 없으면 그 기기 하나.
  private func downloadGroupMembers(of id: VirtualDevice.ID) -> [VirtualDevice.ID] {
    guard let group = self.downloadGroups[id] else { return [id] }
    return self.downloadGroups.filter { $0.value == group }.map(\.key)
  }
}
