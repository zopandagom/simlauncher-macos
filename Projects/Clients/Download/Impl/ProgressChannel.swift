import DownloadInterface

/// 한 번의 받기의 진행 값 통로. delegate(직렬 큐)가 넣고 `DownloadClientImpl.run` 이 한 번 읽는다.
/// 첫 값(응답의 (0, 전체))은 따로 담아 버리지 않고, 그 뒤 값은 가장 최근 하나만 둔다(`bufferingNewest(1)`).
/// 스트림 하나(`bufferingNewest(1)`)에 모두 넣으면, 소비자가 첫 `next()` 를 부르기 전에 delegate(다른 스레드)가 값을
/// 여럿 넣을 때 첫 값이 덮인다.
struct ProgressChannel: Sendable {
  private let first: AsyncStream<DownloadProgress>
  private let firstInput: AsyncStream<DownloadProgress>.Continuation
  private let rest: AsyncStream<DownloadProgress>
  private let restInput: AsyncStream<DownloadProgress>.Continuation

  init() {
    (self.first, self.firstInput) = AsyncStream.makeStream(bufferingPolicy: .bufferingOldest(1))
    (self.rest, self.restInput) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
  }

  /// 응답을 받았을 때 한 번. 넣고 첫 값 통로를 닫는다.
  func yieldFirst(_ progress: DownloadProgress) {
    self.firstInput.yield(progress)
    self.firstInput.finish()
  }

  /// 받는 중의 값과 성공했을 때 마지막 값. 읽히기 전에 다음 값이 오면 앞 값은 버린다.
  func yield(_ progress: DownloadProgress) {
    self.restInput.yield(progress)
  }

  /// 전송이 끝났을 때. 이미 넣은 값(첫 값, 가장 최근 값)은 그대로 읽힌다.
  func finish() {
    self.firstInput.finish()
    self.restInput.finish()
  }

  /// 첫 값, 그 뒤 값 순서로 `body` 에 넘긴다. 앞 호출이 끝난 뒤 다음을 부르고, Task 가 취소되면 남은 값은 넘기지 않고
  /// 돌아간다. 두 통로가 모두 닫히고 남은 값을 다 넘기면 돌아간다. 한 번만 부른다.
  func forEach(_ body: (DownloadProgress) async -> Void) async {
    for await progress in self.first {
      guard !Task.isCancelled else {
        return
      }
      await body(progress)
    }
    for await progress in self.rest {
      guard !Task.isCancelled else {
        return
      }
      await body(progress)
    }
  }
}
