import Core

/// 여러 기기 동작의 대상 한 대. 누른 시점의 id 와 알림에 보일 라벨. iOS `TargetDevice` 와 같다.
public struct AndroidTargetDevice: Hashable, Sendable {
  public let id: AndroidVirtualDevice.ID
  public let label: AndroidDeviceLabel

  public init(id: AndroidVirtualDevice.ID, label: AndroidDeviceLabel) {
    self.id = id
    self.label = label
  }

  /// 지금 목록의 기기 값으로 만든다.
  public init(_ device: AndroidVirtualDevice) {
    self.init(id: device.id, label: AndroidDeviceLabel(device))
  }
}

/// 여러 기기 설치를 시작할 때 대상마다 지금 목록과 진행 작업으로 판정한 결과 (요청 순서 유지). iOS `InstallStart` 와 같다.
/// Model 이 첫 await 전에 `AndroidDeviceActivity.beginInstall` 로 만들고, 흐름이 기기별 진행과 결과 알림에 쓴다.
struct AndroidInstallStart: Hashable, Sendable {
  /// 시작하지 않은 대상 하나와 이유.
  struct Skip: Hashable, Sendable {
    let target: AndroidTargetDevice
    let failure: AndroidAppInstallFailure
  }

  /// 요청한 대상 (누른 시점의 목록 순서). 1대면 한 기기 흐름과 같은 알림을 쓴다.
  let requested: [AndroidTargetDevice]
  /// 진행 기록을 시작한 기기 (지금 목록의 값, 요청 순서).
  let begun: [AndroidVirtualDevice]
  /// 시작하지 않은 대상과 이유 (요청 순서). 없음·목록 없음 = `.emulator(.deviceNotFound)`,
  /// 켜짐이 아니거나 쓸 수 없음 = `.deviceNotReady(reason)` (꺼진 기기는 켜지 않는다), 다른 작업 중 = `.deviceBusy`.
  let skipped: [Skip]
  /// 이 묶음이 시작한 기록의 소유자 번호 (`AndroidDeviceActivity` 가 매긴다). 끝낼 때 이 번호의 기록만 지운다.
  let owner: Int

  var isSingle: Bool {
    self.requested.count == 1
  }

  /// 공통 단계(받기·검사) 실패 알림. 1대 요청이면 한 기기 흐름과 같은 알림이다.
  func failedNotice(_ failure: AndroidAppInstallFailure) -> AndroidDevicesNotice {
    self.isSingle
      ? .installFailed(self.requested[0].label, failure)
      : .batchInstallFailed(self.requested.map(\.label), failure)
  }

  /// 기기별 결과를 요청 순서로 모은다. 건너뛴 대상은 그 이유로 넣고, 결과가 없는 대상은 뺀다.
  func report(results: [AndroidVirtualDevice.ID: AndroidBatchDeviceResult]) -> AndroidBatchInstallReport {
    let entries = self.requested.compactMap { target -> AndroidBatchInstallReport.Entry? in
      if let skip = self.skipped.first(where: { $0.target == target }) {
        return AndroidBatchInstallReport.Entry(device: target.label, result: .installFailed(skip.failure))
      }
      return results[target.id].map { AndroidBatchInstallReport.Entry(device: target.label, result: $0) }
    }
    return AndroidBatchInstallReport(entries: entries)
  }
}

extension AndroidDeviceActivity {
  /// 대상마다 `AndroidAppTarget.current` 로 판정하고, `.ready` 면 `begin(.installApp)` 한다 (받기면 `.receiving(nil)` 과
  /// 받기 묶음 번호도). 시작한 기기에 새 소유자 번호를 붙이고, 시작한 기기·건너뛴 이유·번호를 돌려준다. 첫 await 전에 부른다.
  mutating func beginInstall(
    on targets: [AndroidTargetDevice],
    in state: AndroidDevicesListState,
    downloading: Bool
  ) -> AndroidInstallStart {
    var candidates: [AndroidVirtualDevice] = []
    var failures: [AndroidVirtualDevice.ID: AndroidAppInstallFailure] = [:]
    for target in targets {
      let current = AndroidAppTarget.current(target.id, in: state)
      if case let .ready(device) = current {
        candidates.append(device)
      } else if let failure = current.failure {
        failures[target.id] = AndroidAppInstallFailure(failure)
      }
    }
    var begun: [AndroidVirtualDevice] = []
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
      failures[target.id].map { AndroidInstallStart.Skip(target: target, failure: $0) }
    }
    let owner = self.own(begun.map(\.id))
    return AndroidInstallStart(requested: targets, begun: begun, skipped: skipped, owner: owner)
  }
}
