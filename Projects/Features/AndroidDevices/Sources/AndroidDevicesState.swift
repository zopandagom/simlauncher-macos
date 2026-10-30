import AndroidEmulatorInterface
import AndroidPackageInterface
import Core
import DownloadInterface
import Foundation
import WorkspaceInterface

/// Android 기기 목록 화면의 상태.
public enum AndroidDevicesListState: Hashable, Sendable {
  /// 목록이 없고 읽는 중이다.
  case loading
  /// 읽은 목록. 다시 읽는 동안에도 마지막 목록을 유지한다.
  case loaded(AndroidDeviceList)
  /// 목록을 읽지 못했다 (전체 화면 오류). 한 번도 읽지 못했거나, Android 도구를 찾지 못했다(`.sdkUnavailable`, 이전 목록을 버린다).
  case failed(AndroidEmulatorError)
}

/// 알림에 보일 기기. 누른 시점의 값이라, 실패 뒤 목록에서 사라져도 그대로 보인다.
public struct AndroidDeviceLabel: Hashable, Sendable {
  /// 표시 이름 (번역하지 않는 사용자 데이터).
  public let name: String
  /// "37.0". 이미지 정보가 없으면 nil.
  public let apiLabel: String?

  public init(name: String, apiLabel: String?) {
    self.name = name
    self.apiLabel = apiLabel
  }

  /// 지금 목록의 기기 값으로 만든다.
  public init(_ device: AndroidVirtualDevice) {
    self.init(name: device.displayName, apiLabel: device.systemImage?.apiLabel)
  }
}

/// 목록 위에 띄우는 알림. 기기 작업(켜기·끄기·만들기·삭제·초기화)과 앱 작업(설치·실행·링크 열기)·화면 캡처(스크린샷·녹화) 실패,
/// 목록이 있을 때의 새로 고침 실패, 함께 켜기 결과.
/// 정보 알림은 삭제가 기기 폴더를 남긴 것과 녹화가 기기 꺼짐·3분 제한으로 멈추고 저장된 것이다. 취소(`.cancelled`)는 알리지 않는다.
public enum AndroidDevicesNotice: Hashable, Sendable {
  case refreshFailed(AndroidEmulatorError)
  case bootFailed(AndroidDeviceLabel, AndroidEmulatorError)
  case shutdownFailed(AndroidDeviceLabel, AndroidEmulatorError)
  /// 기기를 만들지 못했다. 라벨은 입력한(앞뒤 공백을 뺀) 이름과 고른 이미지의 API.
  case createFailed(AndroidDeviceLabel, AndroidEmulatorError)
  case deleteFailed(AndroidDeviceLabel, AndroidEmulatorError)
  case eraseFailed(AndroidDeviceLabel, AndroidEmulatorError)
  /// 정보 알림: 목록(ini)에서는 지웠지만 기기 폴더가 예상한 위치가 아니어서 남겼다.
  case folderKept(AndroidDeviceLabel, URL)
  /// 함께 켜기의 기기별 결과. 실패가 하나라도 있을 때만 쌓는다.
  case batchBootFinished(AndroidBatchBootReport)
  /// apk 를 설치하지 못했다 (받기·검사·판정·기기 상태·설치 명령).
  case installFailed(AndroidDeviceLabel, AndroidAppInstallFailure)
  /// 설치는 했지만 실행하지 못했다.
  case installedButNotLaunched(AndroidDeviceLabel, AndroidEmulatorError)
  /// 행 "앱 실행…" 시트에서 고른 앱을 실행하지 못했다.
  case launchFailed(AndroidDeviceLabel, AndroidAppActionFailure)
  /// 행 "링크 열기…" 시트의 링크를 열지 못했다.
  case openURLFailed(AndroidDeviceLabel, AndroidAppActionFailure)
  /// 스크린샷을 저장하지 못했다 (저장 파일 예약·찍기).
  case screenshotFailed(AndroidDeviceLabel, AndroidCaptureFailure)
  /// 스크린샷은 저장했지만 Finder 에서 보여 주지 못했다.
  case screenshotRevealFailed(AndroidDeviceLabel, WorkspaceError)
  /// 화면을 녹화하지 못했다 (저장 파일 예약·시작·기기 꺼짐·가져오기).
  case recordingFailed(AndroidDeviceLabel, AndroidCaptureFailure)
  /// 녹화가 실패로 끝났지만 그때까지의 화면을 가져와 저장했다.
  case recordingInterrupted(AndroidDeviceLabel)
  /// 정보 알림: 녹화 중 기기가 꺼져 멈추고 저장했다.
  case recordingStoppedByDevice(AndroidDeviceLabel)
  /// 정보 알림: API 33 이하의 3분 제한에 닿아 멈추고 저장했다.
  case recordingAtTimeLimit(AndroidDeviceLabel)
  /// 녹화는 저장했지만 Finder 에서 보여 주지 못했다.
  case recordingRevealFailed(AndroidDeviceLabel, WorkspaceError)
}

/// 스크린샷·녹화 실패 원인.
public enum AndroidCaptureFailure: Hashable, Sendable {
  /// 저장 폴더 준비·파일 이름 예약 실패 (명령 전).
  case workspace(WorkspaceError)
  /// 찍기·녹화·가져오기 실패. 기기가 목록에서 사라졌으면 `.deviceNotFound`.
  case emulator(AndroidEmulatorError)
}

/// apk 설치 실패 원인.
public enum AndroidAppInstallFailure: Hashable, Sendable {
  /// 끌어다 놓은 항목이 둘 이상이다.
  case multipleItems
  /// apk 검사 실패.
  case package(AndroidPackageError)
  /// 기기에 맞지 않는 apk 다 (Core 판정).
  case rejected(AndroidInstallProblem)
  /// 파일을 고르거나 검사하는 사이 기기가 켜짐이 아니거나 쓸 수 없게 됐다.
  case deviceNotReady(AndroidAppActionBlockReason)
  /// 기기 값 읽기·설치 명령 실패. 기기가 목록에서 사라졌으면 `.deviceNotFound`.
  case emulator(AndroidEmulatorError)
  /// URL·카탈로그에서 받기 실패 (주소·네트워크·저장 공간). 출처가 문구를 고른다.
  case download(DownloadError, origin: AndroidDownloadOrigin)
  /// 받은 파일의 apk 검사 실패. `isWebPage` 는 `.unreadable` 이고 응답 형식이 웹 페이지(text/html·application/xhtml+xml)일 때만
  /// true 다 (iOS 와 같은 판정. apk 인지는 내용으로 정하고, 형식은 문구만 고른다).
  case downloadedPackage(AndroidPackageError, isWebPage: Bool, origin: AndroidDownloadOrigin)
}

extension AndroidAppInstallFailure {
  /// 받은 파일의 검사 실패를 응답 형식과 함께 옮긴다. 웹 페이지 여부는 `.unreadable` 일 때만 본다.
  init(downloaded error: AndroidPackageError, mimeType: String?, origin: AndroidDownloadOrigin) {
    let webPageTypes: Set = ["text/html", "application/xhtml+xml"]
    let isWebPage = error == .unreadable && webPageTypes.contains(mimeType?.lowercased() ?? "")
    self = .downloadedPackage(error, isWebPage: isWebPage, origin: origin)
  }
}

/// 받아서 설치할 주소가 어디서 왔는지. 받기·받은 파일 실패 문구만 고른다 (주소 쪽 다음 할 일이 입력한 사람 / 카탈로그를 만든 사람).
public enum AndroidDownloadOrigin: Hashable, Sendable {
  /// "URL 에서…" 시트에 입력한 주소.
  case enteredURL
  /// "카탈로그에서…" 시트에서 고른 버전의 빌드 주소.
  case catalog
}

/// `AndroidDownloadInstallModel` 이 App 을 거쳐 `AndroidDevicesModel.downloadInstallRequested(_:)` 에 넘기는 설치 요청.
public struct AndroidDownloadInstallRequest: Hashable, Sendable {
  public let deviceID: AndroidVirtualDevice.ID
  /// 시트를 연 시점의 기기 라벨 (알림에 쓴다).
  public let device: AndroidDeviceLabel
  public let url: DownloadURL
  public let origin: AndroidDownloadOrigin

  public init(
    deviceID: AndroidVirtualDevice.ID,
    device: AndroidDeviceLabel,
    url: DownloadURL,
    origin: AndroidDownloadOrigin
  ) {
    self.deviceID = deviceID
    self.device = device
    self.url = url
    self.origin = origin
  }
}

/// 앱 실행·링크 열기 실패 원인.
public enum AndroidAppActionFailure: Hashable, Sendable {
  /// 시트를 연 사이 기기가 켜짐이 아니거나 쓸 수 없게 됐다.
  case deviceNotReady(AndroidAppActionBlockReason)
  /// 명령 실패. 기기가 목록에서 사라졌으면 `.deviceNotFound`.
  case emulator(AndroidEmulatorError)
}

/// 함께 켜기("선택한 기기 켜기")의 기기별 결과. 시작한 기기만 담는다 (켜져 있거나 작업 중·쓸 수 없는 기기는 알리지 않고 건너뛴다).
public struct AndroidBatchBootReport: Hashable, Sendable {
  public struct Entry: Hashable, Sendable {
    public let device: AndroidDeviceLabel
    /// nil 이면 켰다.
    public let error: AndroidEmulatorError?

    public init(device: AndroidDeviceLabel, error: AndroidEmulatorError?) {
      self.device = device
      self.error = error
    }
  }

  /// 목록 순서.
  public let entries: [Entry]

  public init(entries: [Entry]) {
    self.entries = entries
  }

  public var successCount: Int {
    self.entries.count(where: { $0.error == nil })
  }

  /// 실패가 있으면 알린다 (모두 켰으면 행 켜기처럼 알림이 없다).
  var needsNotice: Bool {
    self.entries.contains { $0.error != nil }
  }
}

/// 알림 한 건. 같은 내용이라도 쌓일 때마다 새 id 를 받는다 (View 가 다음 알림을 다시 띄우는 기준).
public struct AndroidDevicesNoticeItem: Identifiable, Hashable, Sendable {
  public let id: Int
  public let notice: AndroidDevicesNotice
}

/// 닫지 않은 알림 줄. 쌓인 순서이고, 화면은 첫 항목을 보인다.
/// 바꾸는 메서드는 Model 만 부른다 (View 는 Model 의 `notices` 를 읽기만 한다).
public struct AndroidDevicesNotices: Hashable, Sendable {
  public private(set) var items: [AndroidDevicesNoticeItem] = []
  /// 다음에 쌓을 항목의 id. 닫아도 줄어들지 않는다 (같은 내용이 다시 쌓여도 새 id).
  private var nextID = 0

  public init() {}

  /// 기기 작업 실패는 늘 쌓는다. 새로 고침 실패는 같은 원인이 이미 줄에 있으면 쌓지 않는다 (자동 다시 읽기가 되풀이해도 하나).
  mutating func enqueue(_ notice: AndroidDevicesNotice) {
    if case .refreshFailed = notice, self.items.contains(where: { $0.notice == notice }) {
      return
    }
    self.items.append(AndroidDevicesNoticeItem(id: self.nextID, notice: notice))
    self.nextID += 1
  }

  /// id 가 같은 항목만 지운다. 없으면 아무것도 하지 않아, 두 번 불려도 다음 알림을 지우지 않는다.
  mutating func dismiss(_ id: AndroidDevicesNoticeItem.ID) {
    self.items.removeAll { $0.id == id }
  }
}

/// 확인을 기다리는 삭제·초기화. 누른 시점의 기기 라벨을 담는다.
public struct AndroidDeviceConfirmation: Hashable, Sendable {
  public enum Action: Hashable, Sendable {
    case delete
    case erase
  }

  public let action: Action
  public let deviceID: AndroidVirtualDevice.ID
  public let device: AndroidDeviceLabel

  public init(action: Action, deviceID: AndroidVirtualDevice.ID, device: AndroidDeviceLabel) {
    self.action = action
    self.deviceID = deviceID
    self.device = device
  }
}

extension AndroidDeviceConfirmation.Action {
  var task: AndroidDeviceTask {
    switch self {
    case .delete: .delete
    case .erase: .erase
    }
  }

  func availability(for device: AndroidVirtualDevice) -> DeviceActionAvailability {
    switch self {
    case .delete: device.deleteAvailability
    case .erase: device.eraseAvailability
    }
  }
}

extension AndroidDeviceConfirmation {
  /// 이 확인의 작업이 실패했다는 알림.
  func failedNotice(_ error: AndroidEmulatorError) -> AndroidDevicesNotice {
    switch self.action {
    case .delete: .deleteFailed(self.device, error)
    case .erase: .eraseFailed(self.device, error)
    }
  }
}

extension AndroidDeviceList {
  /// 목록에 보이는 모든 기기의 id (선택 정리에 쓴다).
  var deviceIDs: Set<AndroidVirtualDevice.ID> {
    Set(self.devices.map(\.id))
  }
}

extension AndroidDevicesNotice {
  /// 알림에 담긴 기기 명령 에러 (정보 알림·함께 켜기 결과·검사·판정·기기 상태·받기·저장 폴더 실패는 nil). Model 이 취소를 거르는 데
  /// 쓴다.
  var error: AndroidEmulatorError? {
    switch self {
    case let .refreshFailed(error), let .bootFailed(_, error), let .shutdownFailed(_, error),
         let .createFailed(_, error), let .deleteFailed(_, error), let .eraseFailed(_, error):
      error
    case let .installedButNotLaunched(_, error), let .installFailed(_, .emulator(error)),
         let .launchFailed(_, .emulator(error)), let .openURLFailed(_, .emulator(error)):
      error
    case let .screenshotFailed(_, .emulator(error)), let .recordingFailed(_, .emulator(error)):
      error
    case .folderKept, .batchBootFinished, .installFailed, .launchFailed,
         .openURLFailed, .screenshotFailed,
         .screenshotRevealFailed, .recordingFailed, .recordingInterrupted, .recordingStoppedByDevice,
         .recordingAtTimeLimit, .recordingRevealFailed:
      nil
    }
  }
}
