import Core
import Observation
import SimulatorInterface

/// 기기 목록 화면의 상태.
public enum LauncherListState: Hashable, Sendable {
  /// 목록이 없고 읽는 중이다.
  case loading
  /// 읽은 목록. 다시 읽는 동안에도 마지막 목록을 유지한다.
  case loaded(DeviceList)
  /// 목록을 한 번도 읽지 못했다 (전체 화면 오류).
  case failed(SimulatorError)
}

/// 목록 위에 띄우는 알림. 기기 작업 실패와, 목록이 있을 때의 새로 고침 실패.
public enum LauncherNotice: Hashable, Sendable {
  /// 알림에 보일 기기. 누른 시점의 목록에서 꺼낸 값이라, 실패 뒤 목록에서 사라져도 그대로 보인다.
  public struct Device: Hashable, Sendable {
    /// 기기 이름 (번역하지 않는 사용자 데이터).
    public let name: String
    /// 런타임 이름, 예 "iOS 26.0". OS 마다 같은 이름의 기기가 있어 함께 보인다.
    public let runtimeName: String

    public init(name: String, runtimeName: String) {
      self.name = name
      self.runtimeName = runtimeName
    }
  }

  case refreshFailed(SimulatorError)
  case bootFailed(Device, SimulatorError)
  case shutdownFailed(Device, SimulatorError)
  /// 기기는 켜졌지만 Simulator 앱을 열지 못했다.
  case openAppFailed(Device, SimulatorError)
}

/// 알림 한 건. 같은 내용이라도 쌓일 때마다 새 id 를 받는다 (View 가 다음 알림을 다시 띄우는 기준).
public struct LauncherNoticeItem: Identifiable, Hashable, Sendable {
  public let id: Int
  public let notice: LauncherNotice
}

/// 첫 화면의 상태와 로직. iOS 시뮬레이터 기기 목록을 읽고, 기기를 켜고 끄며, 켠 뒤 Simulator 앱을 연다.
@MainActor
@Observable
public final class LauncherModel {
  public private(set) var listState: LauncherListState = .loading
  /// 목록을 읽는 중이다 (첫 로딩 포함).
  public private(set) var isRefreshing = false
  /// 켜기·끄기가 진행 중인 기기. 같은 기기의 작업은 겹치지 않는다.
  public private(set) var busyDeviceIDs: Set<VirtualDevice.ID> = []
  /// 닫지 않은 알림. 쌓인 순서이고, 화면은 첫 항목을 보인다.
  public private(set) var notices: [LauncherNoticeItem] = []

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
