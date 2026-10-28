import AndroidEmulatorInterface
import Core
import Foundation
import Observation

/// Android 기기(AVD) 목록 화면의 상태와 로직. `~/.android/avd` 의 기기(Android Studio 가 만든 것 포함)를 읽고, 켜고 끄며,
/// 만들고 지우고 초기화한다. 목록에서 고른 기기(`selection`)를 함께 켜고, 실패가 있으면 결과를 알림 하나에 모은다.
/// 앱이 켜는 중인 기기는 끄기를 포함한 다른 작업을 막는다 (켜는 중에 끄면 기기가 망가질 수 있다, 실측). 앱 밖에서 켜는 중이거나
/// 켜기 대기가 시간 초과된 기기는 끌 수 있다.
/// 상태는 바깥(잠금 파일·adb)에서 정해지므로, 앱 작업 없이 "켜는 중" 인 기기가 있으면 화면이 보이는 동안 2초마다 다시 읽고
/// (`viewDisappeared()` 면 멈춘다), 앱 활성화 때 다시 읽은 뒤 3초 뒤 한 번 더 읽는다 (창을 닫은 직후 adb 가 아직 켜짐으로 답한 경우).
/// 모든 다시 읽기는 한 경로로 모아, 읽는 중에 온 요청은 지금 읽기가 끝난 뒤 한 번 더 읽는다.
/// Android 도구(SDK) 상태 확인·설치는 여기서 하지 않고, "Android 도구" 버튼으로 App 에 도구 화면을 요청한다.
/// 상태를 바꾸지 않는 읽기 API(`canCreateDevice` 등)는 `AndroidDevicesModel+Reading.swift` 에 있다.
@MainActor
@Observable
public final class AndroidDevicesModel {
  public private(set) var listState: AndroidDevicesListState = .loading
  /// 목록을 읽는 중이다 (첫 로딩 포함).
  public private(set) var isRefreshing = false
  /// 기기별 진행 작업(켜기·끄기·삭제·초기화). 같은 기기의 작업은 겹치지 않는다.
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
    setupRequested: @escaping @MainActor () -> Void = {},
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.emulator = emulator
    self.setupRequested = setupRequested
    self.sleep = sleep
  }

  // MARK: - 화면·다시 읽기

  /// 목록을 읽는다. Android 도구 화면에서 돌아올 때마다 새로 만들어진 View 가 부른다.
  public func onAppear() async {
    self.isVisible = true
    await self.reload()
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
    await self.bootAndReport(device)
  }

  /// 툴바 "선택한 기기 켜기": 고른 기기 중 켤 수 있는 기기를 동시에 켠다 (켜져 있거나 작업 중·쓸 수 없는 기기는 알리지 않고
  /// 건너뛴다). 한 대면 행 "켜기" 와 같다. 여러 대면 먼저 끝난 기기부터 다시 읽고 풀며, 실패가 있으면 결과 알림 하나.
  func bootSelectedTapped() async {
    let start = self.activity.beginAll(.boot, on: self.selectedDevices)
    guard start.begun.count > 1 else {
      guard let device = start.begun.first else { return }
      defer { self.taskEnded(on: device.id, owner: start.owner) }
      return await self.bootAndReport(device)
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
    do throws(AndroidEmulatorError) {
      try await self.emulator.shutdown(id)
    } catch {
      self.enqueue(.shutdownFailed(AndroidDeviceLabel(device), error))
    }
    await self.reload()
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
    do throws(AndroidEmulatorError) {
      let id = try await self.emulator.create(displayName: name, image: draft.image, profile: draft.profile)
      // 다시 읽은 목록에 있으면 남는다 (`reload` 가 목록에 없는 선택을 뺀다).
      self.selection = [id]
    } catch {
      self.enqueue(.createFailed(AndroidDeviceLabel(name: name, apiLabel: draft.image.apiLabel), error))
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
    do throws(AndroidEmulatorError) {
      switch confirmation.action {
      case .delete:
        if case let .folderKept(folder) = try await self.emulator.delete(device.id) {
          self.enqueue(.folderKept(confirmation.device, folder))
        }
      case .erase:
        try await self.emulator.erase(device.id)
      }
    } catch {
      self.enqueue(confirmation.failedNotice(error))
    }
    await self.reload()
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
          self.confirmation == nil,
          self.creationDraft == nil
    else { return }
    self.confirmation = AndroidDeviceConfirmation(action: action, deviceID: id, device: AndroidDeviceLabel(device))
  }

  /// 취소(`.cancelled`)는 알리지 않는다. 그 밖의 실패는 늘 쌓고, 새로 고침 실패는 같은 원인이 이미 줄에 있으면 쌓지 않는다.
  private func enqueue(_ notice: AndroidDevicesNotice) {
    if notice.error == .cancelled {
      return
    }
    self.noticeQueue.enqueue(notice)
  }

  /// 켜고, 실패하면 알림을 쌓은 뒤, 결과와 관계없이 다시 읽는다 (행 켜기·한 대 함께 켜기).
  private func bootAndReport(_ device: AndroidVirtualDevice) async {
    if let error = await self.boot(device.id) {
      self.enqueue(.bootFailed(AndroidDeviceLabel(device), error))
    }
    await self.reload()
  }

  /// 함께 켜기의 기기 한 대: 켜고 다시 읽은 뒤 그 행을 푼다 (먼저 켜진 행이 꺼짐으로 남지 않게 다시 읽기가 먼저다).
  private func bootMember(_ device: AndroidVirtualDevice, owner: Int) async -> (
    AndroidVirtualDevice.ID,
    AndroidEmulatorError?
  ) {
    let error = await self.boot(device.id)
    await self.reload()
    self.taskEnded(on: device.id, owner: owner)
    return (device.id, error)
  }

  private func boot(_ id: AndroidVirtualDevice.ID) async -> AndroidEmulatorError? {
    do throws(AndroidEmulatorError) {
      try await self.emulator.boot(id)
      return nil
    } catch {
      return error
    }
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

  private var hasBootingDeviceWithoutTask: Bool {
    guard case let .loaded(list) = self.listState else { return false }
    return list.devices.contains { $0.state == .booting && self.activity.task(on: $0.id) == nil }
  }
}

private extension AndroidDevicesNotice {
  /// 알림에 담긴 에러 (정보 알림·함께 켜기 결과는 nil).
  var error: AndroidEmulatorError? {
    switch self {
    case let .refreshFailed(error), let .bootFailed(_, error), let .shutdownFailed(_, error),
         let .createFailed(_, error), let .deleteFailed(_, error), let .eraseFailed(_, error):
      error
    case .folderKept, .batchBootFinished:
      nil
    }
  }
}
