import Core
import Observation

/// 첫 화면의 상태와 로직. 단방향 MV 의 형태를 보여 주는 시작점이며, 앱에 맞게 바꾸거나 지운다.
@MainActor
@Observable
public final class HomeModel {
  public private(set) var greeting: Greeting

  public init(greeting: Greeting = Greeting(waveCount: 0)) {
    self.greeting = greeting
  }

  // MARK: - Events

  public func waveButtonTapped() {
    self.greeting = self.greeting.waved()
  }
}
