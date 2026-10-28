import Core
import Foundation
import Synchronization
@testable import PreferencesImpl

/// 메모리 저장소. 읽기·쓰기 각각만 자기 lock 으로 보호하고, 읽기는 값을 복사한 뒤 잠깐 쉬고 돌려준다.
/// 읽기와 쓰기 사이를 넓혀, Impl 의 lock 이 "읽기 → 판정 → 쓰기" 를 묶지 않으면 동시 추가에서 쓰기를 잃게 한다.
final class InMemoryPreferenceStore: PreferenceStore {
  private struct State {
    var urls: [String]
    var isForced: Bool
    var setCount = 0
    var androidSDKPath: AndroidSDKPathSetting.Value = .absent
    var isAndroidSDKPathForced = false
    var androidSDKPathSetCount = 0
    var licenses: [String] = []
    var isLicensesForced = false
    var licensesSetCount = 0
  }

  private let state: Mutex<State>

  init(urls: [String] = [], isForced: Bool = false) {
    self.state = Mutex(State(urls: urls, isForced: isForced))
  }

  /// `setCatalogURLs(_:)` 가 불린 횟수.
  var setCount: Int {
    self.state.withLock { $0.setCount }
  }

  /// 저장된 목록 (쉬지 않고 읽는다).
  var urls: [String] {
    self.state.withLock { $0.urls }
  }

  /// 바깥 변경(`defaults write`·MDM)을 흉내 낸다. `setCount` 에 넣지 않는다.
  func replace(urls: [String], isForced: Bool) {
    self.state.withLock { state in
      state.urls = urls
      state.isForced = isForced
    }
  }

  func catalogURLs() -> [String] {
    let urls = self.state.withLock { $0.urls }
    usleep(50)
    return urls
  }

  func isCatalogURLsForced() -> Bool {
    self.state.withLock { $0.isForced }
  }

  func setCatalogURLs(_ urls: [String]) {
    self.state.withLock { state in
      state.urls = urls
      state.setCount += 1
    }
  }

  /// `setAndroidSDKPath(_:)` 가 불린 횟수.
  var androidSDKPathSetCount: Int {
    self.state.withLock { $0.androidSDKPathSetCount }
  }

  /// `setAcceptedAndroidLicenses(_:)` 가 불린 횟수.
  var licensesSetCount: Int {
    self.state.withLock { $0.licensesSetCount }
  }

  /// 저장된 지문 배열 (쉬지 않고 읽는다).
  var licenses: [String] {
    self.state.withLock { $0.licenses }
  }

  /// 바깥 변경을 흉내 낸다. 쓰기 횟수에 넣지 않는다.
  func replaceAndroidSDKPath(_ value: AndroidSDKPathSetting.Value, isForced: Bool) {
    self.state.withLock { state in
      state.androidSDKPath = value
      state.isAndroidSDKPathForced = isForced
    }
  }

  /// 바깥 변경을 흉내 낸다. 쓰기 횟수에 넣지 않는다.
  func replaceLicenses(_ fingerprints: [String], isForced: Bool) {
    self.state.withLock { state in
      state.licenses = fingerprints
      state.isLicensesForced = isForced
    }
  }

  func androidSDKPath() -> AndroidSDKPathSetting.Value {
    self.state.withLock { $0.androidSDKPath }
  }

  func isAndroidSDKPathForced() -> Bool {
    self.state.withLock { $0.isAndroidSDKPathForced }
  }

  func setAndroidSDKPath(_ path: String?) {
    self.state.withLock { state in
      state.androidSDKPath = path.map { .path($0) } ?? .absent
      state.androidSDKPathSetCount += 1
    }
  }

  func acceptedAndroidLicenses() -> [String] {
    let licenses = self.state.withLock { $0.licenses }
    usleep(50)
    return licenses
  }

  func isAcceptedAndroidLicensesForced() -> Bool {
    self.state.withLock { $0.isLicensesForced }
  }

  func setAcceptedAndroidLicenses(_ fingerprints: [String]) {
    self.state.withLock { state in
      state.licenses = fingerprints
      state.licensesSetCount += 1
    }
  }
}
