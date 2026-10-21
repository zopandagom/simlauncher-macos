import Core
import PreferencesInterface
import Synchronization

/// 테스트·Example 용 `PreferencesClient`. 메모리에 목록을 두고 호출을 기록한다.
/// 추가·삭제는 Impl 과 같은 판정을 Core 규칙으로 한다: 잠김이면 `.locked`, 같은 카탈로그가 있으면 `.duplicate`,
/// 아니면 `CatalogURLList.storedString(for:)` 를 끝에 붙인다 / 같은 문자열을 모두 뺀다. 저장 실패는 없다.
/// "화면이 읽은 뒤 바깥에서 잠김·중복" 은 `setStored(urls:isLocked:)` 로 만든다 (오류를 억지로 내는 설정은 두지 않는다).
public final class PreferencesClientFake: PreferencesClient {
  public enum Call: Hashable, Sendable {
    case catalogURLs
    /// `DownloadURL` 의 `absoluteString`.
    case addCatalogURL(String)
    case removeCatalogURL(String)
  }

  private struct State {
    var setting: CatalogURLSetting
    var calls: [Call] = []
  }

  private let state: Mutex<State>

  public init(urls: [String] = [], isLocked: Bool = false) {
    self.state = Mutex(State(setting: CatalogURLSetting(urls: urls, isLocked: isLocked)))
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
}
