import Core
import Observation
import SimulatorInterface

/// 첫 화면의 상태와 로직. iOS 시뮬레이터 기기 목록을 읽고, 기기를 켜고 끄며(켠 뒤 Simulator 앱을 연다),
/// 만들고 지우고 초기화한다.
@MainActor
@Observable
public final class LauncherModel {
  public private(set) var listState: LauncherListState = .loading
  /// 목록을 읽는 중이다 (첫 로딩 포함).
  public private(set) var isRefreshing = false
  /// 켜기·끄기·삭제·초기화가 진행 중인 기기. 같은 기기의 작업은 겹치지 않는다.
  public private(set) var busyDeviceIDs: Set<VirtualDevice.ID> = []
  /// 닫지 않은 알림. 쌓인 순서이고, 화면은 첫 항목을 보인다.
  public private(set) var notices: [LauncherNoticeItem] = []
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

  /// + 버튼을 누를 수 있는지: 목록을 읽었고, 선택지가 있고, 만드는 중이 아니고, 시트가 닫혀 있다.
  public var canCreateDevice: Bool {
    guard case .loaded = self.listState else { return false }
    return !self.creationOptions.isEmpty && !self.isCreating && self.createDraft == nil
  }

  /// 목록을 읽었지만 만들 수 있는 기기 종류가 없어 + 버튼을 쓸 수 없다. 툴바 + 툴팁 문구를 고르고,
  /// 기기가 있으면 목록 위 안내 줄로 이유를 보인다 (목록이 비면 빈 화면 안내가 이유를 보인다).
  /// 만드는 중·시트 열림·읽는 중은 다른 표시가 이유를 보이므로 여기 들지 않는다.
  public var isCreationUnavailable: Bool {
    guard case .loaded = self.listState else { return false }
    return self.creationOptions.isEmpty
  }

  @ObservationIgnored private let simulator: any SimulatorClient
  /// 진행 중인 목록 읽기. Model 이 소유해 View 의 `.task` 가 취소돼도 끝까지 돈다.
  @ObservationIgnored private var loadTask: Task<Void, Never>?
  /// 읽는 동안 들어온 요청. 진행 중인 읽기가 끝나면 한 번 더 읽는다.
  @ObservationIgnored private var reloadRequested = false
  @ObservationIgnored private var nextNoticeID = 0

  public init(simulator: any SimulatorClient) {
    self.simulator = simulator
  }

  public func onAppear() async {
    await self.reload()
  }

  public func refreshButtonTapped() async {
    await self.reload()
  }

  /// 꺼진 기기를 켜고, 성공하면 Simulator 앱을 연 뒤 목록을 다시 읽는다. 실패하면 알림을 띄우고 다시 읽는다.
  public func bootButtonTapped(_ id: VirtualDevice.ID) async {
    guard case let .loaded(list) = self.listState,
          let device = list.device(id: id),
          device.availability == .available,
          device.state == .shutdown,
          !self.busyDeviceIDs.contains(id)
    else { return }
    let label = Self.label(for: device)
    self.busyDeviceIDs.insert(id)
    defer { self.busyDeviceIDs.remove(id) }
    do throws(SimulatorError) {
      try await self.simulator.boot(id)
    } catch {
      self.enqueue(.bootFailed(label, error))
      await self.reload()
      return
    }
    do throws(SimulatorError) {
      try await self.simulator.openSimulatorApp()
    } catch {
      self.enqueue(.openAppFailed(label, error))
    }
    await self.reload()
  }

  /// 켜진 기기를 끄고 목록을 다시 읽는다. 실패하면 알림을 띄우고 다시 읽는다.
  public func shutdownButtonTapped(_ id: VirtualDevice.ID) async {
    guard case let .loaded(list) = self.listState,
          let device = list.device(id: id),
          device.state == .booted,
          !self.busyDeviceIDs.contains(id)
    else { return }
    let label = Self.label(for: device)
    self.busyDeviceIDs.insert(id)
    defer { self.busyDeviceIDs.remove(id) }
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
    self.notices.removeAll { $0.id == id }
  }

  /// 기기 작업 실패는 늘 쌓는다. 새로 고침 실패는 같은 원인이 이미 줄에 있으면 쌓지 않는다.
  private func enqueue(_ notice: LauncherNotice) {
    if case .refreshFailed = notice, self.notices.contains(where: { $0.notice == notice }) {
      return
    }
    self.notices.append(LauncherNoticeItem(id: self.nextNoticeID, notice: notice))
    self.nextNoticeID += 1
  }

  private static func label(for device: VirtualDevice) -> LauncherNotice.Device {
    LauncherNotice.Device(name: device.name, runtimeName: device.runtime.name)
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
      self.enqueue(Self.failed(confirmation, .deviceNotFound))
      return
    }
    guard !self.busyDeviceIDs.contains(device.id) else { return }
    switch Self.availability(of: confirmation.action, for: device) {
    case .allowed:
      break
    case .blocked(.notShutdown):
      self.enqueue(Self.failed(confirmation, .deviceNotShutdown))
      return
    case .blocked(.unavailable):
      // 기다리는 동안 쓸 수 없게 됐다 (드묾). 행이 이유를 보인다.
      return
    }
    self.busyDeviceIDs.insert(device.id)
    defer { self.busyDeviceIDs.remove(device.id) }
    do throws(SimulatorError) {
      switch confirmation.action {
      case .delete: try await self.simulator.delete(device.id)
      case .erase: try await self.simulator.erase(device.id)
      }
    } catch {
      self.enqueue(Self.failed(confirmation, error))
    }
    await self.reload()
  }

  private func requestConfirmation(_ action: DeviceConfirmation.Action, for id: VirtualDevice.ID) {
    guard case let .loaded(list) = self.listState,
          let device = list.device(id: id),
          Self.availability(of: action, for: device) == .allowed,
          !self.busyDeviceIDs.contains(id),
          self.pendingConfirmation == nil
    else { return }
    self.pendingConfirmation = DeviceConfirmation(action: action, deviceID: id, device: Self.label(for: device))
  }

  private static func availability(
    of action: DeviceConfirmation.Action,
    for device: VirtualDevice
  ) -> DeviceActionAvailability {
    switch action {
    case .delete: device.deleteAvailability
    case .erase: device.eraseAvailability
    }
  }

  private static func failed(_ confirmation: DeviceConfirmation, _ error: SimulatorError) -> LauncherNotice {
    switch confirmation.action {
    case .delete: .deleteFailed(confirmation.device, error)
    case .erase: .eraseFailed(confirmation.device, error)
    }
  }
}
