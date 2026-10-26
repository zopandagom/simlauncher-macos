import Core
import DownloadInterface
import Foundation
import Observation
import PreferencesInterface

/// 카탈로그에서 설치 시트의 상태와 로직. 시트를 열 때와 새로 고칠 때만 등록 카탈로그를 동시에 받아 메인 밖에서 해석하고,
/// 카탈로그마다 결과가 오는 대로 보인다. 설치는 App 이 주입한 `installRequested` 로 기기 목록 화면(LauncherModel)에 넘긴다.
/// 대상은 행 메뉴면 그 기기 한 대, 툴바면 목록에서 고른 기기 전부다.
/// 기기 목록·진행 작업·알림 상태를 함께 쓰지 않아 LauncherModel 과 나눴다 (ARCHITECTURE §1).
@MainActor
@Observable
public final class CatalogInstallModel {
  /// nil 이면 시트가 닫혀 있다.
  public private(set) var draft: CatalogInstallDraft?

  @ObservationIgnored private let preferences: any PreferencesClient
  @ObservationIgnored private let download: any DownloadClient
  /// "받아서 설치" 를 눌렀을 때 부른다. App 이 `LauncherModel.catalogInstallRequested(_:)` 로 잇는다 (화면 간 흐름은 App 이 잇는다).
  @ObservationIgnored private let installRequested: @MainActor (CatalogInstallRequest) async -> Void
  /// 진행 중인 받기. Model 이 소유해 View 의 Task 가 취소돼도 돈다. 닫기·새로 고침이 취소한다.
  @ObservationIgnored private var loadTask: Task<Void, Never>?

  public init(
    preferences: any PreferencesClient,
    download: any DownloadClient,
    installRequested: @escaping @MainActor (CatalogInstallRequest) async -> Void = { _ in }
  ) {
    self.preferences = preferences
    self.download = download
    self.installRequested = installRequested
  }

  /// 행 "앱 설치" 메뉴 "카탈로그에서…": 시트가 닫혀 있고 설치할 수 있는 기기(Core `appInstallAvailability`)면 열고 받는다.
  /// 같은 기기의 진행 중 작업은 행이 메뉴를 비활성으로 막는다 (이 Model 은 기기 작업을 모른다). 받기가 끝날 때까지 기다린다.
  public func menuTapped(_ device: VirtualDevice) async {
    guard self.draft == nil, device.appInstallAvailability == .allowed else { return }
    self.draft = CatalogInstallDraft(targets: [TargetDevice(device)])
    await self.load()
  }

  /// 툴바 "선택한 기기에 앱 설치" > "카탈로그에서…": 시트가 닫혀 있고 고른 기기(지금 목록 순서) 중 하나라도 설치할 수 있는
  /// 기기면 고른 기기 모두를 대상으로 열고 받는다. 한 대면 `menuTapped(_:)` 와 같다. 다른 작업 중인 기기는 LauncherModel 이
  /// 설치를 시작할 때 이유와 함께 건너뛴다. 받기가 끝날 때까지 기다린다.
  public func selectionMenuTapped(_ devices: [VirtualDevice]) async {
    guard self.draft == nil, devices.contains(where: { $0.appInstallAvailability == .allowed }) else { return }
    self.draft = CatalogInstallDraft(targets: devices.map(TargetDevice.init))
    await self.load()
  }

  /// 시트의 "새로 고침": 설정을 다시 읽고 모두 다시 받는다. 받는 중이면 그 받기를 취소하고 새로 시작한다. 끝날 때까지 기다린다.
  public func refreshButtonTapped() async {
    await self.load()
  }

  public func appSelected(_ key: CatalogAppKey?) {
    self.draft?.appSelected(key)
  }

  public func versionSelected(_ id: BuildCatalog.VersionID?) {
    self.draft?.versionSelected(id)
  }

  public func cancelTapped() {
    self.close()
  }

  /// ESC·바깥 닫기 (시트 Binding 의 set false). 두 번 불려도 무해하다.
  public func sheetDismissed() {
    self.close()
  }

  /// 고른 버전이 있으면 첫 await 전에 시트를 닫고(받기 취소) 설치를 요청한다. 설치가 끝날 때까지 기다린다.
  public func installButtonTapped() async {
    guard let draft = self.draft, let version = draft.selectedVersion else { return }
    // 첫 await 전에 닫아, 연타해도 두 번째 호출은 위에서 끝난다.
    self.close()
    await self.installRequested(CatalogInstallRequest(targets: draft.targets, buildURL: version.buildURL))
  }

  /// 설정을 읽어 구역을 다시 만들고, 쓸 수 있는 카탈로그를 모두 동시에 받는다. 결과는 오는 대로(끝난 순서) 받기 식별자를
  /// 확인한 뒤 넣는다: 새로 고침·닫기 뒤에 온 옛 결과(취소를 보지 않는 해석의 늦은 성공 포함)는 버려진다.
  private func load() async {
    guard self.draft != nil else { return }
    self.loadTask?.cancel()
    let id = UUID()
    // 설정 읽기(동기)와 구역 재구성, Task 저장 사이에 await 를 두지 않는다 (취소가 Task 를 놓치지 않게).
    guard let targets = self.draft?.beginLoad(self.preferences.catalogURLs(), id: id) else { return }
    let download = self.download
    let task = Task {
      await withTaskGroup(of: (CatalogSource.ID, Result<BuildCatalog, CatalogLoadFailure>).self) { group in
        for target in targets {
          group.addTask {
            await (target.sourceID, CatalogLoad.result(target.url, download: download))
          }
        }
        for await (sourceID, result) in group {
          self.draft?.loaded(result, for: sourceID, id: id)
        }
      }
    }
    self.loadTask = task
    await task.value
  }

  /// 받기를 취소하고 시트를 닫는다. 늦게 온 결과는 draft 가 없어 아무 일도 하지 않는다.
  private func close() {
    self.loadTask?.cancel()
    self.loadTask = nil
    self.draft = nil
  }
}
