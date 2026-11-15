import Core
import Foundation
import SimulatorInterface

/// 마지막 권한 바꾸기·푸시 보내기가 성공한 것. 다음 적용을 시작하면 지운다. 앱 이름은 명령을 시작한 때의 값이다
/// (도중에 다른 앱을 골라도 문구가 맞다).
public enum TestConditionsResult: Hashable, Sendable {
  case privacyChanged(IOSPrivacyService, IOSPrivacyAction, appName: String)
  case pushSent(appName: String)
}

/// 테스트 조건 시트의 앱 단위 구역 초안: 켜진 기기의 사용자 설치 앱 목록(`installedApps`, "앱 실행…" 과 같은 목록), 고른 앱,
/// 푸시 입력(제목·본문 폼 또는 JSON)과 마지막 성공 결과. `TestConditionsDraft.app` 으로 갖고, 바꾸는 메서드는 Model 만
/// `TestConditionsDraft.updateApp(_:)` 으로 부른다.
public struct TestConditionsAppDraft: Hashable, Sendable {
  /// 설치된 앱 목록.
  public enum AppList: Hashable, Sendable {
    /// 첫 읽기 (보일 목록이 아직 없다).
    case loading
    case loaded([InstalledApp])
    /// 마지막으로 읽은 목록을 그대로 보이며 다시 읽는 중 (고른 앱과 그 아래 권한·푸시 구역도 그대로 둔다).
    case reloading([InstalledApp])
    case failed(SimulatorError)
  }

  /// 푸시 입력 방식.
  public enum PushInputMode: Hashable, Sendable, CaseIterable {
    /// 제목(선택)·본문으로 alert 알림을 만든다.
    case form
    /// payload JSON 을 직접 넣는다 (보낸 바이트 그대로 간다).
    case json
  }

  public private(set) var apps: AppList = .loading
  /// 앱 목록 읽기 요청 번호. 같은 시트에서 다시 읽으면 늘어, 앞 읽기의 늦은 결과를 버린다.
  public private(set) var appsRequest = 0
  /// 고른 앱. 늘 `loadedApps`(`.loaded`·`.reloading`) 목록에 있는 값이다 (목록이 바뀌어 없어지면 nil 이거나 자동 선택 규칙의 값).
  public private(set) var selectedAppID: AppBundleID?
  public private(set) var pushInput: PushInputMode = .form
  public private(set) var pushTitle = ""
  public private(set) var pushBody = ""
  /// JSON 입력. 처음 값은 예시 JSON 이다.
  public private(set) var pushJSON: String
  /// 마지막 권한 바꾸기·푸시 보내기의 성공 줄. 다음 적용을 시작하면 지운다.
  public private(set) var result: TestConditionsResult?

  init(exampleJSON: String) {
    self.pushJSON = exampleJSON
  }

  /// 예시 JSON: `{"aps":{"alert":{"body":…,"title":…}}}` 를 줄바꿈·키 정렬로 만든다. 키 골격은 코드에 두고 제목·본문 글자만 받는다
  /// (번역한 글자가 JSON 을 깨뜨리지 못한다). 문자열 사전이라 직렬화는 실패하지 않는다 (실패하면 빈 입력).
  static func exampleJSON(title: String, body: String) -> String {
    let object: [String: Any] = ["aps": ["alert": ["title": title, "body": body]]]
    guard let data = try? JSONSerialization.data(
      withJSONObject: object,
      options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    ) else { return "" }
    return String(bytes: data, encoding: .utf8) ?? ""
  }

  // MARK: - 계산

  /// 보이는 앱 목록: 읽었거나(`.loaded`) 다시 읽는 중(`.reloading`, 마지막 목록)이면 그 목록, 아니면 nil.
  public var loadedApps: [InstalledApp]? {
    switch self.apps {
    case let .loaded(apps), let .reloading(apps): apps
    case .loading, .failed: nil
    }
  }

  /// 앱 목록을 읽는 중인가 (첫 읽기·다시 읽기).
  public var isReadingApps: Bool {
    switch self.apps {
    case .loading, .reloading: true
    case .loaded, .failed: false
    }
  }

  /// 고른 앱 (보이는 목록에 있는 값. 다시 읽는 동안에도 마지막 목록의 값이다).
  public var selectedApp: InstalledApp? {
    guard let apps = self.loadedApps, let id = self.selectedAppID else { return nil }
    return apps.first { $0.bundleID == id }
  }

  /// 지금 입력으로 만든 payload. 문제가 있으면 nil.
  public var pushPayload: PushPayload? {
    try? self.pushCheck.get()
  }

  /// 지금 입력의 문제. 폼의 빈 본문·JSON 공백뿐은 문구를 보이지 않으므로 nil (버튼만 꺼진다).
  public var pushProblem: PushPayloadProblem? {
    switch self.pushCheck {
    case .success, .failure(.emptyBody), .failure(.empty): nil
    case let .failure(problem): problem
    }
  }

  /// JSON 입력의 UTF-8 바이트 수 (simctl 이 세는 값과 같다: 공백·줄바꿈 포함, 다시 직렬화하지 않는다).
  public var pushByteCount: Int {
    self.pushJSON.utf8.count
  }

  private var pushCheck: Result<PushPayload, PushPayloadProblem> {
    switch self.pushInput {
    case .form: PushPayload.alert(title: self.pushTitle, body: self.pushBody)
    case .json: PushPayload.json(self.pushJSON)
    }
  }

  // MARK: - 바꾸기 (Model 만 부른다)

  /// 앱 목록 읽기를 시작한다 (요청 번호를 올린다). 보일 목록이 있으면(`.loaded`·`.reloading`) 그 목록과 선택을 그대로 두고
  /// `.reloading` 으로, 없으면(첫 읽기·실패 뒤) `.loading` 으로.
  mutating func appsStarted() {
    if let apps = self.loadedApps {
      self.apps = .reloading(apps)
    } else {
      self.apps = .loading
    }
    self.appsRequest += 1
  }

  /// 읽은 목록을 보인다. 선택: 지금 고른 앱이 새 목록에 있으면 그대로, 없으면 이 기기에서 마지막으로 고른 앱(`remembered`)이 목록에
  /// 있으면 그것, 아니면 앱이 하나일 때만 그 앱, 아니면 고르지 않음.
  mutating func appsLoaded(_ apps: [InstalledApp], remembered: AppBundleID?) {
    self.apps = .loaded(apps)
    let ids = apps.map(\.bundleID)
    if let current = self.selectedAppID, ids.contains(current) {
      return
    }
    if let remembered, ids.contains(remembered) {
      self.selectedAppID = remembered
    } else if ids.count == 1 {
      self.selectedAppID = ids.first
    } else {
      self.selectedAppID = nil
    }
  }

  /// 목록을 읽지 못했다 (다시 읽기였어도). 선택도 지운다 (목록에 있는 값만 고를 수 있다. 실패한 기기의 마지막 목록은 믿지 않는다).
  mutating func appsFailed(_ error: SimulatorError) {
    self.apps = .failed(error)
    self.selectedAppID = nil
  }

  /// 앱을 고른다. nil 이거나 보이는 목록(`loadedApps`, 다시 읽는 동안은 마지막 목록)에 있는 값만 받는다 (받았으면 true).
  mutating func appSelected(_ id: AppBundleID?) -> Bool {
    if let id {
      guard let apps = self.loadedApps, apps.contains(where: { $0.bundleID == id }) else { return false }
    }
    self.selectedAppID = id
    return true
  }

  mutating func pushInputChanged(_ mode: PushInputMode) {
    self.pushInput = mode
  }

  mutating func pushTitleChanged(_ text: String) {
    self.pushTitle = text
  }

  mutating func pushBodyChanged(_ text: String) {
    self.pushBody = text
  }

  mutating func pushJSONChanged(_ text: String) {
    self.pushJSON = text
  }

  mutating func resultChanged(_ result: TestConditionsResult?) {
    self.result = result
  }
}
