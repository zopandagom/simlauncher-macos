import ScreenLayoutInterface

/// 키(기기)별 직렬화. iOS 러너의 요청·응답 파일이 기기당 하나라 같은 기기의 요청·스크린샷을 한 번에 하나만 돌린다.
///
/// AndroidEmulator Impl 의 `LayoutReadQueue` 와 같은 "앞 호출의 작업 끝을 이어 붙인다" 규칙이다 (Impl 끼리 import 할 수 없어 따로 둔다):
/// 1. `run` 은 actor 안 한 구간에서 앞 호출의 끝(`tails[key]`)을 읽고, 그것을 기다린 뒤 `body` 를 실행할 작업 Task 를 만들어
///    곧바로 `tails[key]` 를 그 작업의 끝으로 바꾼다.
/// 2. 호출한 쪽은 작업 Task 를 기다리고, 호출한 Task 가 취소되면 작업 Task 도 취소한다. 앞 작업을 기다리는 중에 취소된 작업은 앞 작업이
///    끝난 뒤 `body` 없이 `.cancelled` 로 끝나고, 그 끝을 다음 호출이 이어받는다.
/// 3. 끝나면 `tails[key]` 가 아직 자기 것일 때만 지운다.
/// 작업 Task 는 actor 밖(nonisolated)에서 만들어 actor 격리를 물려받지 않는다.
actor KeyedSerialQueue<Key: Hashable & Sendable> {
  private struct Tail {
    let token: Int
    let wait: @Sendable () async -> Void
  }

  private var tails: [Key: Tail] = [:]
  private var nextToken = 0

  /// 끝나지 않은 차례가 있는 키 수 (테스트용).
  var pendingKeyCount: Int {
    self.tails.count
  }

  /// 지금까지 들어온 `run` 호출 수 (테스트용).
  var runCount: Int {
    self.nextToken
  }

  /// 같은 키의 앞 호출이 끝난 뒤 `body` 를 실행한다. 호출한 Task 가 취소되면 `body` 도 취소를 받고,
  /// 아직 시작하지 않았으면 `body` 없이 `.cancelled`.
  func run<T: Sendable>(
    _ key: Key,
    _ body: @escaping @Sendable () async throws(ScreenLayoutError) -> T
  ) async throws(ScreenLayoutError) -> T {
    let previous = self.tails[key]?.wait
    let work = Self.startWork(after: previous, body)
    let token = self.nextToken
    self.nextToken += 1
    self.tails[key] = Tail(token: token, wait: { _ = await work.value })
    let result = await withTaskCancellationHandler {
      await work.value
    } onCancel: {
      work.cancel()
    }
    if self.tails[key]?.token == token {
      self.tails[key] = nil
    }
    return try result.get()
  }

  /// actor 격리를 물려받지 않는 작업 Task: 앞 작업 끝 → 취소 확인 → `body`.
  private nonisolated static func startWork<T: Sendable>(
    after previous: (@Sendable () async -> Void)?,
    _ body: @escaping @Sendable () async throws(ScreenLayoutError) -> T
  ) -> Task<Result<T, ScreenLayoutError>, Never> {
    Task {
      await previous?()
      guard !Task.isCancelled else { return .failure(.cancelled) }
      do throws(ScreenLayoutError) {
        return try await .success(body())
      } catch {
        return .failure(error)
      }
    }
  }
}
