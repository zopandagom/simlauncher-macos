/// Core 에 두는 도메인 값 타입의 예. 부수효과 없는 `Sendable` 값과 순수 규칙만 둔다.
/// 앱에 맞는 타입이 생기면 지운다.
public struct Greeting: Equatable, Sendable {
  public let waveCount: Int

  public init(waveCount: Int) {
    self.waveCount = waveCount
  }

  public var message: String {
    self.waveCount == 0 ? "아직 인사하지 않았어요" : "\(self.waveCount)번 인사했어요"
  }

  public func waved() -> Greeting {
    Greeting(waveCount: self.waveCount + 1)
  }
}
