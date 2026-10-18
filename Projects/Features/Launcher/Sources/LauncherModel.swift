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
  case refreshFailed(SimulatorError)
  case bootFailed(SimulatorError)
  case shutdownFailed(SimulatorError)
  /// 기기는 켜졌지만 Simulator 앱을 열지 못했다.
  case openAppFailed(SimulatorError)
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
  public private(set) var notice: LauncherNotice?

  @ObservationIgnored private let simulator: any SimulatorClient
  /// 진행 중인 목록 읽기. Model 이 소유해 View 의 `.task` 가 취소돼도 끝까지 돈다.
  @ObservationIgnored private var loadTask: Task<Void, Never>?
  /// 읽는 동안 들어온 요청. 진행 중인 읽기가 끝나면 한 번 더 읽는다.
  @ObservationIgnored private var reloadRequested = false

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
    self.busyDeviceIDs.insert(id)
    defer { self.busyDeviceIDs.remove(id) }
    do throws(SimulatorError) {
      try await self.simulator.boot(id)
    } catch {
      self.notice = .bootFailed(error)
      await self.reload()
      return
    }
    do throws(SimulatorError) {
      try await self.simulator.openSimulatorApp()
    } catch {
      self.notice = .openAppFailed(error)
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
    self.busyDeviceIDs.insert(id)
    defer { self.busyDeviceIDs.remove(id) }
    do throws(SimulatorError) {
      try await self.simulator.shutdown(id)
    } catch {
      self.notice = .shutdownFailed(error)
    }
    await self.reload()
  }

  public func noticeDismissed() {
    self.notice = nil
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
            // 이미 보이는 기기 작업 실패 알림을 덮지 않는다.
            if self.notice == nil {
              self.notice = .refreshFailed(error)
            }
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
