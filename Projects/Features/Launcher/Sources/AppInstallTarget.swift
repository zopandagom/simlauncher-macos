import Core
import Foundation

/// 앱 설치·링크 열기 대상 기기를 지금 목록으로 다시 확인한 결과. 시트를 연 사이나 검사하는 사이 목록이 바뀌었을 수 있어
/// Model 이 명령 전에 부른다. 같은 기기의 진행 중 작업은 보지 않는다 (부르는 쪽이 정한다).
enum AppInstallTarget: Hashable, Sendable {
  /// 목록을 아직 읽지 못했다.
  case notLoaded
  /// 목록에 그 기기가 없다.
  case notFound
  /// 기기가 설치·링크 열기를 받을 수 없는 상태다 (`appInstallAvailability`).
  case blocked(AppInstallBlockReason)
  case ready(VirtualDevice)

  static func current(_ id: VirtualDevice.ID, in state: LauncherListState) -> AppInstallTarget {
    guard case let .loaded(list) = state else { return .notLoaded }
    guard let device = list.device(id: id) else { return .notFound }
    if case let .blocked(reason) = device.appInstallAvailability {
      return .blocked(reason)
    }
    return .ready(device)
  }

  /// 설치 흐름의 실패 원인. 목록이 없거나 기기가 없으면 `.deviceNotFound`. `.ready` 면 nil.
  var installFailure: AppInstallFailure? {
    switch self {
    case .notLoaded, .notFound: .simulator(.deviceNotFound)
    case let .blocked(reason): .deviceNotReady(reason)
    case .ready: nil
    }
  }

  /// 링크 열기 흐름의 실패 원인. 목록이 없으면 알리지 않고(nil) 끝낸다. `.ready` 면 nil.
  var openURLFailure: OpenURLFailure? {
    switch self {
    case .notLoaded, .ready: nil
    case .notFound: .simulator(.deviceNotFound)
    case let .blocked(reason): .deviceNotReady(reason)
    }
  }
}

/// 설치할 항목의 종류 판정.
enum AppInstallSource {
  /// 확장자가 zip 이면(대소문자 무시) 풀어서 설치한다.
  static func isZip(_ url: URL) -> Bool {
    url.pathExtension.lowercased() == "zip"
  }
}
