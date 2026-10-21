import AppBundleInterface
import Core
import DownloadInterface
import Foundation
import Observation
import SimulatorInterface

/// 기기 목록 화면의 상태와 로직. iOS 시뮬레이터 기기 목록을 읽고, 기기를 켜고 끄며(켠 뒤 Simulator 앱을 연다),
/// 만들고 지우고 초기화한다. 고른 .app 이나 .app 을 담은 zip 을(풀어서), 또는 입력한 https 주소의 zip 을 받아 풀어서
/// 기기에 설치하고 바로 실행하며, 입력한 링크(딥링크·웹 주소)를 기기에서 연다 (모두 꺼져 있으면 켠다).
/// Xcode 준비와 iOS 시뮬레이터 설치는 여기서 하지 않고, Setup 진입 버튼으로 App 에 Setup 화면을 요청한다.
/// 상태를 바꾸지 않는 읽기 API(`canCreateDevice` 등)는 `LauncherModel+Reading.swift` 에 있다.
@MainActor
@Observable
public final class LauncherModel {
  public private(set) var listState: LauncherListState = .loading
  /// 목록을 읽는 중이다 (첫 로딩 포함).
  public private(set) var isRefreshing = false
  /// 기기별 진행 작업(켜기·끄기·삭제·초기화·앱 설치·링크 열기)과 URL 설치의 받기 단계. 같은 기기의 작업은 겹치지 않는다.
  public private(set) var activity = DeviceActivity()
  /// 닫지 않은 알림 줄.
  public private(set) var noticeQueue = LauncherNotices()
  /// 마지막으로 읽은 목록의 생성 선택지. 다시 읽기가 실패하면 이전 값을 유지한다.
  public private(set) var creationOptions = DeviceCreationOptions(
    inventory: DeviceInventory(devices: [], runtimes: [], deviceTypes: [])
  )
  /// 생성 시트 초안. nil 이면 시트가 닫혀 있다.
  public private(set) var createDraft: DeviceCreationDraft?
  /// 기기를 만드는 중이다. 한 번에 하나만 만든다.
  public private(set) var isCreating = false
  /// 확인을 기다리는 삭제·초기화. nil 이면 대화상자가 없다.
  public private(set) var pendingConfirmation: DeviceConfirmation?
  /// 링크 열기 시트 초안. nil 이면 시트가 닫혀 있다.
  public private(set) var openURLDraft: OpenURLDraft?
  /// URL 에서 설치 시트 초안. nil 이면 시트가 닫혀 있다.
  public private(set) var installURLDraft: InstallURLDraft?

  @ObservationIgnored private let simulator: any SimulatorClient
  @ObservationIgnored private let appBundle: any AppBundleClient
  @ObservationIgnored private let download: any DownloadClient
  /// Setup 진입 버튼(툴바 "개발 환경", 빈 화면의 "iOS 설치"·"다른 iOS 버전 설치", 목록 위 안내 줄의 "다른 iOS 버전 설치",
  /// 목록 읽기 실패 화면의 "개발 환경 열기")을 눌렀을 때 부른다. App 이 Setup 화면을 다시 연다 (화면 간 흐름은 App 이 잇는다).
  @ObservationIgnored private let setupRequested: @MainActor () -> Void
  /// 진행 중인 목록 읽기. Model 이 소유해 View 의 `.task` 가 취소돼도 끝까지 돈다.
  @ObservationIgnored private var loadTask: Task<Void, Never>?
  /// 읽는 동안 들어온 요청. 진행 중인 읽기가 끝나면 한 번 더 읽는다.
  @ObservationIgnored private var reloadRequested = false
  /// 기기별 받기 작업. Model 이 소유해 받기 취소(`downloadCancelTapped(_:)`)가 이것만 멈춘다.
  @ObservationIgnored private var downloadTasks: [
    VirtualDevice.ID: Task<Result<DownloadedFile, DownloadError>, Never>
  ] =
    [:]

  public init(
    simulator: any SimulatorClient,
    appBundle: any AppBundleClient,
    download: any DownloadClient,
    setupRequested: @escaping @MainActor () -> Void = {}
  ) {
    self.simulator = simulator
    self.appBundle = appBundle
    self.download = download
    self.setupRequested = setupRequested
  }

  /// 목록을 읽은 뒤(목록을 먼저 보인다) 남은 zip 풀기·받기 임시 폴더(앞선 실행이 남겼거나 지우지 못한 것)를 정리한다.
  /// 화면이 나타날 때마다 불리므로 Setup 화면에서 돌아올 때마다 다시 읽고 정리한다. 지금 쓰는 폴더는 Client 가 건너뛴다.
  public func onAppear() async {
    await self.reload()
    await self.appBundle.removeLeftoverExtractions()
    await self.download.removeLeftoverDownloads()
  }

  public func refreshButtonTapped() async {
    await self.reload()
  }

  /// Setup 진입 버튼(툴바 "개발 환경", 빈 화면·안내 줄의 iOS 설치, 목록 읽기 실패 화면의 "개발 환경 열기"): App 이 Setup 화면을
  /// 다시 연다. iOS 설치 버튼도 Setup 의 iOS 시뮬레이터 설치 단계로 갈 뿐 여기서 설치하지 않는다.
  /// 진행 중 작업과 관계없이 늘 누를 수 있다.
  public func setupButtonTapped() {
    self.setupRequested()
  }

  /// 꺼진 기기를 켜고, 성공하면 Simulator 앱을 연 뒤 목록을 다시 읽는다. 실패하면 알림을 띄우고 다시 읽는다.
  public func bootButtonTapped(_ id: VirtualDevice.ID) async {
    guard case let .loaded(list) = self.listState,
          let device = list.device(id: id),
          self.activity.begin(.boot, on: device)
    else { return }
    defer { self.activity.end(on: id) }
    // `begin(.boot)` 이 꺼진 기기만 받으므로 늘 켠다.
    guard await self.bootIfNeededAndShowSimulator(device, label: LauncherNotice.Device(device)) else { return }
    await self.reload()
  }

  /// 켜진 기기를 끄고 목록을 다시 읽는다. 실패하면 알림을 띄우고 다시 읽는다.
  public func shutdownButtonTapped(_ id: VirtualDevice.ID) async {
    guard case let .loaded(list) = self.listState,
          let device = list.device(id: id),
          self.activity.begin(.shutdown, on: device)
    else { return }
    defer { self.activity.end(on: id) }
    let label = LauncherNotice.Device(device)
    do throws(SimulatorError) {
      try await self.simulator.shutdown(id)
    } catch {
      self.enqueue(.shutdownFailed(label, error))
    }
    await self.reload()
  }

  // MARK: - 만들기

  /// 생성 시트를 연다. 선택지는 지금 목록의 스냅샷이다.
  public func createButtonTapped() {
    guard self.canCreateDevice else { return }
    self.createDraft = DeviceCreationDraft(options: self.creationOptions)
  }

  public func createNameChanged(_ name: String) {
    self.createDraft?.nameChanged(name)
  }

  public func createRuntimeChanged(_ id: DeviceRuntime.ID) {
    self.createDraft?.runtimeChanged(id)
  }

  public func createDeviceTypeChanged(_ id: DeviceType.ID) {
    self.createDraft?.deviceTypeChanged(id)
  }

  public func createCancelTapped() {
    self.createDraft = nil
  }

  public func createSheetDismissed() {
    self.createDraft = nil
  }

  /// 시트를 닫고 기기를 만든 뒤 목록을 다시 읽는다. 실패하면 알림을 띄우고(입력은 사라진다) 다시 읽는다.
  public func createConfirmTapped() async {
    guard let draft = self.createDraft,
          draft.canSubmit,
          !self.isCreating,
          let runtime = draft.runtime
    else { return }
    let name = DeviceName.normalized(draft.name)
    let label = LauncherNotice.Device(name: name, runtimeName: runtime.name)
    self.createDraft = nil
    self.isCreating = true
    defer { self.isCreating = false }
    do throws(SimulatorError) {
      _ = try await self.simulator.create(name: name, deviceType: draft.deviceTypeID, runtime: runtime.id)
    } catch {
      self.enqueue(.createFailed(label, error))
    }
    await self.reload()
  }

  // MARK: - 알림

  /// id 가 같은 알림만 지운다. 이미 닫았거나 없으면 아무것도 하지 않아, 두 번 불려도 다음 알림을 지우지 않는다.
  public func noticeDismissed(_ id: LauncherNoticeItem.ID) {
    self.noticeQueue.dismiss(id)
  }

  /// 기기 작업 실패는 늘 쌓는다. 새로 고침 실패는 같은 원인이 이미 줄에 있으면 쌓지 않는다.
  private func enqueue(_ notice: LauncherNotice) {
    self.noticeQueue.enqueue(notice)
  }

  /// 꺼져 있으면 켜고, 켜져 있던 기기도 Simulator 앱을 연다 (창을 닫아 두었어도 결과가 보이게). 켜기에 실패하면 알림을
  /// 띄우고 다시 읽은 뒤 false. 앱을 열지 못하면 알림만 띄우고 true (설치·실행·링크 열기는 창 없이 된다).
  private func bootIfNeededAndShowSimulator(_ device: VirtualDevice, label: LauncherNotice.Device) async -> Bool {
    if device.state == .shutdown {
      do throws(SimulatorError) {
        try await self.simulator.boot(device.id)
      } catch {
        self.enqueue(.bootFailed(label, error))
        await self.reload()
        return false
      }
    }
    do throws(SimulatorError) {
      try await self.simulator.openSimulatorApp()
    } catch {
      self.enqueue(.openAppFailed(label, error))
    }
    return true
  }

  /// 목록을 읽는다. 읽는 중이면 새로 시작하지 않고 그 읽기를 기다리며, 끝난 뒤 한 번 더 읽게 한다.
  private func reload() async {
    if let loadTask = self.loadTask {
      self.reloadRequested = true
      await loadTask.value
      return
    }
    let task = Task {
      self.isRefreshing = true
      repeat {
        self.reloadRequested = false
        if case .failed = self.listState {
          self.listState = .loading
        }
        // Task 클로저 안에서는 catch 의 에러 타입이 any Error 로 추론되므로 명시한다.
        do throws(SimulatorError) {
          let inventory = try await self.simulator.fetchInventory()
          self.listState = .loaded(DeviceList(inventory: inventory))
          self.creationOptions = DeviceCreationOptions(inventory: inventory)
        } catch {
          if case .loaded = self.listState {
            self.enqueue(.refreshFailed(error))
          } else {
            self.listState = .failed(error)
          }
        }
      } while self.reloadRequested
      self.isRefreshing = false
      self.loadTask = nil
    }
    self.loadTask = task
    await task.value
  }
}

// MARK: - 삭제·초기화

// `private(set)` 상태를 바꾸므로 같은 파일에 둔다.
public extension LauncherModel {
  /// 꺼진 기기의 삭제 확인을 띄운다.
  func deleteButtonTapped(_ id: VirtualDevice.ID) {
    self.requestConfirmation(.delete, for: id)
  }

  /// 꺼진·쓸 수 있는 기기의 초기화 확인을 띄운다.
  func eraseButtonTapped(_ id: VirtualDevice.ID) {
    self.requestConfirmation(.erase, for: id)
  }

  func confirmationDismissed() {
    self.pendingConfirmation = nil
  }

  /// 확인한 삭제·초기화를 실행하고 목록을 다시 읽는다. 실패하면 알림을 띄우고 다시 읽는다.
  /// SwiftUI 는 대화상자 버튼 동작 뒤 곧바로 `confirmationDismissed()` 를 부르므로, `pendingConfirmation` 대신
  /// 버튼이 받은 값을 인자로 받는다. 확인을 기다리는 동안 바뀐 목록을 기준으로 다시 확인한다.
  func confirmationConfirmed(_ confirmation: DeviceConfirmation) async {
    if self.pendingConfirmation == confirmation {
      self.pendingConfirmation = nil
    }
    guard case let .loaded(list) = self.listState else { return }
    guard let device = list.device(id: confirmation.deviceID) else {
      self.enqueue(confirmation.failedNotice(.deviceNotFound))
      return
    }
    guard self.activity.task(on: device.id) == nil else { return }
    if case .blocked(.notShutdown) = confirmation.action.availability(for: device) {
      self.enqueue(confirmation.failedNotice(.deviceNotShutdown))
      return
    }
    // 남은 거절은 기다리는 동안 쓸 수 없게 된 경우뿐이다 (드묾). 행이 이유를 보인다.
    guard self.activity.begin(confirmation.action.task, on: device) else { return }
    defer { self.activity.end(on: device.id) }
    do throws(SimulatorError) {
      switch confirmation.action {
      case .delete: try await self.simulator.delete(device.id)
      case .erase: try await self.simulator.erase(device.id)
      }
    } catch {
      self.enqueue(confirmation.failedNotice(error))
    }
    await self.reload()
  }

  private func requestConfirmation(_ action: DeviceConfirmation.Action, for id: VirtualDevice.ID) {
    guard case let .loaded(list) = self.listState,
          let device = list.device(id: id),
          self.activity.canStart(action.task, on: device),
          self.pendingConfirmation == nil,
          self.openURLDraft == nil,
          self.installURLDraft == nil
    else { return }
    self.pendingConfirmation = DeviceConfirmation(action: action, deviceID: id, device: LauncherNotice.Device(device))
  }
}

// MARK: - 앱 설치

// `private(set)` 상태를 바꾸므로 같은 파일에 둔다.
public extension LauncherModel {
  /// 행의 "앱 설치" 메뉴 "파일에서 고르기…" 패널에서 고른 항목(.app, 또는 풀어서 쓰는 zip)을 설치하고 바로 실행한다
  /// (꺼져 있으면 켠다).
  func appFileSelected(_ url: URL, for id: VirtualDevice.ID) async {
    await self.installApp([url], on: id)
  }

  /// 행에 끌어다 놓은 항목(.app 이나 zip). 정확히 하나여야 하고, 둘 이상이면 이유를 알린다.
  func appDropped(_ urls: [URL], on id: VirtualDevice.ID) async {
    await self.installApp(urls, on: id)
  }

  /// 진행 중 기록은 여기서만 시작하고 끝낸다. 아래 단계의 어느 반환에서든 이 defer 하나가 진행 중을 푼다.
  private func installApp(_ items: [URL], on id: VirtualDevice.ID) async {
    guard case let .loaded(list) = self.listState,
          let device = list.device(id: id),
          self.activity.begin(.installApp, on: device)
    else { return }
    defer { self.activity.end(on: id) }
    let label = LauncherNotice.Device(device)
    guard let url = items.first else { return }
    guard items.count == 1 else {
      self.enqueue(.installFailed(label, .multipleItems))
      return
    }
    guard AppInstallSource.isZip(url) else {
      await self.installBundle(url, on: id, label: label)
      return
    }
    guard let extracted = await self.extract(url, label: label, failure: AppInstallFailure.bundle) else { return }
    await self.installExtracted(extracted, on: id, label: label)
  }

  /// zip 을 푼다. 실패하면 `failure` 로 만든 알림을 쌓고 nil (명령을 실행하기 전이라 다시 읽지 않는다.
  /// 풀다 만 폴더는 Impl 이 지웠다).
  private func extract(
    _ zip: URL,
    label: LauncherNotice.Device,
    failure: (AppBundleError) -> AppInstallFailure
  ) async -> ExtractedApp? {
    do throws(AppBundleError) {
      return try await self.appBundle.extractApp(fromZip: zip)
    } catch {
      self.enqueue(.installFailed(label, failure(error)))
      return nil
    }
  }

  /// 푼 .app 을 설치하고, 성공·실패와 관계없이 끝나면 임시 폴더를 지운다 (비동기 defer 를 쓰지 않으려고 실패가 모두
  /// 안에서 끝나는 `installBundle` 뒤에 둔다). 설치 명령이 번들을 기기로 복사한 뒤라 지워도 된다.
  /// 지우지 못하면 다음에 기기 목록 화면을 열 때 지운다.
  private func installExtracted(
    _ extracted: ExtractedApp,
    on id: VirtualDevice.ID,
    label: LauncherNotice.Device
  ) async {
    await self.installBundle(extracted.app, on: id, label: label)
    await self.appBundle.removeExtracted(extracted)
  }

  /// 검사·판정을 통과하면 설치하고 실행한다. 모든 실패가 안에서 알림으로 끝나 던지지 않는다.
  private func installBundle(_ url: URL, on id: VirtualDevice.ID, label: LauncherNotice.Device) async {
    guard let prepared = await self.prepareInstall(url, on: id, label: label) else { return }
    await self.runInstall(prepared.info, on: prepared.device, label: label)
  }

  /// 검사하고, 검사가 끝난 시점의 목록으로 기기와 앱을 판정한다. 실패하면 알림을 쌓고 nil
  /// (명령을 실행하지 않았으므로 다시 읽지 않는다).
  private func prepareInstall(
    _ url: URL,
    on id: VirtualDevice.ID,
    label: LauncherNotice.Device
  ) async -> (info: AppBundleInfo, device: VirtualDevice)? {
    let info: AppBundleInfo
    do throws(AppBundleError) {
      info = try await self.appBundle.inspect(url)
    } catch {
      self.enqueue(.installFailed(label, .bundle(error)))
      return nil
    }
    // 검사하는 동안 새로 고침으로 목록이 바뀌었을 수 있다. 이 기기의 작업은 지금 이 설치라 진행 중은 보지 않는다.
    let target = AppInstallTarget.current(id, in: self.listState)
    guard case let .ready(device) = target else {
      if let failure = target.installFailure {
        self.enqueue(.installFailed(label, failure))
      }
      return nil
    }
    if let problem = info.installProblem(on: device.runtime, hostArchitecture: self.appBundle.hostArchitecture) {
      self.enqueue(.installFailed(label, .rejected(problem)))
      return nil
    }
    return (info, device)
  }

  /// 꺼져 있으면 켜고, Simulator 앱을 열고, 검사한 경로를 설치하고, 검사한 번들 ID 로 실행한 뒤 다시 읽는다.
  private func runInstall(_ info: AppBundleInfo, on device: VirtualDevice, label: LauncherNotice.Device) async {
    guard await self.bootIfNeededAndShowSimulator(device, label: label) else { return }
    do throws(SimulatorError) {
      try await self.simulator.install(info.location, on: device.id)
    } catch {
      self.enqueue(.installFailed(label, .simulator(error)))
      await self.reload()
      return
    }
    do throws(SimulatorError) {
      try await self.simulator.launch(info.bundleID, on: device.id)
    } catch {
      self.enqueue(.launchFailed(label, error))
    }
    await self.reload()
  }
}

// MARK: - URL 에서 설치

// `private(set)` 상태를 바꾸므로 같은 파일에 둔다.
public extension LauncherModel {
  /// 행의 "앱 설치" 메뉴 "URL 에서…": 설치할 수 있는 기기이고 다른 시트·확인 대화상자가 없으면 시트를 연다.
  func installFromURLMenuTapped(_ id: VirtualDevice.ID) {
    guard case let .loaded(list) = self.listState,
          let device = list.device(id: id),
          self.activity.canStart(.installApp, on: device),
          self.installURLDraft == nil,
          self.openURLDraft == nil,
          self.createDraft == nil,
          self.pendingConfirmation == nil
    else { return }
    self.installURLDraft = InstallURLDraft(deviceID: id, device: LauncherNotice.Device(device))
  }

  func installURLTextChanged(_ text: String) {
    self.installURLDraft?.textChanged(text)
  }

  func installURLCancelTapped() {
    self.installURLDraft = nil
  }

  func installURLSheetDismissed() {
    self.installURLDraft = nil
  }

  /// 시트를 닫고 받은 뒤(행에 진행률·취소), 받은 zip 을 풀고 받은 파일을 지운 다음 고른 파일과 같은 경로로 검사·설치·실행한다.
  /// 기기는 시트를 연 사이 바뀌었을 수 있어 지금 목록으로 다시 확인한다 (받기 전 거절은 다시 읽지 않는다).
  func installURLConfirmTapped() async {
    guard let draft = self.installURLDraft, let url = draft.url else { return }
    // 첫 await 전에 닫아, 연타해도 두 번째 호출은 위에서 끝난다.
    self.installURLDraft = nil
    let label = draft.device
    let target = AppInstallTarget.current(draft.deviceID, in: self.listState)
    guard case let .ready(device) = target else {
      if let failure = target.installFailure {
        self.enqueue(.installFailed(label, failure))
      }
      return
    }
    // 남은 거절은 같은 기기의 다른 작업뿐이다 (시트가 창을 막아 드물고, 행의 진행 표시가 이유를 보인다).
    // 시작과 받기 Task 저장 사이에 await 를 두지 않는다 (취소가 Task 를 놓치지 않게).
    guard self.activity.beginDownload(on: device) else { return }
    defer { self.activity.end(on: device.id) }
    guard let file = await self.runDownload(url, on: device.id, label: label) else { return }
    self.activity.downloadEnded(on: device.id)
    // 받는 동안 기기가 목록에서 사라졌으면(외부 삭제, 드묾) 풀지 않는다. 켜는 중 같은 상태는 검사 뒤 판정에 맡긴다.
    if case .notFound = AppInstallTarget.current(device.id, in: self.listState) {
      await self.download.removeDownloaded(file)
      self.enqueue(.installFailed(label, .simulator(.deviceNotFound)))
      return
    }
    let mimeType = file.mimeType
    let extracted = await self.extract(file.file, label: label) { error in
      AppInstallFailure.downloaded(error, mimeType: mimeType)
    }
    // 푼 뒤에는 받은 파일이 필요 없다. 설치 명령이 푼 .app 을 기기로 복사하기 전에 지워 디스크를 덜 쓴다.
    await self.download.removeDownloaded(file)
    guard let extracted else { return }
    await self.installExtracted(extracted, on: device.id, label: label)
  }

  /// 행의 받기 취소: 받는 중일 때만 받기를 멈춘다. 받기가 막 끝났어도(늦은 취소) 받은 파일을 지우고 알림 없이 끝난다.
  /// 받기가 끝난 뒤(풀기·설치 중)에는 아무 일도 하지 않는다.
  func downloadCancelTapped(_ id: VirtualDevice.ID) {
    guard self.activity.requestDownloadCancel(on: id) else { return }
    self.downloadTasks[id]?.cancel()
  }

  /// Model 이 소유한 Task 로 받는다 (취소 버튼이 이 Task 만 멈추고, View 의 Task 취소는 전해지지 않는다).
  /// 취소를 눌렀으면 결과와 관계없이 알림 없이 nil (성공했으면 받은 파일을 지운다). 실패는 알림을 쌓고 nil
  /// (Client 가 폴더를 지웠다).
  private func runDownload(
    _ url: DownloadURL,
    on id: VirtualDevice.ID,
    label: LauncherNotice.Device
  ) async -> DownloadedFile? {
    let download = self.download
    let onProgress: @Sendable (DownloadProgress) async -> Void = { progress in
      await self.downloadProgressed(progress, on: id)
    }
    let task: Task<Result<DownloadedFile, DownloadError>, Never> = Task {
      await download.downloadResult(url, onProgress: onProgress)
    }
    self.downloadTasks[id] = task
    let result = await task.value
    self.downloadTasks[id] = nil
    if self.activity.isDownloadCancelRequested(on: id) {
      if case let .success(file) = result {
        await self.download.removeDownloaded(file)
      }
      return nil
    }
    switch result {
    case let .success(file):
      return file
    case let .failure(error):
      // 취소를 누르지 않았는데 온 `.cancelled` 도 이유 없이 행만 돌아가지 않게 알린다 (코드상 나오지 않는다).
      self.enqueue(.installFailed(label, .download(error)))
      return nil
    }
  }

  private func downloadProgressed(_ progress: DownloadProgress, on id: VirtualDevice.ID) {
    self.activity.downloadProgressed(progress, on: id)
  }
}

// MARK: - 링크 열기

// `private(set)` 상태를 바꾸므로 같은 파일에 둔다.
public extension LauncherModel {
  /// 행의 "링크 열기…": 링크를 열 수 있는 기기이고 다른 시트·확인 대화상자가 없으면 시트를 연다.
  func openURLButtonTapped(_ id: VirtualDevice.ID) {
    guard case let .loaded(list) = self.listState,
          let device = list.device(id: id),
          self.activity.canStart(.openURL, on: device),
          self.openURLDraft == nil,
          self.installURLDraft == nil,
          self.createDraft == nil,
          self.pendingConfirmation == nil
    else { return }
    self.openURLDraft = OpenURLDraft(deviceID: id, device: LauncherNotice.Device(device))
  }

  func openURLTextChanged(_ text: String) {
    self.openURLDraft?.textChanged(text)
  }

  func openURLCancelTapped() {
    self.openURLDraft = nil
  }

  func openURLSheetDismissed() {
    self.openURLDraft = nil
  }

  /// 시트를 닫고, 꺼져 있으면 켜고, Simulator 앱을 연 뒤 링크를 열고 다시 읽는다. 실패하면 알림을 띄운다.
  /// 기기는 시트를 연 사이 바뀌었을 수 있어 지금 목록으로 다시 확인한다 (명령 전 거절은 다시 읽지 않는다).
  func openURLConfirmTapped() async {
    // 링크에 문제가 있으면 버튼이 비활성이라 드물다. 시트와 입력은 그대로 둔다.
    guard let draft = self.openURLDraft, let link = draft.link else { return }
    // 첫 await 전에 닫아, 연타해도 두 번째 호출은 위에서 끝난다.
    self.openURLDraft = nil
    let label = draft.device
    let target = AppInstallTarget.current(draft.deviceID, in: self.listState)
    guard case let .ready(device) = target else {
      if let failure = target.openURLFailure {
        self.enqueue(.openURLFailed(label, failure))
      }
      return
    }
    // 남은 거절은 같은 기기의 다른 작업뿐이다. 시트가 창을 막아 시트를 연 뒤 그 기기 작업을 시작할 수 없어 드물고,
    // 행의 진행 표시가 이유를 보인다.
    guard self.activity.begin(.openURL, on: device) else { return }
    defer { self.activity.end(on: device.id) }
    // 막 켠 기기는 준비가 끝날 때까지 돌아오지 않는다 (콜드 부팅 직후 수십 초). 그동안 행이 진행 중을 보인다.
    guard await self.bootIfNeededAndShowSimulator(device, label: label) else { return }
    do throws(SimulatorError) {
      try await self.simulator.openURL(link, on: device.id)
    } catch {
      self.enqueue(.openURLFailed(label, .simulator(error)))
    }
    await self.reload()
  }
}
