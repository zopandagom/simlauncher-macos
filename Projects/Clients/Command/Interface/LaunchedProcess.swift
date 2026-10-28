import Foundation

/// `launch` 가 띄운 프로세스. 이 앱 프로세스 안에서만 뜻이 있다 (앱을 다시 켜면 없다).
public struct LaunchedProcess: Hashable, Sendable {
  /// Impl 표의 키. pid 는 노출하지 않는다 (신호를 Command Impl 밖에서 보내지 못하게).
  public let id: UUID

  public init(id: UUID) {
    self.id = id
  }
}
