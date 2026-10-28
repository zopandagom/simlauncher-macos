import Core
import PreferencesInterface
import Synchronization

/// UserDefaults 표준 도메인(앱 번들 ID)의 `CatalogURLs`·`AndroidSDKPath`·`AcceptedAndroidLicenses` 키를 읽고 쓴다.
/// 쓰기 전에 키마다 강제 여부(`objectIsForced`)를 본다:
/// 강제 중에 쓰면 화면에는 변화가 없는데 사용자 도메인에 값이 남아 프로필을 지우는 순간 나타나므로 쓰지 않는다.
public final class PreferencesClientImpl: PreferencesClient {
  private let store: any PreferenceStore
  /// 추가·삭제의 "읽기 → 판정 → 쓰기" 를 묶는다. 같은 프로세스의 두 호출이 서로의 쓰기를 덮지 않게 한다.
  /// 다른 프로세스(`defaults write`)와의 경쟁은 막지 않는다.
  private let lock = Mutex(())

  public convenience init() {
    self.init(store: UserDefaultsPreferenceStore(suiteName: nil))
  }

  init(store: any PreferenceStore) {
    self.store = store
  }

  public func catalogURLs() -> CatalogURLSetting {
    CatalogURLSetting(urls: self.store.catalogURLs(), isLocked: self.store.isCatalogURLsForced())
  }

  public func addCatalogURL(_ url: DownloadURL) throws(PreferencesError) -> CatalogURLSetting {
    try self.lock.withLock { _ throws(PreferencesError) in
      guard !self.store.isCatalogURLsForced() else {
        throw .locked
      }
      let urls = self.store.catalogURLs()
      guard CatalogURLList.indexOfSameCatalog(as: url, in: urls) == nil else {
        throw .duplicate
      }
      let updated = urls + [CatalogURLList.storedString(for: url)]
      self.store.setCatalogURLs(updated)
      return CatalogURLSetting(urls: updated, isLocked: false)
    }
  }

  public func removeCatalogURL(_ raw: String) throws(PreferencesError) -> CatalogURLSetting {
    try self.lock.withLock { _ throws(PreferencesError) in
      guard !self.store.isCatalogURLsForced() else {
        throw .locked
      }
      let urls = self.store.catalogURLs()
      let updated = urls.filter { $0 != raw }
      if updated.count != urls.count {
        self.store.setCatalogURLs(updated)
      }
      return CatalogURLSetting(urls: updated, isLocked: false)
    }
  }

  public func androidSDKPath() -> AndroidSDKPathSetting {
    AndroidSDKPathSetting(value: self.store.androidSDKPath(), isLocked: self.store.isAndroidSDKPathForced())
  }

  public func setAndroidSDKPath(_ path: String?) throws(PreferencesError) {
    try self.lock.withLock { _ throws(PreferencesError) in
      guard !self.store.isAndroidSDKPathForced() else {
        throw .locked
      }
      self.store.setAndroidSDKPath(path)
    }
  }

  public func acceptedAndroidLicenses() -> Set<String> {
    Set(self.store.acceptedAndroidLicenses())
  }

  /// 최신 배열을 다시 읽어 없는 지문만 정렬해 끝에 붙인다 (있는 항목의 순서는 그대로).
  public func addAcceptedAndroidLicenses(_ fingerprints: Set<String>) throws(PreferencesError) {
    try self.lock.withLock { _ throws(PreferencesError) in
      guard !self.store.isAcceptedAndroidLicensesForced() else {
        throw .locked
      }
      let stored = self.store.acceptedAndroidLicenses()
      let added = fingerprints.subtracting(stored).sorted()
      guard !added.isEmpty else {
        return
      }
      self.store.setAcceptedAndroidLicenses(stored + added)
    }
  }
}
