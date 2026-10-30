import Core
import DownloadInterface
import Foundation
import Observation
import PreferencesInterface

/// Android 기기 행 "앱 설치" 메뉴의 "URL 에서…"·"카탈로그에서…" 시트의 상태와 로직. 둘은 동시에 하나만 연다.
/// URL 시트는 주소를 입력받고, 카탈로그 시트는 열 때와 새로 고칠 때만 등록 카탈로그를 동시에 받아 메인 밖에서 해석하고
/// 카탈로그마다 결과가 오는 대로 보인다 (Android 앱만). 고른 주소·버전은 App 이 주입한 `installRequested` 로 기기 목록 화면
/// (`AndroidDevicesModel.downloadInstallRequested(_:)`)에 넘기고, 받기·설치·진행 표시는 그쪽이 한다.
/// 기기 목록·진행 작업·알림 상태를 함께 쓰지 않아 `AndroidDevicesModel` 과 나눴다 (ARCHITECTURE §1. iOS 는 URL 시트가
/// `LauncherModel` 에 있다). `AndroidDevicesModel` 의 시트·확인 대화상자와 서로 막는 가드는 없고 모달 시트에 기댄다.
@MainActor
@Observable
public final class AndroidDownloadInstallModel {
  /// nil 이면 URL 시트가 닫혀 있다.
  public private(set) var urlDraft: AndroidInstallURLDraft?
  /// nil 이면 카탈로그 시트가 닫혀 있다.
  public private(set) var catalogDraft: AndroidCatalogInstallDraft?

  @ObservationIgnored private let preferences: any PreferencesClient
  @ObservationIgnored private let download: any DownloadClient
  /// "받아서 설치" 를 눌렀을 때 부른다. App 이 `AndroidDevicesModel.downloadInstallRequested(_:)` 로 잇는다.
  @ObservationIgnored private let installRequested: @MainActor (AndroidDownloadInstallRequest) async -> Void
  /// 진행 중인 카탈로그 받기. Model 이 소유해 View 의 Task 가 취소돼도 돈다. 닫기·새로 고침이 취소한다.
  @ObservationIgnored private var loadTask: Task<Void, Never>?

  public init(
    preferences: any PreferencesClient,
    download: any DownloadClient,
    installRequested: @escaping @MainActor (AndroidDownloadInstallRequest) async -> Void = { _ in }
  ) {
    self.preferences = preferences
    self.download = download
    self.installRequested = installRequested
  }

  // MARK: - URL 에서

  /// 행 "URL 에서…": 두 시트가 닫혀 있고 켜진·쓸 수 있는 기기면 연다. 같은 기기의 진행 중 작업은 행이 메뉴를 비활성으로 막는다.
  public func urlMenuTapped(_ device: AndroidVirtualDevice) {
    guard self.canOpenSheet(for: device) else { return }
    self.urlDraft = AndroidInstallURLDraft(deviceID: device.id, device: AndroidDeviceLabel(device))
  }

  public func urlTextChanged(_ text: String) {
    self.urlDraft?.textChanged(text)
  }

  public func urlCancelTapped() {
    self.urlDraft = nil
  }

  /// ESC·바깥 닫기 (시트 Binding 의 set false). 두 번 불려도 무해하다.
  public func urlSheetDismissed() {
    self.urlDraft = nil
  }

  /// 주소에 문제가 없으면 첫 await 전에 시트를 닫고 설치를 요청한다. 설치가 끝날 때까지 기다린다.
  public func urlInstallTapped() async {
    guard let draft = self.urlDraft, let url = draft.url else { return }
    // 첫 await 전에 닫아, 연타해도 두 번째 호출은 위에서 끝난다.
    self.urlDraft = nil
    await self.installRequested(
      AndroidDownloadInstallRequest(deviceID: draft.deviceID, device: draft.device, url: url, origin: .enteredURL)
    )
  }

  // MARK: - 카탈로그에서

  /// 행 "카탈로그에서…": 두 시트가 닫혀 있고 켜진·쓸 수 있는 기기면 열고 받는다. 받기가 끝날 때까지 기다린다.
  public func catalogMenuTapped(_ device: AndroidVirtualDevice) async {
    guard self.canOpenSheet(for: device) else { return }
    self.catalogDraft = AndroidCatalogInstallDraft(deviceID: device.id, device: AndroidDeviceLabel(device))
    await self.load()
  }

  /// 시트의 "새로 고침": 설정을 다시 읽고 모두 다시 받는다. 받는 중이면 그 받기를 취소하고 새로 시작한다. 끝날 때까지 기다린다.
  public func catalogRefreshTapped() async {
    await self.load()
  }

  public func catalogAppSelected(_ key: AndroidCatalogAppKey?) {
    self.catalogDraft?.appSelected(key)
  }

  public func catalogVersionSelected(_ id: BuildCatalog.VersionID?) {
    self.catalogDraft?.versionSelected(id)
  }

  public func catalogCancelTapped() {
    self.closeCatalog()
  }

  /// ESC·바깥 닫기 (시트 Binding 의 set false). 두 번 불려도 무해하다.
  public func catalogSheetDismissed() {
    self.closeCatalog()
  }

  /// 고른 버전이 있으면 첫 await 전에 시트를 닫고(받기 취소) 설치를 요청한다. 설치가 끝날 때까지 기다린다.
  public func catalogInstallTapped() async {
    guard let draft = self.catalogDraft, let version = draft.selectedVersion else { return }
    // 첫 await 전에 닫아, 연타해도 두 번째 호출은 위에서 끝난다.
    self.closeCatalog()
    await self.installRequested(
      AndroidDownloadInstallRequest(
        deviceID: draft.deviceID,
        device: draft.device,
        url: version.buildURL,
        origin: .catalog
      )
    )
  }

  // MARK: - 내부

  private func canOpenSheet(for device: AndroidVirtualDevice) -> Bool {
    self.urlDraft == nil && self.catalogDraft == nil && device.appActionAvailability == .allowed
  }

  /// 설정을 읽어 구역을 다시 만들고, 쓸 수 있는 카탈로그를 모두 동시에 받는다. 결과는 오는 대로(끝난 순서) 받기 식별자를
  /// 확인한 뒤 넣는다: 새로 고침·닫기 뒤에 온 옛 결과(취소를 보지 않는 해석의 늦은 성공 포함)는 버려진다.
  private func load() async {
    guard self.catalogDraft != nil else { return }
    self.loadTask?.cancel()
    let id = UUID()
    // 설정 읽기(동기)와 구역 재구성, Task 저장 사이에 await 를 두지 않는다 (취소가 Task 를 놓치지 않게).
    guard let targets = self.catalogDraft?.beginLoad(self.preferences.catalogURLs(), id: id) else { return }
    let download = self.download
    let task = Task {
      await withTaskGroup(of: (AndroidCatalogSource.ID, Result<BuildCatalog, AndroidCatalogLoadFailure>)
        .self)
      { group in
        for target in targets {
          group.addTask {
            await (target.sourceID, AndroidCatalogLoad.result(target.url, download: download))
          }
        }
        for await (sourceID, result) in group {
          self.catalogDraft?.loaded(result, for: sourceID, id: id)
        }
      }
    }
    self.loadTask = task
    await task.value
  }

  /// 받기를 취소하고 카탈로그 시트를 닫는다. 늦게 온 결과는 초안이 없어 아무 일도 하지 않는다.
  private func closeCatalog() {
    self.loadTask?.cancel()
    self.loadTask = nil
    self.catalogDraft = nil
  }
}
