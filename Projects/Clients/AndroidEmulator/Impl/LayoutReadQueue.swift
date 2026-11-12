import AndroidEmulatorInterface
import Core

/// 기기(AVD)별 레이아웃 읽기 차례. 같은 기기의 `uiautomator dump` 가 겹치면 뒤에 시작한 쪽이 죽으므로(실측) 한 번에 하나만 돌린다.
///
/// 허가 토큰·대기열 없이 "앞 호출의 작업 끝을 이어 붙인다":
/// 0. 이미 취소된 Task 의 호출은 차례에 들지 않고 곧바로 `.cancelled` 다 (`body` 를 실행하지 않는다).
/// 1. `run` 은 actor 안 한 구간에서 앞 호출의 끝(`tails[id]`)을 읽고, 그것을 기다린 뒤 `body` 를 실행할 작업 Task 를 만들어
///    곧바로 `tails[id]` 를 그 작업의 끝으로 바꾼다 (읽기와 바꾸기 사이에 다른 호출이 끼지 않는다).
/// 2. 호출한 쪽은 작업 Task 를 기다리고, 호출한 Task 가 취소되면 작업 Task 도 취소한다. 앞 작업을 기다리는 중에 취소된 작업은 앞 작업이
///    끝난 뒤 `body` 없이 `.cancelled` 로 끝나고, 그 끝을 다음 호출이 이어받는다 (잃어버릴 허가가 없다).
/// 3. 끝나면 `tails[id]` 가 아직 자기 것일 때만 지운다.
/// 기다림의 상한은 앞 작업의 명령 한도 합이다 (취소된 앞 작업은 `runCancellable` 이 곧 멈춘다).
///
/// 작업 Task 는 actor 밖(nonisolated)에서 만들어 actor 격리를 물려받지 않는다. 그래서 `body` 의 덤프 해석 같은 동기 작업이
/// actor 위에서 돌지 않아 다른 기기의 `run` 진입을 막지 않는다.
actor LayoutReadQueue {
  private struct Tail {
    let token: Int
    let wait: @Sendable () async -> Void
  }

  private var tails: [AndroidVirtualDevice.ID: Tail] = [:]
  private var nextToken = 0

  /// 끝나지 않은 차례가 있는 기기 수 (테스트용).
  var pendingDeviceCount: Int {
    self.tails.count
  }

  /// 지금까지 차례에 든 `run` 호출 수 (이미 취소된 호출은 세지 않는다. 테스트용: 차례에 들어간 뒤 취소하려고).
  var runCount: Int {
    self.nextToken
  }

  /// 같은 기기의 앞 호출이 끝난 뒤 `body` 를 실행한다. 호출한 Task 가 취소되면 `body` 도 취소를 받고,
  /// 아직 시작하지 않았으면 `body` 없이 `.cancelled`.
  func run<T: Sendable>(
    _ id: AndroidVirtualDevice.ID,
    _ body: @escaping @Sendable () async throws(AndroidEmulatorError) -> T
  ) async throws(AndroidEmulatorError) -> T {
    // 이미 취소된 호출은 차례에 들지 않는다: 작업 Task 를 먼저 만들면 아래 `onCancel` 이 닿기 전에 앞 작업 없는 작업 Task 가
    // 취소 확인을 지나 `body` 를 실행할 수 있다.
    guard !Task.isCancelled else { throw .cancelled }
    let previous = self.tails[id]?.wait
    let work = Self.startWork(after: previous, body)
    let token = self.nextToken
    self.nextToken += 1
    self.tails[id] = Tail(token: token, wait: { _ = await work.value })
    let result = await withTaskCancellationHandler {
      await work.value
    } onCancel: {
      work.cancel()
    }
    if self.tails[id]?.token == token {
      self.tails[id] = nil
    }
    return try result.get()
  }

  /// actor 격리를 물려받지 않는 작업 Task: 앞 작업 끝 → 취소 확인 → `body`.
  private nonisolated static func startWork<T: Sendable>(
    after previous: (@Sendable () async -> Void)?,
    _ body: @escaping @Sendable () async throws(AndroidEmulatorError) -> T
  ) -> Task<Result<T, AndroidEmulatorError>, Never> {
    Task {
      await previous?()
      guard !Task.isCancelled else { return .failure(.cancelled) }
      do throws(AndroidEmulatorError) {
        return try await .success(body())
      } catch {
        return .failure(error)
      }
    }
  }
}
