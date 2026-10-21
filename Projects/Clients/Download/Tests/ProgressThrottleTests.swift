import Testing
@testable import DownloadImpl

/// `#expect` 안에서는 mutating 메서드를 부를 수 없어 결과를 배열로 모아 본다.
struct ProgressThrottleTests {
  let start = ContinuousClock.now

  @Test("start 는 늘 true, 0.1초가 지나야 다음 값을 넘긴다")
  func interval() {
    var throttle = ProgressThrottle()

    let results = [
      throttle.start(at: self.start),
      throttle.shouldEmit(received: 100, at: self.start + .milliseconds(50)),
      throttle.shouldEmit(received: 200, at: self.start + .milliseconds(100)),
      throttle.shouldEmit(received: 300, at: self.start + .milliseconds(150)),
      throttle.shouldEmit(received: 400, at: self.start + .milliseconds(250)),
    ]

    #expect(results == [true, false, true, false, true])
  }

  @Test("받은 바이트가 마지막으로 넘긴 값과 같으면 시간이 지나도 넘기지 않는다")
  func sameBytes() {
    var throttle = ProgressThrottle()
    _ = throttle.start(at: self.start)

    let results = [
      throttle.shouldEmit(received: 0, at: self.start + .seconds(1)),
      throttle.shouldEmit(received: 10, at: self.start + .seconds(2)),
      throttle.shouldEmit(received: 10, at: self.start + .seconds(3)),
    ]

    #expect(results == [false, true, false])
  }

  @Test("마지막 값은 마지막으로 넘긴 바이트와 다를 때만 넘긴다")
  func final() {
    var emitted = ProgressThrottle()
    _ = emitted.start(at: self.start)
    _ = emitted.shouldEmit(received: 3000, at: self.start + .seconds(1))
    var pending = ProgressThrottle()
    _ = pending.start(at: self.start)
    _ = pending.shouldEmit(received: 1000, at: self.start + .milliseconds(10))

    let results = [
      emitted.shouldEmitFinal(received: 3000),
      pending.shouldEmitFinal(received: 3000),
      pending.shouldEmitFinal(received: 3000),
    ]

    #expect(results == [false, true, false])
  }

  @Test("빈 본문(start 0 → final 0) 은 마지막 값을 넘기지 않는다")
  func emptyBody() {
    var throttle = ProgressThrottle()
    _ = throttle.start(at: self.start)

    let result = throttle.shouldEmitFinal(received: 0)

    #expect(!result)
  }

  @Test("start 전에는 넘기지 않는다")
  func beforeStart() {
    var throttle = ProgressThrottle()

    let result = throttle.shouldEmit(received: 100, at: self.start)

    #expect(!result)
  }
}
