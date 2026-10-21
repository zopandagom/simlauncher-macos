/// 진행 값을 넘길지 정한다. 시각은 부르는 쪽이 준다. 연속으로 같은 받은 바이트를 넘기지 않는다.
struct ProgressThrottle: Sendable {
  static let interval: Duration = .milliseconds(100)

  private var lastTime: ContinuousClock.Instant?
  private var lastBytes: Int64 = 0

  /// 응답을 받았을 때. 늘 true (0 바이트), 그 시각을 마지막으로 넘긴 때로 둔다.
  mutating func start(at now: ContinuousClock.Instant) -> Bool {
    self.lastTime = now
    self.lastBytes = 0
    return true
  }

  /// 조각을 받은 뒤. 마지막으로 넘긴 때로부터 `interval` 이상 지났고 받은 바이트가 마지막으로 넘긴 값과 다르면 true
  /// (그 값·시각을 기록). `start(at:)` 전이면 false.
  mutating func shouldEmit(received: Int64, at now: ContinuousClock.Instant) -> Bool {
    guard let lastTime = self.lastTime, now - lastTime >= Self.interval, received != self.lastBytes else {
      return false
    }
    self.lastTime = now
    self.lastBytes = received
    return true
  }

  /// 성공으로 끝났을 때. 마지막으로 넘긴 바이트와 다르면 true.
  mutating func shouldEmitFinal(received: Int64) -> Bool {
    guard received != self.lastBytes else {
      return false
    }
    self.lastBytes = received
    return true
  }
}
