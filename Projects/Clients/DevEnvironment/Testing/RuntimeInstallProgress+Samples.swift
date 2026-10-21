import Core

/// 테스트·Example·Preview 가 함께 쓰는 런타임 설치 진행 샘플 (`.preparing` 은 Core 에 있다).
public extension RuntimeInstallProgress {
  /// 설치 단계 (퍼센트·바이트 없음).
  static let installing = RuntimeInstallProgress(
    phase: .installing,
    fractionCompleted: nil,
    completedBytes: nil,
    totalBytes: nil
  )

  /// 내려받기 단계. 값이 없으면 그 숫자를 읽지 못한 경우다.
  static func downloading(
    fraction: Double?,
    completed: Int64? = nil,
    total: Int64? = nil
  ) -> RuntimeInstallProgress {
    RuntimeInstallProgress(
      phase: .downloading,
      fractionCompleted: fraction,
      completedBytes: completed,
      totalBytes: total
    )
  }
}
