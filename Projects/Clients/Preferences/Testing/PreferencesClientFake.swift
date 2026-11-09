import Core
import PreferencesInterface
import Synchronization

/// 테스트·Example 용 `PreferencesClient`. 메모리에 목록을 두고 호출을 기록한다.
/// 추가·삭제는 Impl 과 같은 판정을 Core 규칙으로 한다: 잠김이면 `.locked`, 같은 카탈로그가 있으면 `.duplicate`,
/// 아니면 `CatalogURLList.storedString(for:)` 를 끝에 붙인다 / 같은 문자열을 모두 뺀다. 저장 실패는 없다.
/// "화면이 읽은 뒤 바깥에서 잠김·중복" 은 `setStored(urls:isLocked:)` 로 만든다 (오류를 억지로 내는 설정은 두지 않는다).
/// Android SDK 위치·라이선스 지문도 메모리에 두고 Impl 과 같이 잠김이면 `.locked` 이고 쓰지 않는다.
/// 바깥 변경은 `setStoredAndroidSDKPath(_:)`·`setStoredAndroidLicenses(_:isLocked:)` 로 만든다.
/// 저장한 로그 필터는 저장 배열처럼 항목 목록(nil = 읽지 못한 항목)으로 두고 Impl 과 같은 Core 규칙(`SavedLogFilterList`)으로 판정한다:
/// 잠김이면 `.locked`, 같은 이름을 덮어쓰지 않으면 `.duplicate`, 상한이면 `.limitReached`, nil 항목은 같은 자리에 그대로 남긴다.
/// 바깥 변경은 `setStoredLogFilters(_:isLocked:)` 로 만든다.
public final class PreferencesClientFake: PreferencesClient {
  public enum Call: Hashable, Sendable {
    case catalogURLs
    /// `DownloadURL` 의 `absoluteString`.
    case addCatalogURL(String)
    case removeCatalogURL(String)
    case androidSDKPath
    case setAndroidSDKPath(String?)
    case acceptedAndroidLicenses
    case addAcceptedAndroidLicenses(Set<String>)
    case savedLogFilters
    /// 저장한 필터의 이름 (자른 값).
    case saveLogFilter(String, replacingSameName: Bool)
    case removeLogFilter(String)
  }

  private struct State {
    var setting: CatalogURLSetting
    var calls: [Call] = []
    var androidSDKPath: AndroidSDKPathSetting = .absent
    var androidLicenses: Set<String> = []
    var androidLicensesLocked = false
    var logFilters: [SavedLogFilter?] = []
    var logFiltersLocked = false
  }

  private let state: Mutex<State>

  public init(urls: [String] = [], isLocked: Bool = false) {
    self.state = Mutex(State(setting: CatalogURLSetting(urls: urls, isLocked: isLocked)))
  }

  /// 저장된 Android SDK 위치·라이선스 지문을 정해 만든다.
  public convenience init(
    androidSDKPath: AndroidSDKPathSetting,
    androidLicenses: Set<String> = [],
    androidLicensesLocked: Bool = false
  ) {
    self.init()
    self.setStoredAndroidSDKPath(androidSDKPath)
    self.setStoredAndroidLicenses(androidLicenses, isLocked: androidLicensesLocked)
  }

  /// 저장된 로그 필터 항목(nil = 읽지 못한 항목)과 잠금을 정해 만든다.
  public convenience init(logFilters: [SavedLogFilter?], logFiltersLocked: Bool = false) {
    self.init()
    self.setStoredLogFilters(logFilters, isLocked: logFiltersLocked)
  }

  /// 들어온 호출 순서대로.
  public var calls: [Call] {
    self.state.withLock { $0.calls }
  }

  /// 지금 저장된 값 (기록하지 않는다).
  public var stored: CatalogURLSetting {
    self.state.withLock { $0.setting }
  }

  /// 바깥 변경(`defaults write`·MDM)을 흉내 낸다. 기록하지 않는다.
  public func setStored(urls: [String], isLocked: Bool) {
    self.state.withLock { $0.setting = CatalogURLSetting(urls: urls, isLocked: isLocked) }
  }

  /// 지금 저장된 Android SDK 위치 (기록하지 않는다).
  public var storedAndroidSDKPath: AndroidSDKPathSetting {
    self.state.withLock { $0.androidSDKPath }
  }

  /// 지금 저장된 라이선스 지문 (기록하지 않는다).
  public var storedAndroidLicenses: Set<String> {
    self.state.withLock { $0.androidLicenses }
  }

  /// 바깥 변경(`defaults write`·MDM)을 흉내 낸다. 기록하지 않는다.
  public func setStoredAndroidSDKPath(_ setting: AndroidSDKPathSetting) {
    self.state.withLock { $0.androidSDKPath = setting }
  }

  /// 바깥 변경(관리자가 미리 넣은 동의·잠금)을 흉내 낸다. 기록하지 않는다.
  public func setStoredAndroidLicenses(_ fingerprints: Set<String>, isLocked: Bool) {
    self.state.withLock { state in
      state.androidLicenses = fingerprints
      state.androidLicensesLocked = isLocked
    }
  }

  /// 지금 저장된 로그 필터 항목, 저장 순서 (기록하지 않는다).
  public var storedLogFilters: [SavedLogFilter?] {
    self.state.withLock { $0.logFilters }
  }

  /// 지금 로그 필터 키가 잠겼는지 (기록하지 않는다).
  public var storedLogFiltersLocked: Bool {
    self.state.withLock { $0.logFiltersLocked }
  }

  /// 바깥 변경(`defaults write`·MDM)을 흉내 낸다. 기록하지 않는다.
  public func setStoredLogFilters(_ items: [SavedLogFilter?], isLocked: Bool) {
    self.state.withLock { state in
      state.logFilters = items
      state.logFiltersLocked = isLocked
    }
  }

  public func catalogURLs() -> CatalogURLSetting {
    self.state.withLock { state in
      state.calls.append(.catalogURLs)
      return state.setting
    }
  }

  public func addCatalogURL(_ url: DownloadURL) throws(PreferencesError) -> CatalogURLSetting {
    try self.state.withLock { (current: inout State) throws(PreferencesError) -> CatalogURLSetting in
      current.calls.append(.addCatalogURL(url.url.absoluteString))
      guard !current.setting.isLocked else {
        throw .locked
      }
      guard CatalogURLList.indexOfSameCatalog(as: url, in: current.setting.urls) == nil else {
        throw .duplicate
      }
      current.setting = CatalogURLSetting(
        urls: current.setting.urls + [CatalogURLList.storedString(for: url)],
        isLocked: false
      )
      return current.setting
    }
  }

  public func removeCatalogURL(_ raw: String) throws(PreferencesError) -> CatalogURLSetting {
    try self.state.withLock { (current: inout State) throws(PreferencesError) -> CatalogURLSetting in
      current.calls.append(.removeCatalogURL(raw))
      guard !current.setting.isLocked else {
        throw .locked
      }
      current.setting = CatalogURLSetting(urls: current.setting.urls.filter { $0 != raw }, isLocked: false)
      return current.setting
    }
  }

  public func androidSDKPath() -> AndroidSDKPathSetting {
    self.state.withLock { state in
      state.calls.append(.androidSDKPath)
      return state.androidSDKPath
    }
  }

  /// nil 이면 `.absent`, 문자열이면 `.path` 로 바꾼다 (잠금은 그대로).
  public func setAndroidSDKPath(_ path: String?) throws(PreferencesError) {
    try self.state.withLock { (current: inout State) throws(PreferencesError) in
      current.calls.append(.setAndroidSDKPath(path))
      guard !current.androidSDKPath.isLocked else {
        throw .locked
      }
      current.androidSDKPath = AndroidSDKPathSetting(value: path.map { .path($0) } ?? .absent, isLocked: false)
    }
  }

  public func acceptedAndroidLicenses() -> Set<String> {
    self.state.withLock { state in
      state.calls.append(.acceptedAndroidLicenses)
      return state.androidLicenses
    }
  }

  public func addAcceptedAndroidLicenses(_ fingerprints: Set<String>) throws(PreferencesError) {
    try self.state.withLock { (current: inout State) throws(PreferencesError) in
      current.calls.append(.addAcceptedAndroidLicenses(fingerprints))
      guard !current.androidLicensesLocked else {
        throw .locked
      }
      current.androidLicenses.formUnion(fingerprints)
    }
  }

  public func savedLogFilters() -> SavedLogFilterSetting {
    self.state.withLock { state in
      state.calls.append(.savedLogFilters)
      return SavedLogFilterSetting(
        filters: SavedLogFilterList.visible(state.logFilters),
        isLocked: state.logFiltersLocked
      )
    }
  }

  public func saveLogFilter(
    _ filter: SavedLogFilter,
    replacingSameName: Bool
  ) throws(PreferencesError) -> SavedLogFilterSetting {
    try self.state.withLock { (current: inout State) throws(PreferencesError) -> SavedLogFilterSetting in
      current.calls.append(.saveLogFilter(filter.name, replacingSameName: replacingSameName))
      guard !current.logFiltersLocked else {
        throw .locked
      }
      switch SavedLogFilterList.saveChange(filter, replacingSameName: replacingSameName, in: current.logFilters) {
      case let .success(change):
        current.logFilters = change.applied(to: current.logFilters) { $0 }
      case .failure(.sameName):
        throw .duplicate
      case .failure(.limitReached):
        throw .limitReached
      }
      return SavedLogFilterSetting(filters: SavedLogFilterList.visible(current.logFilters), isLocked: false)
    }
  }

  public func removeLogFilter(named name: String) throws(PreferencesError) -> SavedLogFilterSetting {
    try self.state.withLock { (current: inout State) throws(PreferencesError) -> SavedLogFilterSetting in
      current.calls.append(.removeLogFilter(name))
      guard !current.logFiltersLocked else {
        throw .locked
      }
      if let change = SavedLogFilterList.removeChange(named: name, in: current.logFilters) {
        current.logFilters = change.applied(to: current.logFilters) { $0 }
      }
      return SavedLogFilterSetting(filters: SavedLogFilterList.visible(current.logFilters), isLocked: false)
    }
  }
}
