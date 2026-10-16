import Testing
@testable import Core

struct GreetingTests {
  @Test("인사 횟수에 따라 문구가 바뀐다", arguments: [(0, "아직 인사하지 않았어요"), (3, "3번 인사했어요")])
  func message(waveCount: Int, expected: String) {
    #expect(Greeting(waveCount: waveCount).message == expected)
  }

  @Test("인사하면 횟수가 1 늘어난 새 값을 돌려준다")
  func waved() {
    #expect(Greeting(waveCount: 1).waved() == Greeting(waveCount: 2))
  }
}
