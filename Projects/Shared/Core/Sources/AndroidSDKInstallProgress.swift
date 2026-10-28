/// Android 패키지 설치 진행. 패키지마다 받기 → 확인 → 풀기 → 마무리 순서로 알린다.
public struct AndroidSDKInstallProgress: Hashable, Sendable {
  public enum Phase: Hashable, Sendable {
    /// 받는 중. `expected` 는 계획의 archive 크기.
    case downloading(received: Int64, expected: Int64)
    /// 크기·체크섬 확인.
    case verifying
    /// zipinfo 검사와 unzip 풀기.
    case extracting
    /// 최종 경로로 이름 바꾸기와 스테이징 지우기. 취소를 받지 않는다.
    case finishing
  }

  /// 지금 패키지의 번호 (1부터). 건너뛴 패키지도 번호를 쓴다.
  public let packageIndex: Int
  /// 계획의 패키지 수.
  public let packageCount: Int
  public let component: AndroidSDKComponent
  public let phase: Phase
  /// 받기를 마친 패키지의 크기 합 + 지금 받는 패키지의 받은 바이트 (확인·풀기·마무리 단계면 그 패키지의 크기를 더한 값).
  /// 마지막 패키지의 받기가 끝나면 `totalBytes` 와 같다.
  public let completedBytes: Int64
  /// 이번 설치가 받을 패키지(시작 때 최종 경로가 이미 있어 건너뛴 패키지 제외)의 archive 크기 합.
  /// 건너뛸 때마다 그 크기를 빼고 다시 알린다.
  public let totalBytes: Int64

  public init(
    packageIndex: Int,
    packageCount: Int,
    component: AndroidSDKComponent,
    phase: Phase,
    completedBytes: Int64,
    totalBytes: Int64
  ) {
    self.packageIndex = packageIndex
    self.packageCount = packageCount
    self.component = component
    self.phase = phase
    self.completedBytes = completedBytes
    self.totalBytes = totalBytes
  }

  /// 마무리 단계가 아니면 취소할 수 있다.
  public var canCancel: Bool {
    self.phase != .finishing
  }
}

/// 설치 결과. 둘 다 계획 순서.
public struct AndroidSDKInstallOutcome: Hashable, Sendable {
  /// 이번에 설치한 구성 요소.
  public let installed: [AndroidSDKComponent]
  /// 시작 직전에 최종 경로에 무엇이든 있어 건너뛴 구성 요소 (Android Studio 가 그사이 설치했을 수 있다).
  public let alreadyPresent: [AndroidSDKComponent]

  public init(installed: [AndroidSDKComponent], alreadyPresent: [AndroidSDKComponent]) {
    self.installed = installed
    self.alreadyPresent = alreadyPresent
  }
}
