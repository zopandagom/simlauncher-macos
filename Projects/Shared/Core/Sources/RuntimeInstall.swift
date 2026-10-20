/// 런타임 설치 진행. 해석하지 못한 출력은 진행을 바꾸지 않는다.
public struct RuntimeInstallProgress: Hashable, Sendable {
  public enum Phase: Hashable, Sendable {
    /// 시작 ~ 첫 퍼센트 전 ("Finding content..."·"Preparing to download...").
    case preparing
    /// 퍼센트가 나온 뒤.
    case downloading
    /// "Installing..."·"Done." 뒤 ~ 종료 (실측 약 1초).
    case installing
  }

  public let phase: Phase
  /// 0...1. downloading 에서 퍼센트를 읽었을 때만.
  public let fractionCompleted: Double?
  /// "(x of y)" 를 읽었을 때만. 바이트 (`kB`·`MB`·`GB` 를 1000 진법으로 본다).
  public let completedBytes: Int64?
  public let totalBytes: Int64?

  public init(phase: Phase, fractionCompleted: Double?, completedBytes: Int64?, totalBytes: Int64?) {
    self.phase = phase
    self.fractionCompleted = fractionCompleted
    self.completedBytes = completedBytes
    self.totalBytes = totalBytes
  }

  /// 시작 직후 (퍼센트·바이트 없음).
  public static let preparing = RuntimeInstallProgress(
    phase: .preparing,
    fractionCompleted: nil,
    completedBytes: nil,
    totalBytes: nil
  )
}

/// 런타임 설치가 성공으로 끝난 방식. 어느 쪽이든 런타임이 바로 Ready 가 아닐 수 있어 호출한 쪽이 다시 조회한다.
public enum RuntimeInstallOutcome: Hashable, Sendable {
  /// exit 0 이고, xcodebuild 가 취소를 알리지 않았으며(`Download was cancelled.` 없음), 내려받기 줄(`Downloading …`)이 나왔다.
  case installed
  /// exit 0 이고 취소 알림이 없으며 내려받기 줄이 없다 (xcodebuild 가 이미 있는 iOS 런타임 목록만 찍었다).
  case alreadyInstalled
}
