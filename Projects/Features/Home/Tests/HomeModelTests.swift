import Core
import Testing
@testable import HomeFeature

@MainActor
struct HomeModelTests {
  @Test("인사 버튼을 누르면 인사 횟수가 늘어난다")
  func waveButtonTappedIncrementsCount() {
    let model = HomeModel()

    model.waveButtonTapped()
    model.waveButtonTapped()

    #expect(model.greeting == Greeting(waveCount: 2))
  }
}
