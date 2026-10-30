import Core
import DownloadInterface

/// 기기 하나에서 앱이 진행 중인 작업. 같은 기기의 작업은 겹치지 않는다.
public enum AndroidDeviceTask: Hashable, Sendable {
  /// 켜기 (emulator 를 띄우고 부팅 완료까지). 이 동안은 끄기를 막는다 (켜는 중에 끄면 기기가 망가질 수 있다, 실측).
  case boot
  case shutdown
  case delete
  case erase
  /// (URL·카탈로그면 받기 →) apk 검사 → 기기 값 → 판정 → 설치 → 실행 (켜진 기기만). 받는 동안은 `AndroidDownloadStage` 도 있다.
  case installApp
  /// 행 "앱 실행…" 시트에서 고른 앱 실행 (켜진 기기만).
  case launchApp
  /// 행 "링크 열기…" 시트의 링크 열기 (켜진 기기만).
  case openURL
}

/// URL·카탈로그에서 설치의 받기 단계 (작업은 `.installApp`). 받기가 끝나면(성공·실패·취소) 지운다.
/// 여러 기기 설치는 받기 묶음 하나로 받아, 대상 기기 모두가 같은 단계를 보이고 함께 취소된다.
public enum AndroidDownloadStage: Hashable, Sendable {
  /// 받는 중. 응답 전이면 nil.
  case receiving(DownloadProgress?)
  /// 취소를 눌렀고 받기가 멈추기를 기다린다.
  case cancelling
}

/// 기기별 진행 작업과 "지금 이 기기에서 이 작업을 시작할 수 있나" 판정. Model 가드와 View(행의 진행 표시)가 쓴다.
/// 이 화면이 지금 돌리는 작업(세션 상태)이라 Core 가 아니라 Feature 에 둔다. 기기만 보는 규칙은 Core 의 것을 부른다.
/// iOS 기기 목록의 `DeviceActivity` 와 같은 규칙이지만 Feature 끼리 공유하지 않으므로 따로 둔다. 여러 기기 설치는 받기 묶음
/// 하나로 받아(행은 받기 단계 `downloadStage(on:)` 와 묶음 크기 `downloadGroupSize(on:)` 로 진행·취소를 보인다) 어느 행에서든
/// 함께 취소된다. 바꾸는 메서드는 Model 만 부른다. 함께 켜기·여러 기기 설치가 시작한 기록에는 소유자 번호를 붙여, 먼저 끝나
/// 풀린 기기에 새로 시작한 작업을 묶음의 끝이 지우지 않게 한다. 같음 비교는 기록만 본다 (다음 번호는 보지 않는다).
public struct AndroidDeviceActivity: Hashable, Sendable {
  public private(set) var tasks: [AndroidVirtualDevice.ID: AndroidDeviceTask] = [:]
  /// URL·카탈로그에서 설치 중 받는 단계. 작업이 `.installApp` 인 기기에만 있다.
  public private(set) var downloads: [AndroidVirtualDevice.ID: AndroidDownloadStage] = [:]
  /// 받는 기기의 받기 묶음 번호. 같은 번호의 기기는 같은 받기를 보이고 함께 취소된다.
  private var downloadGroups: [AndroidVirtualDevice.ID: Int] = [:]
  private var nextDownloadGroup = 0
  /// 함께 켜기·여러 기기 설치가 시작한 기록의 소유자 번호. 한 기기 경로(`begin`)의 기록에는 없다.
  private var owners: [AndroidVirtualDevice.ID: Int] = [:]
  private var nextOwner = 0

  public init() {}

  /// 작업이 진행 중인 기기.
  public var busyDeviceIDs: Set<AndroidVirtualDevice.ID> {
    Set(self.tasks.keys)
  }

  public func task(on id: AndroidVirtualDevice.ID) -> AndroidDeviceTask? {
    self.tasks[id]
  }

  public func downloadStage(on id: AndroidVirtualDevice.ID) -> AndroidDownloadStage? {
    self.downloads[id]
  }

  /// 진행 중인 작업이 없고 기기 규칙이 허용하면 true. 기기 규칙: boot = `canBoot`(쓸 수 있고 꺼짐),
  /// shutdown = `canShutdown`(켜는 중·켜짐. 앱이 켜는 중인 기기는 위의 작업 기록이 막는다),
  /// delete = `deleteAvailability == .allowed`, erase = `eraseAvailability == .allowed`,
  /// 앱 설치·실행·링크 열기 = `appActionAvailability == .allowed`(쓸 수 있고 켜짐).
  public func canStart(_ task: AndroidDeviceTask, on device: AndroidVirtualDevice) -> Bool {
    guard self.tasks[device.id] == nil else { return false }
    return switch task {
    case .boot: device.canBoot
    case .shutdown: device.canShutdown
    case .delete: device.deleteAvailability == .allowed
    case .erase: device.eraseAvailability == .allowed
    case .installApp, .launchApp, .openURL: device.appActionAvailability == .allowed
    }
  }

  /// `canStart` 가 true 면 기록하고 true, 아니면 아무것도 바꾸지 않고 false.
  mutating func begin(_ task: AndroidDeviceTask, on device: AndroidVirtualDevice) -> Bool {
    guard self.canStart(task, on: device) else { return false }
    self.tasks[device.id] = task
    return true
  }

  /// 그 기기의 작업 기록·받기 단계(묶음 번호 포함)·소유자 번호를 지운다. 없으면 아무것도 하지 않는다.
  mutating func end(on id: AndroidVirtualDevice.ID) {
    self.tasks[id] = nil
    self.downloads[id] = nil
    self.downloadGroups[id] = nil
    self.owners[id] = nil
  }

  /// `canStart(task, on:)` 가 true 인 기기만 시작하고, 시작한 기기에 새 소유자 번호를 붙인다 (기기가 없어도 번호를 돌려준다).
  /// 시작한 기기를 넘긴 순서로 돌려준다.
  mutating func beginAll(
    _ task: AndroidDeviceTask,
    on devices: [AndroidVirtualDevice]
  ) -> (begun: [AndroidVirtualDevice], owner: Int) {
    var begun: [AndroidVirtualDevice] = []
    for device in devices where self.begin(task, on: device) {
      begun.append(device)
    }
    return (begun, self.own(begun.map(\.id)))
  }

  /// 기록이 있는 기기들에 새 소유자 번호를 붙이고 그 번호를 돌려준다 (기기가 없어도 번호를 돌려준다).
  mutating func own(_ ids: [AndroidVirtualDevice.ID]) -> Int {
    self.nextOwner += 1
    for id in ids where self.tasks[id] != nil {
      self.owners[id] = self.nextOwner
    }
    return self.nextOwner
  }

  /// 그 기기의 기록이 이 소유자 번호일 때만 지운다. 다르거나 없으면 아무것도 하지 않는다.
  mutating func end(on id: AndroidVirtualDevice.ID, owner: Int) {
    guard self.owners[id] == owner else { return }
    self.end(on: id)
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

// MARK: - 받기 단계

extension AndroidDeviceActivity {
  /// `begin(.installApp)` 이 true 면 받기 단계 `.receiving(nil)` 도 기록하고 true, 아니면 아무것도 바꾸지 않고 false (1대 묶음).
  mutating func beginDownload(on device: AndroidVirtualDevice) -> Bool {
    !self.beginDownload(on: [device]).isEmpty
  }

  /// 기기마다 `begin(.installApp)` 이 true 면 받기 단계 `.receiving(nil)` 을 기록하고, 시작한 기기 모두에 같은 묶음 번호를 붙인다.
  /// 시작한 기기를 넘긴 순서로 돌려준다.
  mutating func beginDownload(on devices: [AndroidVirtualDevice]) -> [AndroidVirtualDevice] {
    var begun: [AndroidVirtualDevice] = []
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

  /// 받는 중일 때만 진행을 바꾼다 (취소 중·받기가 끝난 뒤에 온 진행은 버린다).
  mutating func downloadProgressed(_ progress: DownloadProgress, on id: AndroidVirtualDevice.ID) {
    guard case .receiving = self.downloads[id] else { return }
    self.downloads[id] = .receiving(progress)
  }

  /// 받기 묶음의 기기마다 받는 중일 때만 진행을 바꾼다.
  mutating func downloadProgressed(_ progress: DownloadProgress, on ids: [AndroidVirtualDevice.ID]) {
    for id in ids {
      self.downloadProgressed(progress, on: id)
    }
  }

  /// 받는 중이면 같은 받기 묶음의 받는 중인 기기 모두를 `.cancelling` 으로 바꾸고 true.
  /// 아니면(취소 중·받기가 끝남·작업 없음) 아무것도 바꾸지 않고 false.
  mutating func requestDownloadCancel(on id: AndroidVirtualDevice.ID) -> Bool {
    guard case .receiving = self.downloads[id] else { return false }
    for member in self.downloadGroupMembers(of: id) {
      self.downloads[member] = .cancelling
    }
    return true
  }

  /// 같은 받기 묶음에서 받는 중인 기기 수. 받는 중이 아니면 0. 행 취소 툴팁이 2 이상이면 묶음 문구를 보인다.
  public func downloadGroupSize(on id: AndroidVirtualDevice.ID) -> Int {
    guard case .receiving = self.downloads[id] else { return 0 }
    return self.downloadGroupMembers(of: id).count(where: { member in
      if case .receiving = self.downloads[member] {
        true
      } else {
        false
      }
    })
  }

  /// 받기 취소를 눌렀다 (받기가 끝난 뒤 결과를 보기 전에 읽는다).
  func isDownloadCancelRequested(on id: AndroidVirtualDevice.ID) -> Bool {
    self.downloads[id] == .cancelling
  }

  /// 받기 묶음의 받기 단계만 지운다 (작업 `.installApp` 은 검사·설치 동안 남는다).
  mutating func downloadEnded(on ids: [AndroidVirtualDevice.ID]) {
    for id in ids {
      self.downloads[id] = nil
      self.downloadGroups[id] = nil
    }
  }

  /// 그 기기와 같은 받기 묶음의 기기 (그 기기 포함). 묶음 번호가 없으면 그 기기 하나.
  private func downloadGroupMembers(of id: AndroidVirtualDevice.ID) -> [AndroidVirtualDevice.ID] {
    guard let group = self.downloadGroups[id] else { return [id] }
    return self.downloadGroups.filter { $0.value == group }.map(\.key)
  }
}
