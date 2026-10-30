import AndroidEmulatorInterface
import AndroidPackageInterface
import Core
import DownloadInterface
import Foundation
import Observation
import WorkspaceInterface

/// Android 기기(AVD) 목록 화면의 상태와 로직. `~/.android/avd` 의 기기(Android Studio 가 만든 것 포함)를 읽고, 켜고 끄며,
/// 만들고 지우고 초기화한다. 목록에서 고른 기기(`selection`)를 함께 켜고, 실패가 있으면 결과를 알림 하나에 모은다.
/// 앱이 켜는 중인 기기는 끄기를 포함한 다른 작업을 막는다 (켜는 중에 끄면 기기가 망가질 수 있다, 실측). 앱 밖에서 켜는 중이거나
/// 켜기 대기가 시간 초과된 기기는 끌 수 있다.
/// 상태는 바깥(잠금 파일·adb)에서 정해지므로, 앱 작업 없이 "켜는 중" 인 기기가 있으면 화면이 보이는 동안 2초마다 다시 읽고
/// (`viewDisappeared()` 면 멈춘다), 앱 활성화 때 다시 읽은 뒤 3초 뒤 한 번 더 읽는다 (창을 닫은 직후 adb 가 아직 켜짐으로 답한 경우).
/// 모든 다시 읽기는 한 경로로 모아, 읽는 중에 온 요청은 지금 읽기가 끝난 뒤 한 번 더 읽는다.
/// 켜진 기기에는 로컬 apk(파일 고르기·드롭)나 URL·카탈로그에서 받은 apk(`AndroidDownloadInstallModel` 의 요청을 App 이 넘긴다.
/// 받기는 Model 이 소유하고 행에 진행·취소)를 설치·실행하고(툴바 "선택한 기기에 앱 설치" 는 고른 기기 중 켜진 기기에 한 번 받고
/// 검사해 동시에 설치하고 결과를 알림 하나에 모은다), 설치한 앱을 골라 실행하고, 링크를 연다 (앱 실행·링크 열기 시트는
/// `AndroidAppSheetsModel` 에 있고, 확정한 요청을 App 이 넘긴다). Client 호출은 흐름 타입이 맡는다: 기기 명령은
/// `AndroidDeviceCommandFlow`, 앱 작업은 `AndroidAppInstallFlow`, 스크린샷·녹화(예약·찍기·녹화·보이기)는 `AndroidScreenCaptureFlow`.
/// 녹화는 Model 이 소유한 Task 로 돌고, 녹화 중인 기기는 끄기·삭제·초기화를 막으며, 다시 읽은 목록에서 없거나 꺼졌으면 멈춘다.
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
  /// 기기별로 찍고 있는 스크린샷. 기기 작업과 겹칠 수 있다 (앱 설치·실행·링크 열기 중에도 찍는다).
  public private(set) var screenshots = AndroidScreenshotActivity()
  /// 기기별 화면 녹화 (시작 중·녹화 중(시작 시각)·저장 중). 기기 작업과 겹칠 수 있다.
  public private(set) var recordings = AndroidRecordingActivity()
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
  /// 목록에서 고른 기기 (⌘·⇧ 클릭). 툴바 "선택한 기기 켜기"·"선택한 기기에 앱 설치" 의 대상이고, 다시 읽은 목록에 없는 기기는 빠진다.
  public private(set) var selection: Set<AndroidVirtualDevice.ID> = []

  @ObservationIgnored private let emulator: any AndroidEmulatorClient
  /// 받기(흐름 둘과 화면을 열 때 남은 받기 폴더 정리). App 이 Launcher 와 같은 인스턴스를 넣는다.
  @ObservationIgnored private let download: any DownloadClient
  /// 기기 명령·앱 작업 흐름. 진행 기록을 시작한 Model 메서드 안에서만 부른다.
  @ObservationIgnored private let commandFlow: AndroidDeviceCommandFlow
  @ObservationIgnored private let appFlow: AndroidAppInstallFlow
  /// 화면 캡처 흐름(예약 → 찍기·녹화 → Finder 에서 보이기). Model 상태에는 `captureHost` 창구로만 닿는다.
  @ObservationIgnored private let captureFlow: AndroidScreenCaptureFlow
  /// 기기별 녹화 작업. Model 이 소유해 중지·기기 꺼짐·앱 종료가 이것을 취소해 멈춘다 (View 의 Task 취소는 전해지지 않는다).
  @ObservationIgnored private var recordingTasks: [AndroidVirtualDevice.ID: Task<Void, Never>] = [:]
  /// 앱 종료를 기다리는 중이다. 새 녹화를 시작하지 않는다 (곧 종료하므로 되돌리지 않는다).
  @ObservationIgnored private var isTerminating = false
  /// 기기별 받기 작업 (받기 묶음의 기기는 같은 Task). Model 이 소유해 받기 취소(`downloadCancelTapped(_:)`)가 이것만 멈춘다.
  /// 결과를 받은 직후, 어느 기기도 풀리기 전에 지운다.
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
    workspace: any WorkspaceClient,
    setupRequested: @escaping @MainActor () -> Void = {},
    appSheetPresented: @escaping @MainActor () -> Bool = { false },
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.emulator = emulator
    self.download = download
    self.commandFlow = AndroidDeviceCommandFlow(emulator: emulator)
    self.appFlow = AndroidAppInstallFlow(emulator: emulator, package: package, download: download)
    self.captureFlow = AndroidScreenCaptureFlow(emulator: emulator, workspace: workspace, now: now)
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
    await self.commandFlow.bootAll(start, host: self.appHost)
  }

  /// 켜는 중(앱 밖에서 켜는 중·시간 초과 포함)이거나 켜진 기기를 끄고 목록을 다시 읽는다. 실패하면 알림을 띄우고 다시 읽는다.
  /// 앱이 켜는 중인 기기는 작업 기록이 막는다. 녹화 중이면 끄지 않는다.
  func shutdownTapped(_ id: AndroidVirtualDevice.ID) async {
    guard case let .loaded(list) = self.listState,
          let device = list.device(id: id),
          !self.recordings.blocks(.shutdown, on: id),
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
    guard self.activity.task(on: device.id) == nil, !self.recordings.blocks(confirmation.action.task, on: device.id)
    else { return }
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

  /// 툴바 "선택한 기기에 앱 설치" > "파일에서 고르기…" 로 고른 파일. 한 대면 행 메뉴와 같은 경로다. 여러 대면 한 번 검사하고
  /// 켜진 기기마다 동시에 설치·실행해 결과를 알림 하나에 모은다 (꺼진·쓸 수 없는·작업 중 기기는 이유와 함께 건너뛴다).
  func selectedAppFileChosen(_ url: URL) async {
    let devices = self.selectedDevices
    if devices.count == 1 {
      return await self.installApp([url], on: devices[0].id)
    }
    let targets = devices.map(AndroidTargetDevice.init)
    let start = self.activity.beginInstall(on: targets, in: self.listState, downloading: false)
    defer { start.begun.forEach { self.taskEnded(on: $0.id, owner: start.owner) } }
    await self.appFlow.install(url, start: start, host: self.appHost)
  }

  /// App 이 `AndroidDownloadInstallModel` 의 요청(행 메뉴면 1대, 툴바면 고른 기기 전부)을 넘긴다. 대상을 지금 목록으로 판정해
  /// 받기 묶음을 시작하고(1대 요청이면 없음·막힘은 알림, 다른 작업 중이면 행이 진행 중을 보여 알림 없이 끝. 여러 대면 결과 알림에
  /// 이유), Model 이 소유한 Task 로 한 번 받은 뒤(대상 행 모두에 진행·취소) 한 번 검사하고 기기별로 설치·실행한다.
  /// 받기 시작과 Task 저장 사이에 await 를 두지 않는다 (취소가 Task 를 놓치지 않게).
  func downloadInstallRequested(_ request: AndroidDownloadInstallRequest) async {
    let start = self.activity.beginInstall(on: request.targets, in: self.listState, downloading: true)
    let ids = start.begun.map(\.id)
    defer { ids.forEach { self.taskEnded(on: $0, owner: start.owner) } }
    guard !ids.isEmpty else { return self.appFlow.reportNotStarted(start, host: self.appHost) }
    let result = await self.appFlow.downloadResult(
      request.url,
      progressed: { self.activity.downloadProgressed($0, on: ids) },
      taskChanged: { task in ids.forEach { self.downloadTasks[$0] = task } }
    )
    let cancelRequested = self.activity.isDownloadCancelRequested(on: ids[0])
    self.activity.downloadEnded(on: ids)
    await self.appFlow.installDownloaded(
      result, cancelRequested: cancelRequested, start: start, origin: request.origin, host: self.appHost
    )
  }

  /// 행의 받기 취소: 받는 중일 때만 받기 묶음 전체를 멈춘다 (묶음의 기기가 같은 Task 를 갖는다). 받기가 막 끝났어도(늦은 취소)
  /// 받은 파일을 지우고 알림 없이 끝난다. 받기가 끝난 뒤(검사·설치 중)에는 아무 일도 하지 않는다.
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

  // MARK: - 스크린샷·녹화

  /// 행의 "스크린샷": 켜진 기기 화면을 사진 폴더의 SimLauncher 폴더에 PNG 로 저장하고 Finder 에서 선택해 보인다.
  /// 같은 기기는 한 번에 하나만 찍고, 같은 기기의 앱 설치·실행·링크 열기·녹화 중에도 찍는다 (켜기·끄기·삭제·초기화 중에는 찍지 않는다).
  func screenshotTapped(_ id: AndroidVirtualDevice.ID) async {
    // `begin` 은 첫 await 전이라 연타해도 두 번째 호출은 여기서 끝난다.
    guard case let .loaded(list) = self.listState,
          let device = list.device(id: id),
          self.screenshots.begin(on: device, during: self.activity.task(on: id))
    else { return }
    defer { self.screenshots.end(on: id) }
    await self.captureFlow.takeScreenshot(of: device, label: AndroidDeviceLabel(device), host: self.captureHost)
  }

  /// 행의 "녹화": 켜진 기기 화면을 동영상 폴더의 SimLauncher 폴더에 녹화한다. 같은 기기의 앱 작업 중에도 한다.
  /// 중지·기기 꺼짐(다시 읽기)·앱 종료로 멈추거나 녹화가 스스로 끝나면 가져와 저장하고 Finder 에서 보이며(실패면 알림), 그때까지
  /// 돌아오지 않는다. 녹화는 Model 이 소유한 Task 로 돌아 View 의 Task 취소는 전해지지 않는다. 앱 종료를 기다리는 중이면 시작하지 않는다.
  func recordTapped(_ id: AndroidVirtualDevice.ID) async {
    // `begin` 과 Task 저장 사이에 await 를 두지 않는다 (연타·중지가 Task 를 놓치지 않게).
    guard !self.isTerminating,
          case let .loaded(list) = self.listState,
          let device = list.device(id: id),
          self.recordings.begin(on: device, during: self.activity.task(on: id))
    else { return }
    let label = AndroidDeviceLabel(device)
    // 기록은 Task 안에서 지워, 같은 Task 를 기다리는 `appTerminationRequested` 가 어느 쪽이 먼저 깨어나든 끝난 기록을 보게 한다.
    let task = Task {
      await self.captureFlow.record(device, label: label, host: self.captureHost)
      self.recordings.end(on: id)
      self.recordingTasks[id] = nil
    }
    self.recordingTasks[id] = task
    await task.value
  }

  /// 행의 "중지": 시작 중·녹화 중이면 녹화 Task 를 취소해 멈춘다 (저장은 `recordTapped` 의 흐름이 이어서 한다).
  /// 이미 저장 중이면 아무 일도 하지 않는다.
  func recordingStopTapped(_ id: AndroidVirtualDevice.ID) {
    guard self.recordings.requestStop(on: id) else { return }
    self.recordingTasks[id]?.cancel()
  }

  /// App 전용(앱 종료 요청): 새 녹화를 더 시작하지 않고, 모든 녹화를 멈춘 뒤 흐름(가져오기·저장·Finder 보이기)이 끝나기를
  /// 기다린다. 이미 저장 중인 녹화도 끝까지 기다린다.
  func appTerminationRequested() async {
    self.isTerminating = true
    for id in self.recordings.requestStopAll() {
      self.recordingTasks[id]?.cancel()
    }
    for task in Array(self.recordingTasks.values) {
      await task.value
    }
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
          !self.recordings.blocks(action.task, on: id),
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
  /// 묶음의 기기별 끝(`finished`)은 `taskEnded` 라 시간 초과로 켜는 중에 남은 기기의 자동 다시 읽기도 시작한다.
  private var appHost: AndroidAppInstallFlow.Host {
    AndroidAppInstallFlow.Host(
      enqueue: { self.enqueue($0) },
      reload: { await self.reload() },
      listState: { self.listState },
      finished: { self.taskEnded(on: $0, owner: $1) }
    )
  }

  /// 캡처 흐름이 Model 상태에 닿는 창구. 부를 때마다 만들어 넘기고 흐름 타입은 저장하지 않는다.
  private var captureHost: AndroidScreenCaptureFlow.Host {
    AndroidScreenCaptureFlow.Host(
      enqueue: { self.enqueue($0) },
      reload: { await self.reload() },
      recordingStarted: { id, date in self.recordings.started(at: date, on: id) },
      recordingStopReason: { self.recordings.stopReason(on: $0) }
    )
  }

  /// 취소(`.cancelled`)는 알리지 않는다. 그 밖의 실패는 늘 쌓고, 새로 고침 실패는 같은 원인이 이미 줄에 있으면 쌓지 않는다.
  private func enqueue(_ notice: AndroidDevicesNotice) {
    if notice.error == .cancelled {
      return
    }
    self.noticeQueue.enqueue(notice)
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
          // 녹화 중인 기기가 목록에 없거나 꺼졌으면 멈춘다 (켜는 중으로 읽힌 것은 멈추지 않는다, `requestStops(shutDownIn:)`).
          for id in self.recordings.requestStops(shutDownIn: list) {
            self.recordingTasks[id]?.cancel()
          }
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
