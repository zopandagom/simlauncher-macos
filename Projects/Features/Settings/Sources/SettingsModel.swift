import AndroidSDKInterface
import Core
import DownloadInterface
import Foundation
import Observation
import PreferencesInterface

/// 설정 창의 빌드 카탈로그 목록. 주소를 입력해 "등록" 하면 한 번 받아(`fetchData`, 상한 `BuildCatalog.maxByteCount`)
/// 메인 밖에서 해석하고(`BuildCatalog.decoded(from:)`), 통과해야 저장한다. 확인 중 취소·창 닫기·다시 열기는 확인을 취소한다.
/// 관리자가 강제한 목록이면 바꾸지 않는다. 창이 열린 채 바깥에서 바뀐 값은 다음 창 열기·추가·삭제 때 반영한다.
/// Android SDK 위치: 고른 폴더를 판정해(`inspectCandidateFolder`) 빈 폴더나 SDK 폴더만 저장하고, 기본 위치로 되돌릴 수 있다.
/// 저장 값이 실제로 바뀌면 App 이 주입한 `androidSDKLocationChanged` 를 부른다 (Android 화면이 다시 확인하게. 같은 앱의 다른 창이라
/// 앱 활성화 알림이 오지 않는다). 관리자가 강제한 위치면 바꾸지 않는다.
/// Settings 씬의 View 와 이 Model 은 앱 시작 때 한 번 만들어지므로, 생성자는 저장만 하고 읽기는 `onAppear()` 에서 한다.
@MainActor
@Observable
public final class SettingsModel {
  /// 마지막으로 읽은 목록·잠금. `onAppear`·추가·삭제 뒤 최신 값으로 바꾼다.
  public private(set) var setting: CatalogURLSetting = .empty
  /// 입력란 글자.
  public private(set) var draftText = ""
  /// 등록 확인 중인 주소. nil 이면 확인 중이 아니다.
  public private(set) var checkingURL: DownloadURL?
  /// 마지막 등록 결과 줄. 입력을 바꾸거나 새 등록·삭제·창 열기 때 지운다.
  public private(set) var result: CatalogRegistrationResult?
  /// 마지막으로 읽은 Android SDK 위치 설정·잠금. `onAppear`·고르기·되돌리기 뒤 최신 값으로 바꾼다.
  public private(set) var androidSDKPath: AndroidSDKPathSetting = .absent
  /// 마지막 폴더 고르기의 판정 결과 줄. 창 열기·되돌리기·새로 고르기 때 지운다.
  public private(set) var androidSDKCandidate: SettingsSDKFolderResult?
  /// 고른 폴더를 판정하는 중이다. 그동안 다시 고르기·되돌리기는 무시한다.
  public private(set) var isInspectingSDKFolder = false

  @ObservationIgnored private let preferences: any PreferencesClient
  @ObservationIgnored private let download: any DownloadClient
  /// 진행 중인 확인. Model 이 소유해 View 의 Task 가 취소돼도 돈다.
  @ObservationIgnored private var checkTask: Task<Void, Never>?
  /// 지금 확인의 식별자. 취소·창 닫기·다시 열기·새 확인 뒤 늦게 끝난 확인의 결과를 버린다.
  @ObservationIgnored private var checkID: UUID?
  @ObservationIgnored private let androidSDK: any AndroidSDKClient
  /// 사용자 홈. 저장 값을 위치로 풀 때(`AndroidSDKRootChoice.resolve`) 쓴다. App 이 provider 와 같은 값을 넘긴다.
  @ObservationIgnored private let home: URL
  @ObservationIgnored private let androidSDKLocationChanged: @MainActor () -> Void
  /// 지금 폴더 판정의 식별자. 창 닫기·다시 열기 뒤 늦게 끝난 판정의 결과를 버린다 (판정은 파일만 읽어 취소하지 않는다).
  @ObservationIgnored private var inspectionID: UUID?

  public init(
    preferences: any PreferencesClient,
    download: any DownloadClient,
    androidSDK: any AndroidSDKClient,
    home: URL,
    androidSDKLocationChanged: @escaping @MainActor () -> Void
  ) {
    self.preferences = preferences
    self.download = download
    self.androidSDK = androidSDK
    self.home = home
    self.androidSDKLocationChanged = androidSDKLocationChanged
  }

  /// 저장된 목록의 줄마다 상태 (Core `CatalogURLList.entries`).
  public var entries: [CatalogURLEntry] {
    CatalogURLList.entries(self.setting.urls)
  }

  /// 입력란 아래 안내. 빈 입력은 nil (버튼만 비활성).
  public var draftProblem: CatalogDraftProblem? {
    if let problem = DownloadURL.problem(in: self.draftText) {
      return problem == .empty ? nil : .url(problem)
    }
    guard let url = DownloadURL(self.draftText),
          CatalogURLList.indexOfSameCatalog(as: url, in: self.setting.urls) != nil
    else { return nil }
    return .duplicate
  }

  /// "등록" 을 누를 수 있다: 잠기지 않았고, 확인 중이 아니고, 입력이 주소 검사를 통과하고 이미 등록된 카탈로그가 아니다.
  public var canAdd: Bool {
    !self.setting.isLocked && self.checkingURL == nil && DownloadURL(self.draftText) != nil && self.draftProblem == nil
  }

  /// 입력란·삭제 버튼을 보인다.
  public var canEdit: Bool {
    !self.setting.isLocked
  }

  /// 지금 설정이 가리키는 SDK 위치 (Core 규칙). 저장 값을 경로로 읽을 수 없으면 `.invalidSetting`.
  public var androidSDKRootChoice: AndroidSDKRootChoice {
    AndroidSDKRootChoice.resolve(self.androidSDKPath.value, home: self.home)
  }

  /// "다른 폴더 고르기…" 를 누를 수 있다: 잠기지 않았고 판정 중이 아니다.
  public var canChooseSDKFolder: Bool {
    !self.androidSDKPath.isLocked && !self.isInspectingSDKFolder
  }

  /// "기본 위치로 되돌리기" 를 누를 수 있다: 고를 수 있고, 지금 위치가 기본이 아니다 (잘못된 값도 되돌릴 수 있다).
  public var canResetSDKFolder: Bool {
    guard self.canChooseSDKFolder else { return false }
    if case let .root(root) = self.androidSDKRootChoice {
      return !root.isDefault
    }
    return true
  }

  /// 창이 열릴 때마다: 남은 확인·판정을 버리고, 최신 목록·SDK 위치를 읽고, 입력과 결과 줄을 지운다.
  public func onAppear() {
    self.cancelCheck()
    self.dropInspection()
    self.setting = self.preferences.catalogURLs()
    self.androidSDKPath = self.preferences.androidSDKPath()
    self.draftText = ""
    self.result = nil
    self.androidSDKCandidate = nil
  }

  /// 창이 닫힐 때: 확인을 취소하고(등록하지 않는다) 판정 중인 폴더는 저장하지 않는다. 글자·결과는 다음 `onAppear()` 가 지운다.
  public func windowClosed() {
    self.cancelCheck()
    self.dropInspection()
  }

  /// 확인 중에는 무시한다 (입력란도 비활성).
  public func catalogURLTextChanged(_ text: String) {
    guard self.checkingURL == nil else { return }
    self.draftText = text
    self.result = nil
  }

  /// "등록" (입력란 Return 포함). `canAdd` 가 아니면 무시한다. 확인이 끝날 때까지(취소되면 그 확인이 끝날 때까지) 기다린다.
  public func addButtonTapped() async {
    guard self.canAdd, let url = DownloadURL(self.draftText) else { return }
    self.result = nil
    self.checkingURL = url
    let id = UUID()
    self.checkID = id
    let task = Task {
      await self.check(url, id: id)
    }
    self.checkTask = task
    await task.value
  }

  /// 확인 중 "취소". 글자는 그대로 두고(고쳐서 다시 누를 수 있게) 결과 줄은 남기지 않는다.
  public func cancelCheckTapped() {
    guard self.checkingURL != nil else { return }
    self.cancelCheck()
  }

  /// 저장된 문자열(행 인덱스가 아니라)로 지운다. 같은 문자열이 여러 번 있으면 모두 지운다. 잠겼으면 무시한다.
  public func removeButtonTapped(_ raw: String) {
    guard !self.setting.isLocked else { return }
    self.result = nil
    do throws(PreferencesError) {
      self.setting = try self.preferences.removeCatalogURL(raw)
    } catch {
      // 창을 연 뒤 관리자가 잠갔다: 다시 읽어 잠금 안내로 바꾼다.
      self.setting = self.preferences.catalogURLs()
    }
  }

  /// 폴더 고르기 패널에서 폴더를 골랐다. 잠겼거나 판정 중이면 무시한다. 판정해 빈 폴더(쓸 수 있을 때)·SDK 폴더면 저장하고
  /// (기본 위치와 같으면 키를 지운다), 그 밖이면 저장하지 않고 이유를 결과 줄에 둔다.
  public func sdkFolderChosen(_ url: URL) async {
    guard self.canChooseSDKFolder else { return }
    self.androidSDKCandidate = nil
    self.isInspectingSDKFolder = true
    let id = UUID()
    self.inspectionID = id
    let inspection = await self.androidSDK.inspectCandidateFolder(url)
    // 창 닫기·다시 열기가 식별자를 바꾸므로 이 확인 하나로 늦은 판정을 버린다.
    guard self.inspectionID == id else { return }
    self.dropInspection()
    let path = url.path(percentEncoded: false)
    let result = SettingsSDKFolderResult(path: path, candidate: inspection.candidate, writable: inspection.writable)
    guard result.isSaved else {
      self.androidSDKCandidate = result
      return
    }
    let isDefault = if case let .root(root) = AndroidSDKRootChoice.resolve(.path(path), home: self.home) {
      root.isDefault
    } else {
      false
    }
    if self.saveAndroidSDKPath(isDefault ? nil : path) {
      self.androidSDKCandidate = result
    }
  }

  /// "기본 위치로 되돌리기". 누를 수 없으면 무시한다.
  public func sdkDefaultButtonTapped() {
    guard self.canResetSDKFolder else { return }
    self.androidSDKCandidate = nil
    self.saveAndroidSDKPath(nil)
  }

  /// 저장하고 다시 읽는다. 저장 직전에 읽은 위치와 달라졌을 때만 Android 화면에 알린다. 바깥에서 잠겼으면 다시 읽어 잠금 안내로 바꾸고
  /// false 를 돌려준다.
  @discardableResult
  private func saveAndroidSDKPath(_ path: String?) -> Bool {
    let before = AndroidSDKRootChoice.resolve(self.preferences.androidSDKPath().value, home: self.home)
    let saved: Bool
    do throws(PreferencesError) {
      try self.preferences.setAndroidSDKPath(path)
      saved = true
    } catch {
      saved = false
    }
    self.androidSDKPath = self.preferences.androidSDKPath()
    if self.androidSDKRootChoice != before {
      self.androidSDKLocationChanged()
    }
    return saved
  }

  /// 판정 중이 아닌 상태로 돌아간다. 늦게 끝나는 판정의 결과는 `inspectionID` 가 달라 버린다.
  private func dropInspection() {
    self.inspectionID = nil
    self.isInspectingSDKFolder = false
  }

  /// 받기 → 해석 → (지금 확인일 때만) 저장. await 지점은 받기와 해석 두 곳이고, 저장은 동기다.
  private func check(_ url: DownloadURL, id: UUID) async {
    let data: Data
    do throws(DownloadError) {
      data = try await self.download.fetchData(url, maxBytes: BuildCatalog.maxByteCount)
    } catch .cancelled {
      // 취소를 누르지 않았는데 `.cancelled` 가 와도 "확인 중" 에 갇히지 않게 끝낸다.
      self.finish(id, nil)
      return
    } catch {
      self.finish(id, .failed(.download(error)))
      return
    }
    let catalog: BuildCatalog
    do throws(BuildCatalogProblem) {
      catalog = try await BuildCatalog.decoded(from: data)
    } catch {
      self.finish(id, .failed(.catalog(error)))
      return
    }
    // 취소하는 모든 경로가 checkID 를 바꾸므로 이 확인 하나로 늦은 성공을 버린다.
    guard self.checkID == id else { return }
    do throws(PreferencesError) {
      self.setting = try self.preferences.addCatalogURL(url)
      self.draftText = ""
      self.finish(id, .added(raw: CatalogURLList.storedString(for: url), appCount: catalog.apps.count))
    } catch {
      // 확인 중 바깥에서 잠겼거나 같은 카탈로그가 들어왔다: 다시 읽으면 잠금 안내나 중복 캡션으로 한 번 보인다.
      self.setting = self.preferences.catalogURLs()
      self.finish(id, nil)
    }
  }

  /// 지금 확인(`checkID == id`)일 때만 확인을 끝내고 결과 줄을 둔다. 다르면(취소 뒤 늦게 끝남) 아무것도 바꾸지 않는다.
  private func finish(_ id: UUID, _ result: CatalogRegistrationResult?) {
    guard self.checkID == id else { return }
    self.checkingURL = nil
    self.checkID = nil
    self.checkTask = nil
    self.result = result
  }

  /// 그 자리에서 확인 전으로 돌아간다. 늦게 끝나는 확인의 결과는 `checkID` 가 달라 버린다.
  private func cancelCheck() {
    self.checkTask?.cancel()
    self.checkTask = nil
    self.checkID = nil
    self.checkingURL = nil
  }
}
