import AndroidEmulatorInterface
import AndroidPackageInterface
import Core
import DownloadInterface
import Foundation
import Observation

/// Android 기기(AVD) 목록 화면의 상태와 로직. `~/.android/avd` 의 기기(Android Studio 가 만든 것 포함)를 읽고, 켜고 끄며,
/// 만들고 지우고 초기화한다. 목록에서 고른 기기(`selection`)를 함께 켜고, 실패가 있으면 결과를 알림 하나에 모은다.
/// 앱이 켜는 중인 기기는 끄기를 포함한 다른 작업을 막는다 (켜는 중에 끄면 기기가 망가질 수 있다, 실측). 앱 밖에서 켜는 중이거나
/// 켜기 대기가 시간 초과된 기기는 끌 수 있다.
/// 상태는 바깥(잠금 파일·adb)에서 정해지므로, 앱 작업 없이 "켜는 중" 인 기기가 있으면 화면이 보이는 동안 2초마다 다시 읽고
/// (`viewDisappeared()` 면 멈춘다), 앱 활성화 때 다시 읽은 뒤 3초 뒤 한 번 더 읽는다 (창을 닫은 직후 adb 가 아직 켜짐으로 답한 경우).
/// 모든 다시 읽기는 한 경로로 모아, 읽는 중에 온 요청은 지금 읽기가 끝난 뒤 한 번 더 읽는다.
/// 켜진 기기에는 로컬 apk(파일 고르기·드롭)나 URL·카탈로그에서 받은 apk(`AndroidDownloadInstallModel` 의 요청을 App 이 넘긴다.
/// 받기는 Model 이 소유하고 행에 진행·취소)를 설치·실행하고, 설치한 앱을 골라 실행하고, 링크를 연다 (앱 실행·링크 열기 시트는
/// `AndroidAppSheetsModel` 에 있고, 확정한 요청을 App 이 넘긴다). Client 호출은 흐름 타입이 맡는다: 기기 명령은
/// `AndroidDeviceCommandFlow`, 앱 작업은 `AndroidAppInstallFlow`.
/// Android 도구(SDK) 상태 확인·설치는 여기서 하지 않고, "Android 도구" 버튼으로 App 에 도구 화면을 요청한다.
/// 상태를 바꾸지 않는 읽기 API(`canCreateDevice` 등)는 `AndroidDevicesModel+Reading.swift` 에 있다.
@MainActor
@Observable
public final class AndroidDevicesModel {
  public private(set) var listState: AndroidDevicesListState = .loading
  /// 목록을 읽는 중이다 (첫 로딩 포함).
  public private(set) var isRefreshing = false
  /// 기기별 진행 작업(켜기·끄기·삭제·초기화·앱 설치·앱 실행·링크 열기). 같은 기기의 작업은 겹치지 않는다.
  public private(set) var activity = AndroidDeviceActivity()
  /// 닫지 않은 알림 줄.
  public private(set) var noticeQueue = AndroidDevicesNotices()
  /// 마지막으로 읽은 목록의 만들기 선택지. 다시 읽기가 실패하면 이전 값을 유지한다.
  public private(set) var creationOptions = AndroidDeviceCreationOptions(installedImages: [], host: .aarch64)
  /// 만들기 시트 초안. nil 이면 시트가 닫혀 있다.
  public private(set) var creationDraft: AndroidDeviceCreationDraft?
  /// 기기를 만드는 중이다. 한 번에 하나만 만든다.
  public private(set) var isCreating = false
  /// 확인을 기다리는 삭제·초기화. nil 이면 대화상자가 없다.
  public private(set) var confirmation: AndroidDeviceConfirmation?
  /// 목록에서 고른 기기 (⌘·⇧ 클릭). 툴바 "선택한 기기 켜기" 의 대상이고, 다시 읽은 목록에 없는 기기는 빠진다.
  public private(set) var selection: Set<AndroidVirtualDevice.ID> = []

  @ObservationIgnored private let emulator: any AndroidEmulatorClient
  /// 받기(흐름 둘과 화면을 열 때 남은 받기 폴더 정리). App 이 Launcher 와 같은 인스턴스를 넣는다.
  @ObservationIgnored private let download: any DownloadClient
  /// 기기 명령·앱 작업 흐름. 진행 기록을 시작한 Model 메서드 안에서만 부른다.
  @ObservationIgnored private let commandFlow: AndroidDeviceCommandFlow
  @ObservationIgnored private let appFlow: AndroidAppInstallFlow
  /// 기기별 받기 작업. Model 이 소유해 받기 취소(`downloadCancelTapped(_:)`)가 이것만 멈춘다. 결과를 받은 직후 지운다.
  @ObservationIgnored private var downloadTasks: [
    AndroidVirtualDevice.ID: Task<Result<DownloadedFile, DownloadError>, Never>
  ] = [:]
  /// 앱 실행·링크 열기 시트(`AndroidAppSheetsModel`)가 떠 있는지. App 이 그 Model 의 `hasPresentedSheet` 로 잇는다.
  @ObservationIgnored private let appSheetPresented: @MainActor () -> Bool
  /// "Android 도구" 버튼(툴바, 빈 화면·안내 줄의 "Android 도구 열기", 목록 읽기 실패 화면)을 눌렀을 때 부른다.
  /// App 이 Android 도구 화면을 다시 연다 (화면 간 흐름은 App 이 잇는다).
  @ObservationIgnored private let setupRequested: @MainActor () -> Void
  /// 자동 다시 읽기의 기다림. 테스트가 바꾼다.
  @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
  /// 진행 중인 목록 읽기. Model 이 소유해 View 의 `.task` 가 취소돼도 끝까지 돈다.
  @ObservationIgnored private var loadTask: Task<Void, Never>?
  /// 읽는 동안 들어온 요청. 진행 중인 읽기가 끝나면 한 번 더 읽는다.
  @ObservationIgnored private var reloadRequested = false
  /// 화면이 보인다 (`onAppear()` 뒤, `viewDisappeared()` 전). 보이지 않으면 자동 다시 읽기·위치 바뀜 다시 읽기를 하지 않는다.
  @ObservationIgnored private var isVisible = false
  /// 앱 작업 없이 켜는 중인 기기가 있을 때 2초 뒤 다시 읽는 Task.
  @ObservationIgnored private var autoRefreshTask: Task<Void, Never>?
  /// 앱 활성화 3초 뒤 한 번 더 읽는 Task.
  @ObservationIgnored private var activationTask: Task<Void, Never>?

  /// 앱 작업 없이 켜는 중인 기기가 있을 때 다시 읽는 간격.
  static let bootingRefreshInterval: Duration = .seconds(2)
  /// 앱 활성화 뒤 한 번 더 읽기까지의 시간.
  static let activationRefreshDelay: Duration = .seconds(3)

  public init(
    emulator: any AndroidEmulatorClient,
    package: any AndroidPackageClient,
    download: any DownloadClient,
    setupRequested: @escaping @MainActor () -> Void = {},
    appSheetPresented: @escaping @MainActor () -> Bool = { false },
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.emulator = emulator
    self.download = download
    self.commandFlow = AndroidDeviceCommandFlow(emulator: emulator)
    self.appFlow = AndroidAppInstallFlow(emulator: emulator, package: package, download: download)
    self.setupRequested = setupRequested
    self.appSheetPresented = appSheetPresented
    self.sleep = sleep
  }

  /// 시트(만들기·앱 실행·링크 열기)나 삭제·초기화 확인 대화상자가 떠 있다. 하나가 떠 있으면 다른 것을 열지 않는다.
  /// 앱 실행·링크 열기 시트는 `AndroidAppSheetsModel` 에 있어 App 이 주입한 클로저로 본다 (클로저가 `private` 이라 이 파일에 둔다).
  public var hasPresentedSheet: Bool {
    self.creationDraft != nil || self.confirmation != nil || self.appSheetPresented()
  }

  // MARK: - 화면·다시 읽기

  /// 목록을 읽고, 남은 받기 폴더를 지운다 (같은 Download 인스턴스라 지금 받는 폴더는 건너뛴다). Android 도구 화면에서 돌아올
  /// 때마다 새로 만들어진 View 가 부른다.
  public func onAppear() async {
    self.isVisible = true
    await self.reload()
    await self.download.removeLeftoverDownloads()
  }

  /// View 가 사라졌다 (칸을 옮기거나 Android 도구 화면으로 갔다). 자동 다시 읽기를 멈춘다.
  public func viewDisappeared() {
    self.isVisible = false
    self.autoRefreshTask?.cancel()
    self.autoRefreshTask = nil
    self.activationTask?.cancel()
    self.activationTask = nil
  }

  public func refreshButtonTapped() async {
    await self.reload()
  }

  /// Android Studio·에뮬레이터 창에서 바뀐 것을 반영한다. 만들기 시트가 열려 있으면 무시한다.
  /// 다시 읽고, 3초 뒤 한 번 더 읽는다 (창을 닫은 직후에는 adb 가 아직 켜짐으로 답할 수 있다).
  public func appBecameActive() async {
    guard self.isVisible, self.creationDraft == nil else { return }
    self.activationTask?.cancel()
    let sleep = self.sleep
    self.activationTask = Task {
      do {
        try await sleep(Self.activationRefreshDelay)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      self.activationTask = nil
      await self.reload()
    }
    await self.reload()
  }

  /// App 이 설정 창의 SDK 위치 변경을 넘긴다. 화면이 보이면 다시 읽는다 (보이지 않으면 나타날 때 읽는다).
  public func sdkLocationChanged() async {
    guard self.isVisible else { return }
    await self.reload()
  }

  /// "Android 도구" 버튼: App 이 Android 도구 화면을 다시 연다. 진행 중 작업과 관계없이 늘 누를 수 있다.
  public func setupButtonTapped() {
    self.setupRequested()
  }

  /// 목록의 선택이 바뀌었다 (클릭·⌘·⇧ 클릭·⌘A·빈 곳 클릭).
  public func selectionChanged(_ ids: Set<AndroidVirtualDevice.ID>) {
    self.selection = ids
  }
}

// `private(set)` 상태를 바꾸므로 같은 파일에 둔다.
public extension AndroidDevicesModel {
  // MARK: - 켜기·끄기

  /// 쓸 수 있는 꺼진 기기를 켜고(부팅 완료까지) 목록을 다시 읽는다. 실패하면 알림을 띄우고 다시 읽는다.
  func bootTapped(_ id: AndroidVirtualDevice.ID) async {
    guard case let .loaded(list) = self.listState,
          let device = list.device(id: id),
          self.activity.begin(.boot, on: device)
    else { return }
    defer { self.taskEnded(on: id) }
    await self.commandFlow.bootAndReport(device, host: self.appHost)
  }

  /// 툴바 "선택한 기기 켜기": 고른 기기 중 켤 수 있는 기기를 동시에 켠다 (켜져 있거나 작업 중·쓸 수 없는 기기는 알리지 않고
  /// 건너뛴다). 한 대면 행 "켜기" 와 같다. 여러 대면 먼저 끝난 기기부터 다시 읽고 풀며, 실패가 있으면 결과 알림 하나.
  func bootSelectedTapped() async {
    let start = self.activity.beginAll(.boot, on: self.selectedDevices)
    guard start.begun.count > 1 else {
      guard let device = start.begun.first else { return }
      defer { self.taskEnded(on: device.id, owner: start.owner) }
      return await self.commandFlow.bootAndReport(device, host: self.appHost)
    }
    let errors = await withTaskGroup(of: (AndroidVirtualDevice.ID, AndroidEmulatorError?).self) { group in
      for device in start.begun {
        group.addTask { await self.bootMember(device, owner: start.owner) }
      }
      var errors: [AndroidVirtualDevice.ID: AndroidEmulatorError] = [:]
      for await (id, error) in group {
        errors[id] = error
      }
      return errors
    }
    let report = AndroidBatchBootReport(entries: start.begun.map {
      AndroidBatchBootReport.Entry(device: AndroidDeviceLabel($0), error: errors[$0.id])
    })
    if report.needsNotice {
      self.enqueue(.batchBootFinished(report))
    }
  }

  /// 켜는 중(앱 밖에서 켜는 중·시간 초과 포함)이거나 켜진 기기를 끄고 목록을 다시 읽는다. 실패하면 알림을 띄우고 다시 읽는다.
  /// 앱이 켜는 중인 기기는 작업 기록이 막는다.
  func shutdownTapped(_ id: AndroidVirtualDevice.ID) async {
    guard case let .loaded(list) = self.listState,
          let device = list.device(id: id),
          self.activity.begin(.shutdown, on: device)
    else { return }
    defer { self.taskEnded(on: id) }
    await self.commandFlow.shutdown(device, host: self.appHost)
  }

  // MARK: - 만들기

  /// 만들기 시트를 연다. 선택지는 지금 목록의 스냅샷이다.
  func createButtonTapped() {
    guard self.canCreateDevice else { return }
    self.creationDraft = AndroidDeviceCreationDraft(options: self.creationOptions)
  }

  func creationNameChanged(_ name: String) {
    self.creationDraft?.nameChanged(name)
  }

  func creationImageChanged(_ image: AndroidSystemImageRef) {
    self.creationDraft?.imageChanged(image)
  }

  func creationProfileChanged(_ profile: AndroidDeviceProfile.ID) {
    self.creationDraft?.profileChanged(profile)
  }

  func creationCancelTapped() {
    self.creationDraft = nil
  }

  func creationSheetDismissed() {
    self.creationDraft = nil
  }

  /// 시트를 닫고 기기를 만든 뒤 목록을 다시 읽고 새 기기를 고른다. 실패하면 알림을 띄우고(입력은 사라진다) 다시 읽는다.
  func creationConfirmTapped() async {
    guard let draft = self.creationDraft, draft.canSubmit, !self.isCreating else { return }
    let name = DeviceName.normalized(draft.name)
    // 첫 await 전에 닫아, 연타해도 두 번째 호출은 위에서 끝난다.
    self.creationDraft = nil
    self.isCreating = true
    defer { self.isCreating = false }
    let label = AndroidDeviceLabel(name: name, apiLabel: draft.image.apiLabel)
    if let id = await self.commandFlow.create(
      name: name, image: draft.image, profile: draft.profile, label: label, host: self.appHost
    ) {
      // 다시 읽은 목록에 있으면 남는다 (`reload` 가 목록에 없는 선택을 뺀다). 그래서 고른 뒤에 다시 읽는다.
      self.selection = [id]
    }
    await self.reload()
  }

  // MARK: - 삭제·초기화

  /// 꺼진 기기의 삭제 확인을 띄운다 (쓸 수 없는 기기도 지울 수 있다).
  func deleteTapped(_ id: AndroidVirtualDevice.ID) {
    self.requestConfirmation(.delete, for: id)
  }

  /// 꺼진·쓸 수 있는 기기의 초기화 확인을 띄운다.
  func eraseTapped(_ id: AndroidVirtualDevice.ID) {
    self.requestConfirmation(.erase, for: id)
  }

  func confirmationCancelled() {
    self.confirmation = nil
  }

  /// 확인한 삭제·초기화를 실행하고 목록을 다시 읽는다. 실패하면 알림을, 삭제가 기기 폴더를 남겼으면 정보 알림을 띄운다.
  /// SwiftUI 는 대화상자 버튼 동작 뒤 곧바로 `confirmationCancelled()` 를 부르므로, `confirmation` 대신 버튼이 받은 값을
  /// 인자로 받는다. 확인을 기다리는 동안 바뀐 목록을 기준으로 다시 확인한다.
  func confirmationConfirmTapped(_ confirmation: AndroidDeviceConfirmation) async {
    if self.confirmation == confirmation {
      self.confirmation = nil
    }
    guard case let .loaded(list) = self.listState else { return }
    guard let device = list.device(id: confirmation.deviceID) else {
      self.enqueue(confirmation.failedNotice(.deviceNotFound))
      return
    }
    guard self.activity.task(on: device.id) == nil else { return }
    if case .blocked(.notShutdown) = confirmation.action.availability(for: device) {
      self.enqueue(confirmation.failedNotice(.deviceRunning))
      return
    }
    // 남은 거절은 기다리는 동안 쓸 수 없게 된 경우뿐이다 (드묾). 행이 이유를 보인다.
    guard self.activity.begin(confirmation.action.task, on: device) else { return }
    defer { self.taskEnded(on: device.id) }
    await self.commandFlow.deleteOrErase(confirmation, device: device, host: self.appHost)
  }

  // MARK: - 앱 설치

  /// 행 "앱 설치" 메뉴의 "파일에서 고르기…" 로 고른 파일.
  func appFileSelected(_ url: URL, for id: AndroidVirtualDevice.ID) async {
    await self.installApp([url], on: id)
  }

  /// 행에 끌어다 놓은 항목. 정확히 하나여야 하고, 둘 이상이면 이유를 알린다. 빈 배열은 무시한다.
  func appDropped(_ urls: [URL], on id: AndroidVirtualDevice.ID) async {
    guard !urls.isEmpty else { return }
    await self.installApp(urls, on: id)
  }

  /// App 이 `AndroidDownloadInstallModel` 의 요청을 넘긴다. 지금 목록으로 대상을 확인하고(없음·막힘이면 알림, 다른 작업 중이면
  /// 행이 진행 중을 보여 알림 없이 끝), Model 이 소유한 Task 로 받은 뒤(행에 진행·취소) 검사·설치·실행한다. 받기 시작과 Task 저장
  /// 사이에 await 를 두지 않는다 (취소가 Task 를 놓치지 않게).
  func downloadInstallRequested(_ request: AndroidDownloadInstallRequest) async {
    let host = self.appHost
    guard let device = self.appFlow.target(request.deviceID, host: host, failed: {
      .installFailed(request.device, .init($0))
    }), self.activity.beginDownload(on: device) else { return }
    let id = device.id
    defer { self.taskEnded(on: id) }
    let download = self.download
    let onProgress: @Sendable (DownloadProgress) async -> Void = { @MainActor progress in
      self.activity.downloadProgressed(progress, on: id)
    }
    let task = Task { await download.downloadResult(request.url, savingAs: .apk, onProgress: onProgress) }
    self.downloadTasks[id] = task
    let result = await task.value
    self.downloadTasks[id] = nil
    let cancelRequested = self.activity.isDownloadCancelRequested(on: id)
    self.activity.downloadEnded(on: id)
    await self.appFlow.installDownloaded(result, cancelRequested: cancelRequested, request: request, host: host)
  }

  /// 행의 받기 취소: 받는 중일 때만 받기를 멈춘다. 받기가 막 끝났어도(늦은 취소) 받은 파일을 지우고 알림 없이 끝난다.
  /// 받기가 끝난 뒤(검사·설치 중)에는 아무 일도 하지 않는다.
  func downloadCancelTapped(_ id: AndroidVirtualDevice.ID) {
    guard self.activity.requestDownloadCancel(on: id) else { return }
    self.downloadTasks[id]?.cancel()
  }

  // MARK: - 앱 실행·링크 열기

  /// App 이 `AndroidAppSheetsModel` 의 "실행" 요청을 넘긴다. 고른 앱을 실행한 뒤 다시 읽는다. 기기는 시트를 연 사이 바뀌었을
  /// 수 있어 지금 목록으로 다시 확인한다 (명령 전 거절은 다시 읽지 않는다).
  func launchAppRequested(_ request: AndroidLaunchAppRequest) async {
    guard let device = self.appFlow.target(request.deviceID, host: self.appHost, failed: {
      .launchFailed(request.device, $0)
    }) else { return }
    // 남은 거절은 같은 기기의 다른 작업뿐이다. 시트가 창을 막아 드물고, 행의 진행 표시가 이유를 보인다.
    guard self.activity.begin(.launchApp, on: device) else { return }
    defer { self.taskEnded(on: device.id) }
    await self.appFlow.launch(request.package, on: device.id, label: request.device, host: self.appHost)
  }

  /// App 이 `AndroidAppSheetsModel` 의 "열기" 요청을 넘긴다. 링크를 연 뒤 다시 읽는다. 기기는 지금 목록으로 다시 확인한다
  /// (명령 전 거절은 다시 읽지 않는다).
  func openURLRequested(_ request: AndroidOpenURLRequest) async {
    guard let device = self.appFlow.target(request.deviceID, host: self.appHost, failed: {
      .openURLFailed(request.device, $0)
    }) else { return }
    guard self.activity.begin(.openURL, on: device) else { return }
    defer { self.taskEnded(on: device.id) }
    await self.appFlow.openURL(request.link, on: device.id, label: request.device, host: self.appHost)
  }

  // MARK: - 알림

  /// id 가 같은 알림만 지운다. 이미 닫았거나 없으면 아무것도 하지 않아, 두 번 불려도 다음 알림을 지우지 않는다.
  func noticeDismissed(_ id: AndroidDevicesNoticeItem.ID) {
    self.noticeQueue.dismiss(id)
  }
}

// 내부 도우미. `private` 이라 같은 파일에 둔다.
extension AndroidDevicesModel {
  // MARK: - 내부

  private func requestConfirmation(_ action: AndroidDeviceConfirmation.Action, for id: AndroidVirtualDevice.ID) {
    guard case let .loaded(list) = self.listState,
          let device = list.device(id: id),
          self.activity.canStart(action.task, on: device),
          !self.hasPresentedSheet
    else { return }
    self.confirmation = AndroidDeviceConfirmation(action: action, deviceID: id, device: AndroidDeviceLabel(device))
  }

  /// 진행 기록은 여기서만 시작하고 끝낸다. 작업 중인 기기는 행이 진행 중을 보여 알리지 않고, 켜짐이 아니거나 쓸 수 없으면
  /// (파일을 고르는 사이 꺼진 경우. 드롭은 View 가 먼저 거절한다) 이유를 알린다. 목록에 없는 기기는 알리지 않는다
  /// (파일을 고르는 사이 지워진 경우뿐이고 라벨을 만들 수 없다. iOS 와 같다).
  private func installApp(_ items: [URL], on id: AndroidVirtualDevice.ID) async {
    guard case let .loaded(list) = self.listState,
          let device = list.device(id: id),
          self.activity.task(on: id) == nil
    else { return }
    let label = AndroidDeviceLabel(device)
    if case let .blocked(reason) = device.appActionAvailability {
      self.enqueue(.installFailed(label, .deviceNotReady(reason)))
      return
    }
    guard self.activity.begin(.installApp, on: device) else { return }
    defer { self.taskEnded(on: id) }
    await self.appFlow.install(items, on: id, label: label, host: self.appHost)
  }

  /// 흐름(기기 명령·앱 작업)이 Model 상태에 닿는 창구. 부를 때마다 만들어 넘기고 흐름 타입은 저장하지 않는다.
  private var appHost: AndroidAppInstallFlow.Host {
    AndroidAppInstallFlow.Host(
      enqueue: { self.enqueue($0) },
      reload: { await self.reload() },
      listState: { self.listState }
    )
  }

  /// 취소(`.cancelled`)는 알리지 않는다. 그 밖의 실패는 늘 쌓고, 새로 고침 실패는 같은 원인이 이미 줄에 있으면 쌓지 않는다.
  private func enqueue(_ notice: AndroidDevicesNotice) {
    if notice.error == .cancelled {
      return
    }
    self.noticeQueue.enqueue(notice)
  }

  /// 함께 켜기의 기기 한 대: 켜고 다시 읽은 뒤 그 행을 푼다 (먼저 켜진 행이 꺼짐으로 남지 않게 다시 읽기가 먼저다).
  private func bootMember(_ device: AndroidVirtualDevice, owner: Int) async -> (
    AndroidVirtualDevice.ID,
    AndroidEmulatorError?
  ) {
    let error = await self.commandFlow.boot(device.id)
    await self.reload()
    self.taskEnded(on: device.id, owner: owner)
    return (device.id, error)
  }

  /// 작업 기록을 지우고, 그 기기가 앱 밖 켜는 중으로 남았으면(켜기 시간 초과 등) 자동 다시 읽기를 시작한다.
  private func taskEnded(on id: AndroidVirtualDevice.ID, owner: Int? = nil) {
    if let owner {
      self.activity.end(on: id, owner: owner)
    } else {
      self.activity.end(on: id)
    }
    self.updateAutoRefresh()
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
        do throws(AndroidEmulatorError) {
          let inventory = try await self.emulator.fetchDevices()
          let list = AndroidDeviceList(devices: inventory.devices)
          self.listState = .loaded(list)
          self.selection.formIntersection(list.deviceIDs)
          self.creationOptions = inventory.creationOptions
        } catch {
          self.loadFailed(error)
        }
      } while self.reloadRequested
      self.isRefreshing = false
      self.loadTask = nil
      self.updateAutoRefresh()
    }
    self.loadTask = task
    await task.value
  }

  /// 목록이 있으면 알림만 쌓고 목록을 유지한다. 목록이 없거나 Android 도구를 찾지 못했으면(목록이 더는 맞지 않는다) 실패 화면.
  private func loadFailed(_ error: AndroidEmulatorError) {
    if case .loaded = self.listState, error != .sdkUnavailable {
      self.enqueue(.refreshFailed(error))
      return
    }
    self.listState = .failed(error)
    self.selection = []
  }

  /// 화면이 보이고, 앱 작업 없이 켜는 중인 기기가 있으면 2초 뒤 다시 읽는다 (이미 기다리는 중이면 그대로). 없으면 멈춘다.
  private func updateAutoRefresh() {
    guard self.isVisible, self.hasBootingDeviceWithoutTask else {
      self.autoRefreshTask?.cancel()
      self.autoRefreshTask = nil
      return
    }
    guard self.autoRefreshTask == nil else { return }
    let sleep = self.sleep
    self.autoRefreshTask = Task {
      do {
        try await sleep(Self.bootingRefreshInterval)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      // 다시 읽기가 끝나면 다음 기다림을 새로 정한다.
      self.autoRefreshTask = nil
      await self.reload()
    }
  }
}
