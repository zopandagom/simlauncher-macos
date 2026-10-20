/// 앱을 그 기기에 설치할 수 없는 이유 (Core 판정).
public enum AppInstallProblem: Hashable, Sendable {
  /// `platforms` 가 있는데 iOSSimulator 가 없다 (기기용 빌드, 빈 배열, 다른 플랫폼 등. 원인은 단정하지 않는다).
  /// 키가 없으면(platforms nil) 이 검사를 하지 않는다: simctl 은 이 키가 아니라 실행 파일의 Mach-O 플랫폼으로 판정하므로
  /// 키를 넣지 않는 다른 빌드 도구의 정상 시뮬레이터 빌드를 막지 않고, 기기용 실행 파일은 simctl install 이 거절한다.
  case notSimulatorBuild
  /// 실행 파일에 이 Mac 시뮬레이터가 실행하는 아키텍처(값)가 없다.
  case missingArchitecture(CPUArchitecture)
  /// 기기 런타임 버전 < MinimumOSVersion. 값은 필요한 최소 버전.
  case requiresNewerOS(OSVersion)
}

public extension AppBundleInfo {
  /// 첫 문제 하나: 플랫폼 → 아키텍처 → OS 버전 순서. 없으면 nil. platforms 가 nil 이면 플랫폼은 보지 않는다.
  /// minimumOSVersion 이 nil 이면 OS 는 보지 않는다. runtime.version 과 같으면 통과.
  func installProblem(on runtime: DeviceRuntime, hostArchitecture: CPUArchitecture) -> AppInstallProblem? {
    if let platforms = self.platforms, !platforms.contains(.iOSSimulator) {
      return .notSimulatorBuild
    }
    if !self.architectures.contains(hostArchitecture) {
      return .missingArchitecture(hostArchitecture)
    }
    if let minimum = self.minimumOSVersion, runtime.version < minimum {
      return .requiresNewerOS(minimum)
    }
    return nil
  }
}

/// 행에서 앱 설치를 막는 이유.
public enum AppInstallBlockReason: Hashable, Sendable {
  /// 쓸 수 없는 기기.
  case unavailable
  /// 켜는 중·끄는 중·상태를 모름.
  case stateChanging
}

/// 그 기기에 지금 앱을 설치할 수 있는지.
public enum AppInstallAvailability: Hashable, Sendable {
  case allowed
  case blocked(AppInstallBlockReason)
}

public extension VirtualDevice {
  /// 쓸 수 없으면 blocked(.unavailable) (상태보다 먼저), `.shutdown`·`.booted` 면 allowed(꺼져 있으면 켜고 설치한다),
  /// 그 밖은 blocked(.stateChanging). Model 가드와 View(버튼 비활성·드롭 거절·이유)가 같은 규칙을 쓴다.
  /// 링크 열기도 같은 규칙을 쓴다 (꺼져 있으면 켜고 연다).
  var appInstallAvailability: AppInstallAvailability {
    if self.availability != .available {
      return .blocked(.unavailable)
    }
    switch self.state {
    case .shutdown, .booted: return .allowed
    case .booting, .shuttingDown, .unknown: return .blocked(.stateChanging)
    }
  }
}
