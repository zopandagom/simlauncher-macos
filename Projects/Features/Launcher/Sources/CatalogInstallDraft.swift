import Core
import DownloadInterface
import Foundation
import PreferencesInterface

/// 카탈로그에서 설치 시트의 상태. 대상 기기는 "카탈로그에서…" 를 누른 시점의 값이다 (행 메뉴면 1대, 툴바면 고른 기기 전부).
/// 바꾸는 메서드는 Model 만 부른다 (View 는 `CatalogInstallModel.draft` 를 읽기만 한다).
public struct CatalogInstallDraft: Hashable, Sendable {
  /// 시트 제목과 설치 요청에 쓸 대상 기기 (1대 이상, 누른 시점의 목록 순서·이름·런타임 이름).
  public let targets: [TargetDevice]
  /// 마지막으로 읽은 설정의 잠금. 잠기면 사용자가 주소를 바꿀 수 없어, 빈 목록·쓸 수 없는 주소·카탈로그 읽기 실패의 다음 할 일이
  /// 담당자 안내로 바뀌고 "설정 열기" 를 숨긴다.
  public private(set) var isLocked = false
  /// 저장 순서. 같은 카탈로그(`.duplicate`)는 빠진다.
  public private(set) var sources: [CatalogSource] = []
  public private(set) var selectedApp: CatalogAppKey?
  public private(set) var selectedVersionID: BuildCatalog.VersionID?
  /// 지금 받기의 식별자. 늦게 온 결과(새로 고침 전·시트를 닫았다 다시 연 뒤)를 버린다.
  private var loadID: UUID?

  init(targets: [TargetDevice]) {
    self.targets = targets
  }

  /// 기기 한 대짜리 초안.
  init(deviceID: VirtualDevice.ID, device: LauncherNotice.Device) {
    self.init(targets: [TargetDevice(id: deviceID, label: device)])
  }

  /// 설정을 다시 읽은 값으로 구역을 새로 만들고(쓸 수 있는 주소는 `.loading`, 쓸 수 없으면 `.invalid`, 중복은 뺌) 받기 식별자를
  /// 바꾼다. 고른 앱·버전은 그 카탈로그가 새 설정에도 쓸 수 있는 주소로 있으면 그대로 두고(결과가 오면 `loaded` 가 확인한다),
  /// 없으면(지움·쓸 수 없게 됨·중복이 됨) 비운다. 받을 대상을 저장 순서로 돌려준다.
  mutating func beginLoad(_ setting: CatalogURLSetting, id: UUID) -> [CatalogLoadTarget] {
    var sources: [CatalogSource] = []
    var targets: [CatalogLoadTarget] = []
    for (index, entry) in CatalogURLList.entries(setting.urls).enumerated() {
      switch entry.status {
      case let .usable(url):
        let sourceID = url.comparisonKey
        sources.append(CatalogSource(id: sourceID, raw: entry.raw, state: .loading))
        targets.append(CatalogLoadTarget(sourceID: sourceID, url: url))
      case let .invalid(problem):
        sources.append(CatalogSource(id: "invalid-\(index)", raw: entry.raw, state: .invalid(problem)))
      case .duplicate:
        continue
      }
    }
    self.sources = sources
    self.isLocked = setting.isLocked
    self.loadID = id
    if let selected = self.selectedApp, !targets.contains(where: { $0.sourceID == selected.sourceID }) {
      self.clearSelection()
    }
    return targets
  }

  /// `id` 가 지금 받기일 때만 그 구역에 결과를 넣는다. 고른 앱이 그 구역이면: 실패면 선택을 비우고, 성공인데 앱이 없으면
  /// 선택을 비우고, 앱은 있는데 고른 버전이 없으면 버전 선택만 비운다 (다른 버전으로 바꾸지 않는다).
  mutating func loaded(
    _ result: Result<BuildCatalog, CatalogLoadFailure>,
    for sourceID: CatalogSource.ID,
    id: UUID
  ) {
    guard id == self.loadID, let index = self.sources.firstIndex(where: { $0.id == sourceID }) else { return }
    switch result {
    case let .success(catalog):
      self.sources[index].state = .loaded(catalog)
    case let .failure(failure):
      self.sources[index].state = .failed(failure)
    }
    guard let selected = self.selectedApp, selected.sourceID == sourceID else { return }
    guard let app = self.selectedAppValue else {
      self.clearSelection()
      return
    }
    if let versionID = self.selectedVersionID, !app.versions.contains(where: { $0.id == versionID }) {
      self.selectedVersionID = nil
    }
  }

  /// 읽힌 카탈로그에 있는 앱이면 고르고 가장 새 버전(`versions.first`, 없으면 nil)을 고른다. nil·없는 앱이면 선택을 비운다.
  mutating func appSelected(_ key: CatalogAppKey?) {
    guard let key, let app = self.app(for: key) else {
      self.clearSelection()
      return
    }
    self.selectedApp = key
    self.selectedVersionID = app.versions.first?.id
  }

  /// 고른 앱의 버전이면 고른다. 아니면(nil 포함) 무시한다.
  mutating func versionSelected(_ id: BuildCatalog.VersionID?) {
    guard let id, let app = self.selectedAppValue, app.versions.contains(where: { $0.id == id }) else { return }
    self.selectedVersionID = id
  }

  private mutating func clearSelection() {
    self.selectedApp = nil
    self.selectedVersionID = nil
  }

  private func app(for key: CatalogAppKey) -> BuildCatalog.App? {
    guard let source = self.sources.first(where: { $0.id == key.sourceID }),
          case let .loaded(catalog) = source.state
    else { return nil }
    // iOS 기기 시트라 iOS 앱만 찾는다. 새로 고침 뒤 Android 앱이 된 앱은 사라진 앱처럼 선택이 비워진다.
    return catalog.app(key.appID, for: .ios)
  }
}

// MARK: - 읽기

public extension CatalogInstallDraft {
  /// 고른 앱. 그 구역이 읽힌(`.loaded`) 상태이고 앱이 있을 때만.
  var selectedAppValue: BuildCatalog.App? {
    guard let key = self.selectedApp else { return nil }
    return self.app(for: key)
  }

  /// 고른 버전. 고른 앱의 구역이 읽힌 상태이고 앱·버전이 있을 때만 (새로 고침으로 읽는 중이면 nil).
  var selectedVersion: BuildCatalog.Version? {
    guard let versionID = self.selectedVersionID else { return nil }
    return self.selectedAppValue?.versions.first { $0.id == versionID }
  }

  /// 구역이 없다 (등록 없음. 중복은 첫 항목이 남으므로 비지 않는다).
  var isEmpty: Bool {
    self.sources.isEmpty
  }

  /// 빈 목록 화면에 "설정 열기" 를 보인다: 구역이 없고 잠기지 않았다.
  var showsOpenSettings: Bool {
    self.isEmpty && !self.isLocked
  }

  /// 구역의 상태 줄. 잠김은 이 값의 `isLocked` 를 담는다 (View 는 잠김을 따로 넘기지 않는다).
  func note(for source: CatalogSource) -> CatalogSourceNote? {
    switch source.state {
    case let .failed(failure):
      .failed(failure, isLocked: self.isLocked)
    case let .invalid(problem):
      .invalid(problem, isLocked: self.isLocked)
    case .loading, .loaded:
      nil
    }
  }

  /// 읽힌 구역에 iOS 앱이 없는 이유. 앱이 있거나 읽는 중·실패면 nil. View 는 이것으로만 고른다.
  func emptyReason(for source: CatalogSource) -> CatalogEmptyReason? {
    guard case let .loaded(catalog) = source.state, catalog.apps(for: .ios).isEmpty else { return nil }
    return catalog.apps.isEmpty ? .noApps : .noIOSApps
  }

  /// 읽는 중인 구역이 있다 (새로 고침 버튼 옆 진행 표시).
  var isLoading: Bool {
    self.sources.contains { $0.state == .loading }
  }

  var canInstall: Bool {
    self.selectedVersion != nil
  }

  /// 오른쪽 버전 칸에 보일 것. View 는 이것으로만 고른다.
  var versionPane: CatalogVersionPane {
    guard let key = self.selectedApp else { return .noSelection }
    if let source = self.sources.first(where: { $0.id == key.sourceID }), source.state == .loading {
      return .loading
    }
    guard let app = self.selectedAppValue else { return .noSelection }
    guard !app.versions.isEmpty else { return .noVersions }
    return .versions(app.versions)
  }
}

/// 읽힌 구역에 iOS 앱이 없는 이유.
public enum CatalogEmptyReason: Hashable, Sendable {
  /// 앱이 하나도 없다.
  case noApps
  /// Android 앱만 있다.
  case noIOSApps
}

/// 시트의 카탈로그 구역 하나.
public struct CatalogSource: Identifiable, Hashable, Sendable {
  public enum State: Hashable, Sendable {
    case loading
    case loaded(BuildCatalog)
    case failed(CatalogLoadFailure)
    case invalid(DownloadURLProblem)
  }

  /// 쓸 수 있는 주소는 `comparisonKey`, 쓸 수 없는 주소는 "invalid-<저장 순서>" (선택 대상이 아니다).
  public let id: String
  /// 저장된 문자열 그대로 (머리글).
  public let raw: String
  public fileprivate(set) var state: State
}

/// 구역의 상태 줄(받기·해석 실패, 쓸 수 없는 주소)과 그 다음 할 일을 고르는 잠김. 잠김을 함께 담아 View 가 빠뜨릴 수 없다.
public enum CatalogSourceNote: Hashable, Sendable {
  case failed(CatalogLoadFailure, isLocked: Bool)
  case invalid(DownloadURLProblem, isLocked: Bool)
}

/// 카탈로그 하나를 받지 못했거나 읽지 못한 이유.
public enum CatalogLoadFailure: Error, Hashable, Sendable {
  /// `.cancelled` 는 지금 받기에서는 나오지 않는다 (닫기·새로 고침이 식별자를 바꾼 뒤에만 취소한다). 와도 실패로 보인다.
  case download(DownloadError)
  case catalog(BuildCatalogProblem)
}

/// 앱 한 줄의 식별자: 카탈로그(구역 id)와 앱 id. 카탈로그 사이의 같은 앱 id 를 구별한다.
public struct CatalogAppKey: Hashable, Sendable {
  public let sourceID: CatalogSource.ID
  public let appID: BuildCatalog.AppID

  public init(sourceID: CatalogSource.ID, appID: BuildCatalog.AppID) {
    self.sourceID = sourceID
    self.appID = appID
  }
}

/// 오른쪽 버전 칸의 내용.
public enum CatalogVersionPane: Hashable, Sendable {
  /// 앱을 고르지 않았다.
  case noSelection
  /// 고른 앱의 카탈로그를 다시 읽는 중이다.
  case loading
  /// 고른 앱에 버전이 없다.
  case noVersions
  /// Core 정렬(최신순) 그대로.
  case versions([BuildCatalog.Version])
}

/// 받을 카탈로그 하나.
struct CatalogLoadTarget: Hashable, Sendable {
  let sourceID: CatalogSource.ID
  let url: DownloadURL
}

/// 카탈로그 하나 받기·해석. 상태가 없어 Model 파일 밖에 둔다. 메인 밖(TaskGroup 자식)에서 불린다.
enum CatalogLoad {
  /// `fetchData`(상한 `BuildCatalog.maxByteCount`) 실패는 `.download`, 해석(`BuildCatalog.decoded`, 메인 밖) 실패는 `.catalog`.
  /// 던지지 않고 값으로 돌려준다 (Task 클로저 안에서는 catch 의 에러 타입이 any Error 로 추론되므로 여기서 타입을 정한다).
  static func result(
    _ url: DownloadURL,
    download: any DownloadClient
  ) async -> Result<BuildCatalog, CatalogLoadFailure> {
    let data: Data
    do throws(DownloadError) {
      data = try await download.fetchData(url, maxBytes: BuildCatalog.maxByteCount)
    } catch {
      return .failure(.download(error))
    }
    do throws(BuildCatalogProblem) {
      return try await .success(BuildCatalog.decoded(from: data))
    } catch {
      return .failure(.catalog(error))
    }
  }
}
