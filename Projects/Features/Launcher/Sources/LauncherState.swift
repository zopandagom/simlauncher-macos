import AppBundleInterface
import Core
import DownloadInterface
import SimulatorInterface
import WorkspaceInterface

/// 기기 목록 화면의 상태.
public enum LauncherListState: Hashable, Sendable {
  /// 목록이 없고 읽는 중이다.
  case loading
  /// 읽은 목록. 다시 읽는 동안에도 마지막 목록을 유지한다.
  case loaded(DeviceList)
  /// 목록을 한 번도 읽지 못했다 (전체 화면 오류).
  case failed(SimulatorError)
}

/// 목록 위에 띄우는 알림. 기기 작업(켜기·끄기·만들기·삭제·초기화·앱 설치(URL·카탈로그 버전의 받기 포함)·실행·링크 열기·스크린샷·
/// 녹화) 실패와, 목록이 있을 때의 새로 고침 실패. 여러 기기 설치·켜기는 공통 단계 실패 또는 기기별 결과를 알림 하나에 모은다.
/// 정보 알림은 기기가 꺼져 녹화를 자동으로 멈추고 저장한 것 하나다.
public enum LauncherNotice: Hashable, Sendable {
  /// 알림에 보일 기기. 누른 시점의 값이라, 실패 뒤 목록에서 사라져도 그대로 보인다.
  public struct Device: Hashable, Sendable {
    /// 기기 이름 (번역하지 않는 사용자 데이터).
    public let name: String
    /// 런타임 이름, 예 "iOS 26.0". OS 마다 같은 이름의 기기가 있어 함께 보인다.
    public let runtimeName: String

    public init(name: String, runtimeName: String) {
      self.name = name
      self.runtimeName = runtimeName
    }

    /// 지금 목록의 기기 값으로 만든다.
    public init(_ device: VirtualDevice) {
      self.init(name: device.name, runtimeName: device.runtime.name)
    }
  }

  case refreshFailed(SimulatorError)
  case bootFailed(Device, SimulatorError)
  case shutdownFailed(Device, SimulatorError)
  /// 기기는 켜졌지만 Simulator 앱을 열지 못했다.
  case openAppFailed(Device, SimulatorError)
  /// 기기를 만들지 못했다. Device 는 입력한(앞뒤 공백을 뺀) 이름과 고른 런타임 이름이다.
  case createFailed(Device, SimulatorError)
  case deleteFailed(Device, SimulatorError)
  case eraseFailed(Device, SimulatorError)
  /// 앱을 설치하지 못했다 (설치 명령 전 거절, URL·카탈로그 버전의 받기·받은 파일 풀기 실패 포함). Device 는 누른 시점의 기기.
  case installFailed(Device, AppInstallFailure)
  /// 앱은 설치했지만 실행하지 못했다.
  case launchFailed(Device, SimulatorError)
  /// 링크를 열지 못했다 (명령 전 거절 포함). Device 는 "링크 열기…" 를 누른 시점의 기기.
  case openURLFailed(Device, OpenURLFailure)
  /// 스크린샷을 저장하지 못했다 (예약·촬영 실패). Device 는 누른 시점의 기기.
  case screenshotFailed(Device, ScreenshotFailure)
  /// 스크린샷을 저장했지만 Finder 에서 보이지 못했다.
  case screenshotRevealFailed(Device, WorkspaceError)
  /// 녹화를 시작하지 못했거나 저장하지 못했다 (예약·시작·저장 실패). Device 는 "녹화" 를 누른 시점의 기기.
  case recordingFailed(Device, RecordingFailure)
  /// simctl 이 스스로 실패로 끝났지만 끝난 데까지 저장했다 (Finder 에서 보였다).
  case recordingInterrupted(Device)
  /// 정보 알림: 다시 읽은 목록에서 기기가 꺼져 있거나 없어 녹화를 자동으로 멈추고 저장했다 (Finder 에서 보였다).
  case recordingStoppedByDevice(Device)
  /// 녹화를 저장했지만 Finder 에서 보이지 못했다.
  case recordingRevealFailed(Device, WorkspaceError)
  /// 여러 기기 설치의 공통 단계(받기·풀기·검사) 실패. Device 들은 요청한 대상 (누른 시점).
  case batchInstallFailed([Device], AppInstallFailure)
  /// 여러 기기 설치·켜기의 기기별 결과. 실패·건너뜀이 하나라도 있을 때만 쌓는다.
  case batchFinished(BatchReport)
}

/// 여러 기기 동작의 대상 한 대. 누른 시점의 id 와 알림에 보일 이름·런타임 이름.
public struct TargetDevice: Hashable, Sendable {
  public let id: VirtualDevice.ID
  public let label: LauncherNotice.Device

  public init(id: VirtualDevice.ID, label: LauncherNotice.Device) {
    self.id = id
    self.label = label
  }

  /// 지금 목록의 기기 값으로 만든다.
  public init(_ device: VirtualDevice) {
    self.init(id: device.id, label: LauncherNotice.Device(device))
  }
}

/// 여러 기기 설치·켜기의 기기별 결과 (`LauncherNotice.batchFinished`).
public struct BatchReport: Hashable, Sendable {
  public enum Action: Hashable, Sendable {
    case install, boot
  }

  public struct Entry: Hashable, Sendable {
    public let device: LauncherNotice.Device
    public let result: BatchDeviceResult

    public init(device: LauncherNotice.Device, result: BatchDeviceResult) {
      self.device = device
      self.result = result
    }
  }

  public let action: Action
  /// 요청 순서(목록 순서). 건너뛴 기기도 같은 자리에 넣는다.
  public let entries: [Entry]
  /// Simulator 앱 열기 실패 (기기마다 같은 에러라 하나만).
  public let simulatorAppError: SimulatorError?

  public init(action: Action, entries: [Entry], simulatorAppError: SimulatorError?) {
    self.action = action
    self.entries = entries
    self.simulatorAppError = simulatorAppError
  }

  /// 성공한 기기 수. 설치는 실행에 실패해도 설치는 됐으므로 센다. 켜기는 켠 기기만 센다.
  public var successCount: Int {
    self.entries.count(where: { entry in
      switch entry.result {
      case .succeeded: true
      case .launchFailed: self.action == .install
      case .installFailed, .bootFailed: false
      }
    })
  }

  /// 실패·건너뜀이나 Simulator 앱 열기 실패가 있으면 알린다 (모두 성공이면 한 기기 설치처럼 알림이 없다).
  var needsNotice: Bool {
    self.simulatorAppError != nil || self.entries.contains { $0.result != .succeeded }
  }
}

/// 여러 기기 동작에서 기기 한 대의 결과.
public enum BatchDeviceResult: Hashable, Sendable {
  /// 설치: 설치하고 실행함. 켜기: 켬.
  case succeeded
  /// 시작 판정·기기별 판정·설치 명령 실패 (`deviceBusy` 포함).
  case installFailed(AppInstallFailure)
  /// 설치는 됐지만 실행하지 못했다.
  case launchFailed(SimulatorError)
  case bootFailed(SimulatorError)
}

/// 앱 설치 흐름의 실패 원인 (켜기·앱 열기 실패는 기존 bootFailed·openAppFailed 를 쓴다).
public enum AppInstallFailure: Hashable, Sendable {
  /// 끌어다 놓은 항목이 둘 이상이다.
  case multipleItems
  /// 고른·끌어다 놓은 zip 의 풀기 실패와 모든 .app 검사 실패 (받은 zip 의 풀기 실패는 `.downloadedNotZip`·`.downloadedZip`,
  /// 카탈로그 버전이면 `.catalogDownloadedNotZip`·`.catalogDownloadedZip`).
  case bundle(AppBundleError)
  /// URL 에서 받지 못했다 (취소를 누르지 않았는데 온 `.cancelled` 포함).
  case download(DownloadError)
  /// 받은 내용이 zip 으로 읽히지 않는다. 응답 형식이 웹 페이지(HTML)면 `isWebPage` (로그인 페이지 등).
  case downloadedNotZip(isWebPage: Bool)
  /// 받은 zip 을 풀지 못했다 (zip 으로 읽히지 않는 경우 밖).
  case downloadedZip(AppBundleError)
  /// 카탈로그 버전의 빌드를 받지 못했다 (원인은 `.download` 와 같다. 문구는 `LauncherText.catalogInstallMessage(for:)` 가 고르고,
  /// 빌드 주소와 관계없는 원인은 URL 설치와 같은 문구다).
  case catalogDownload(DownloadError)
  /// 카탈로그 버전에서 받은 내용이 zip 으로 읽히지 않는다. 응답 형식이 웹 페이지(HTML)면 `isWebPage`.
  case catalogDownloadedNotZip(isWebPage: Bool)
  /// 카탈로그 버전에서 받은 zip 을 풀지 못했다 (zip 으로 읽히지 않는 경우 밖).
  case catalogDownloadedZip(AppBundleError)
  /// Core 판정 거절.
  case rejected(AppInstallProblem)
  /// 검사하는 사이 기기가 설치할 수 없는 상태가 됐다.
  case deviceNotReady(AppInstallBlockReason)
  /// install 명령 실패, 또는 검사하는 사이 기기가 목록에서 사라짐(`.deviceNotFound`).
  case simulator(SimulatorError)
  /// 여러 기기 설치를 시작할 때 그 기기에서 다른 작업이 진행 중이라 건너뛰었다 (한 기기 흐름은 알림 없이 끝내 쓰지 않는다).
  case deviceBusy
}

/// App 이 LauncherModel 에 넘기는 카탈로그 버전 설치 요청 (`CatalogInstallModel` 이 만들고 `catalogInstallRequested(_:)` 가 받는다).
/// 대상은 행 메뉴면 1대, 툴바면 고른 기기 전부다.
public struct CatalogInstallRequest: Hashable, Sendable {
  public let targets: [TargetDevice]
  public let buildURL: DownloadURL

  public init(targets: [TargetDevice], buildURL: DownloadURL) {
    self.targets = targets
    self.buildURL = buildURL
  }

  /// 기기 한 대짜리 요청.
  public init(deviceID: VirtualDevice.ID, device: LauncherNotice.Device, buildURL: DownloadURL) {
    self.init(targets: [TargetDevice(id: deviceID, label: device)], buildURL: buildURL)
  }
}

extension DeviceList {
  /// 목록에 보이는 모든 기기의 id (선택 정리에 쓴다).
  var deviceIDs: Set<VirtualDevice.ID> {
    Set(self.sections.flatMap { $0.devices.map(\.id) })
  }
}

/// 받은 빌드의 출처. 받기·받은 파일 실패 문구를 고르는 출처 (입력한 주소는 사용자가 고칠 수 있고, 카탈로그 버전은 고칠 수 없다).
/// 빌드 주소와 관계없는 원인은 두 출처가 같은 문구다 (어느 원인이 다른지는 `LauncherText+CatalogInstall.swift` 머리 주석).
enum DownloadOrigin: Hashable, Sendable {
  case enteredURL
  case catalog
}

extension AppInstallFailure {
  /// 받기 실패를 출처에 맞는 케이스로.
  static func download(_ error: DownloadError, from origin: DownloadOrigin) -> AppInstallFailure {
    switch origin {
    case .enteredURL: .download(error)
    case .catalog: .catalogDownload(error)
    }
  }

  /// 받은 파일의 풀기 실패. zip 으로 읽히지 않으면(`.zipUnreadable`) 응답 형식으로 웹 페이지인지 나눈다
  /// (zip 인지는 내용으로 판정하고, 형식은 문구만 고른다. 잘못된 형식으로 온 zip 도 설치된다).
  static func downloaded(
    _ error: AppBundleError,
    mimeType: String?,
    from origin: DownloadOrigin = .enteredURL
  ) -> AppInstallFailure {
    guard error == .zipUnreadable else {
      return origin == .catalog ? .catalogDownloadedZip(error) : .downloadedZip(error)
    }
    let webPageTypes: Set = ["text/html", "application/xhtml+xml"]
    let isWebPage = webPageTypes.contains(mimeType?.lowercased() ?? "")
    return origin == .catalog ? .catalogDownloadedNotZip(isWebPage: isWebPage) : .downloadedNotZip(isWebPage: isWebPage)
  }
}

/// 링크 열기 흐름의 실패 원인 (켜기·앱 열기 실패는 설치와 같이 기존 bootFailed·openAppFailed 를 쓴다).
public enum OpenURLFailure: Hashable, Sendable {
  /// 시트를 연 사이 기기가 링크를 열 수 없는 상태가 됐다. 막힘 규칙은 설치와 같다 (`appInstallAvailability`).
  case deviceNotReady(AppInstallBlockReason)
  /// openurl 명령 실패, 또는 시트를 연 사이 기기가 목록에서 사라짐(`.deviceNotFound`).
  case simulator(SimulatorError)
}

/// 스크린샷 흐름의 실패 원인.
public enum ScreenshotFailure: Hashable, Sendable {
  /// 저장 폴더 준비·이름 예약 실패 (촬영 명령 전).
  case workspace(WorkspaceError)
  /// 촬영 명령 실패, 또는 실행 전 확인에서 기기가 없거나 꺼짐.
  case simulator(SimulatorError)
}

/// 녹화 흐름의 실패 원인.
public enum RecordingFailure: Hashable, Sendable {
  /// 저장 폴더 준비·이름 예약 실패 (녹화 명령 전).
  case workspace(WorkspaceError)
  /// 녹화 시작·저장 실패, 또는 실행 전 확인에서 기기가 없거나 꺼짐.
  case simulator(SimulatorError)
}

/// 알림 한 건. 같은 내용이라도 쌓일 때마다 새 id 를 받는다 (View 가 다음 알림을 다시 띄우는 기준).
public struct LauncherNoticeItem: Identifiable, Hashable, Sendable {
  public let id: Int
  public let notice: LauncherNotice
}

/// 확인을 기다리는 삭제·초기화. 누른 시점의 기기 이름·런타임 이름을 담는다.
public struct DeviceConfirmation: Hashable, Sendable {
  public enum Action: Hashable, Sendable {
    case delete
    case erase
  }

  public let action: Action
  public let deviceID: VirtualDevice.ID
  public let device: LauncherNotice.Device

  public init(action: Action, deviceID: VirtualDevice.ID, device: LauncherNotice.Device) {
    self.action = action
    self.deviceID = deviceID
    self.device = device
  }
}

/// 확인 대화상자의 작업 규칙. Model 가드가 쓴다.
extension DeviceConfirmation.Action {
  var task: DeviceTask {
    switch self {
    case .delete: .delete
    case .erase: .erase
    }
  }

  func availability(for device: VirtualDevice) -> DeviceActionAvailability {
    switch self {
    case .delete: device.deleteAvailability
    case .erase: device.eraseAvailability
    }
  }
}

extension DeviceConfirmation {
  /// 이 확인의 작업이 실패했다는 알림.
  func failedNotice(_ error: SimulatorError) -> LauncherNotice {
    switch self.action {
    case .delete: .deleteFailed(self.device, error)
    case .erase: .eraseFailed(self.device, error)
    }
  }
}
