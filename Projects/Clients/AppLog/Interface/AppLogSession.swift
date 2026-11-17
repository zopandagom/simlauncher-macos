import Core
import Foundation

/// 로그 세션(앱 실행 한 번) ID.
public struct AppLogSessionID: Hashable, Sendable {
  public let rawValue: UUID

  public init(_ rawValue: UUID) {
    self.rawValue = rawValue
  }
}

/// 세션이 끝난 이유.
public enum AppLogEndReason: Hashable, Sendable {
  /// 앱이 끝났다 (종료·크래시·Simulator 에서 닫기. simctl 은 원인을 알려 주지 않는다). Android 는 메인 프로세스가 끝남.
  case appExited
  /// 기기가 꺼졌거나(끄는 중 포함) 목록에서 사라졌다. Android 는 adb 연결이 끊긴 경우 포함.
  case deviceShutDown
  /// SimLauncher 가 같은 기기에서 같은 앱을 다시 설치하거나 실행해 끝났다.
  case replaced
  /// SimLauncher 가 받기를 멈췄다 (앱 종료 때. 화면에는 보일 일이 없다).
  case stopped
}

/// 세션 상태.
public enum AppLogSessionState: Hashable, Sendable {
  case receiving
  case ended(AppLogEndReason)
}

/// iOS 앱 버전 (CFBundleShortVersionString·CFBundleVersion). 앱이 정한 글자라 그대로 보인다. 둘 다 nil 일 수 있다.
public struct AppLogAppVersion: Hashable, Sendable {
  public let version: String?
  public let build: String?

  public init(version: String?, build: String?) {
    self.version = version
    self.build = build
  }
}

/// 세션 기기의 OS. 실행을 부른 쪽이 이미 아는 값이다 (새 명령으로 읽지 않는다).
public enum AppLogDeviceOS: Hashable, Sendable {
  /// iOS 런타임 이름 그대로 (`DeviceRuntime.name`, 예 "iOS 27.0").
  case iOS(runtimeName: String)
  /// Android 시스템 이미지의 API (`AndroidSystemImageRef.apiLabel`, 예 "37.0").
  case android(apiLabel: String)
}

/// 세션 하나의 요약 (줄은 담지 않는다). 실행 신호를 받은 세션만 보인다 (실행에 실패한 세션은 없다).
public struct AppLogSessionSummary: Identifiable, Hashable, Sendable {
  public let id: AppLogSessionID
  public let target: AppLogTarget
  public let deviceName: String
  /// 기기 OS. 모르면 nil (Android 이미지 정보 없음).
  public let deviceOS: AppLogDeviceOS?
  /// iOS 는 번들 ID, Android 는 패키지 이름.
  public let appID: String
  public let appName: String
  /// iOS 앱 버전 (실행할 때 SimLauncher 가 안 값). Android 는 nil.
  public let appVersion: AppLogAppVersion?
  /// 실행을 요청한 시각.
  public let startedAt: Date
  public let state: AppLogSessionState

  public init(
    id: AppLogSessionID,
    target: AppLogTarget,
    deviceName: String,
    deviceOS: AppLogDeviceOS?,
    appID: String,
    appName: String,
    appVersion: AppLogAppVersion?,
    startedAt: Date,
    state: AppLogSessionState
  ) {
    self.id = id
    self.target = target
    self.deviceName = deviceName
    self.deviceOS = deviceOS
    self.appID = appID
    self.appName = appName
    self.appVersion = appVersion
    self.startedAt = startedAt
    self.state = state
  }

  /// 상태만 바꾼 요약.
  public func with(state: AppLogSessionState) -> AppLogSessionSummary {
    AppLogSessionSummary(
      id: self.id,
      target: self.target,
      deviceName: self.deviceName,
      deviceOS: self.deviceOS,
      appID: self.appID,
      appName: self.appName,
      appVersion: self.appVersion,
      startedAt: self.startedAt,
      state: state
    )
  }
}

/// 로그 한 줄. 앱 출력은 신뢰하지 않는 텍스트다: 해석하지 않고 화면에 보이며, 사용자가 내보낼 때만 그대로(제어 문자 포함) 클립보드·파일로 나간다.
public struct AppLogLine: Identifiable, Hashable, Sendable {
  /// 세션 안에서 0 부터 늘어나는 번호 (버린 줄도 번호를 쓴다).
  public let index: Int
  public let text: String

  public var id: Int {
    self.index
  }

  public init(index: Int, text: String) {
    self.index = index
    self.text = text
  }
}

/// 줄 구독의 한 번 알림. 첫 알림은 지금 버퍼 전체(`isSnapshot`), 그 뒤는 새로 쌓인 줄만.
public struct AppLogLineUpdate: Hashable, Sendable {
  public let isSnapshot: Bool
  public let lines: [AppLogLine]
  /// 버퍼가 차서 지금까지 버린 앞 줄 수. 번호가 이보다 작은 줄은 버퍼에 없다.
  public let droppedCount: Int

  public init(isSnapshot: Bool, lines: [AppLogLine], droppedCount: Int) {
    self.isSnapshot = isSnapshot
    self.lines = lines
    self.droppedCount = droppedCount
  }
}
