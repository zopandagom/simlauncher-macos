import Core
import SimulatorInterface

/// 여러 기기 설치·켜기를 시작할 때 대상마다 지금 목록과 진행 작업으로 판정한 결과 (요청 순서 유지).
/// Model 이 첫 await 전에 `DeviceActivity.beginInstall`·`beginAll` 로 만들고, 흐름이 기기별 진행과 결과 알림에 쓴다.
struct InstallStart: Hashable, Sendable {
  /// 시작하지 않은 대상 하나와 이유.
  struct Skip: Hashable, Sendable {
    let target: TargetDevice
    let failure: AppInstallFailure
  }

  /// 요청한 대상 (누른 시점의 목록 순서). 1대면 한 기기 흐름과 같은 알림을 쓴다.
  let requested: [TargetDevice]
  /// 진행 기록을 시작한 기기 (지금 목록의 값, 요청 순서).
  let begun: [VirtualDevice]
  /// 시작하지 않은 대상과 이유 (요청 순서). 없음·목록 없음 = `.simulator(.deviceNotFound)`,
  /// 설치할 수 없는 상태 = `.deviceNotReady(reason)`, 다른 작업 중 = `.deviceBusy`.
  let skipped: [Skip]
  /// 이 묶음이 시작한 기록의 소유자 번호 (`DeviceActivity` 가 매긴다). 끝낼 때 이 번호의 기록만 지운다.
  let owner: Int

  var isSingle: Bool {
    self.requested.count == 1
  }

  /// 공통 단계(받기·풀기·검사) 실패 알림. 1대 요청이면 한 기기 흐름과 같은 알림이다.
  func failedNotice(_ failure: AppInstallFailure) -> LauncherNotice {
    self.isSingle
      ? .installFailed(self.requested[0].label, failure)
      : .batchInstallFailed(self.requested.map(\.label), failure)
  }

  /// 기기별 결과를 요청 순서로 모은다. 건너뛴 대상은 그 이유로 넣고, 결과도 건너뜀도 없는 대상(켜기에서 할 일이 없던 기기)은 뺀다.
  func report(
    _ action: BatchReport.Action,
    results: [VirtualDevice.ID: BatchDeviceResult],
    simulatorAppError: SimulatorError?
  ) -> BatchReport {
    let entries = self.requested.compactMap { target -> BatchReport.Entry? in
      if let skip = self.skipped.first(where: { $0.target == target }) {
        return BatchReport.Entry(device: target.label, result: .installFailed(skip.failure))
      }
      return results[target.id].map { BatchReport.Entry(device: target.label, result: $0) }
    }
    return BatchReport(action: action, entries: entries, simulatorAppError: simulatorAppError)
  }
}

extension DeviceActivity {
  /// 대상마다 `AppInstallTarget.current` 로 판정하고, `.ready` 면 `begin(.installApp)` 한다 (받기면 `.receiving(nil)` 과
  /// 받기 묶음 번호도). 시작한 기기에 새 소유자 번호를 붙이고, 시작한 기기·건너뛴 이유·번호를 돌려준다. 첫 await 전에 부른다.
  mutating func beginInstall(
    on targets: [TargetDevice],
    in state: LauncherListState,
    downloading: Bool
  ) -> InstallStart {
    var candidates: [VirtualDevice] = []
    var failures: [VirtualDevice.ID: AppInstallFailure] = [:]
    for target in targets {
      let current = AppInstallTarget.current(target.id, in: state)
      if case let .ready(device) = current {
        candidates.append(device)
      } else {
        failures[target.id] = current.installFailure
      }
    }
    var begun: [VirtualDevice] = []
    if downloading {
      begun = self.beginDownload(on: candidates)
    } else {
      for device in candidates where self.begin(.installApp, on: device) {
        begun.append(device)
      }
    }
    let begunIDs = Set(begun.map(\.id))
    for device in candidates where !begunIDs.contains(device.id) {
      failures[device.id] = .deviceBusy
    }
    let skipped = targets.compactMap { target in
      failures[target.id].map { InstallStart.Skip(target: target, failure: $0) }
    }
    let owner = self.own(begun.map(\.id))
    return InstallStart(requested: targets, begun: begun, skipped: skipped, owner: owner)
  }

  /// `canStart(task, on:)` 가 true 인 기기만 시작하고 소유자 번호를 붙인다 (켜기 묶음용. 켜져 있거나 다른 작업 중인 기기는
  /// 알리지 않으므로 `skipped` 는 비운다).
  mutating func beginAll(_ task: DeviceTask, on devices: [VirtualDevice]) -> InstallStart {
    var begun: [VirtualDevice] = []
    for device in devices where self.begin(task, on: device) {
      begun.append(device)
    }
    let owner = self.own(begun.map(\.id))
    return InstallStart(requested: devices.map(TargetDevice.init), begun: begun, skipped: [], owner: owner)
  }
}
