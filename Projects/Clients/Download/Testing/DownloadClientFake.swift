import Core
import DownloadInterface
import Foundation
import Synchronization

/// 테스트·Example 용 `DownloadClient`. 호출을 기록하고, 진행·결과·지연·멈춤을 바꿀 수 있다. 네트워크·파일을 쓰지 않는다.
/// `download` 는 설정한 진행을 순서대로 알린 뒤 결과로 끝나고, 결과를 정하지 않았으면 k 번째 호출(1부터)에
/// `.fake(index: k)` 를 돌려준다. 취소 계약은 Impl 과 같다: 시작 전 취소면 기록 뒤 바로, 진행 사이·멈춤 중·결과 전
/// (마지막 진행 콜백 안 포함) 취소면 그때 `.cancelled`, 돌아온 뒤에는 `onProgress` 를 부르지 않는다.
/// 멈춘 받기에 `sendDownloadProgress(_:)` 가 진행을 넘기는 중에 온 취소·재개는 그 콜백이 끝난 뒤 받기를 깨운다.
/// 내부 취소(-999)는 흉내 내지 않는다 (필요하면 결과를 `.failure(.failed)` 로 둔다).
public final class DownloadClientFake: DownloadClient {
  public enum Call: Hashable, Sendable {
    case download(URL)
    case fetchData(URL, maxBytes: Int)
    case removeDownloaded(DownloadedFile)
  }

  /// 멈춘 받기 하나. 진행을 넘기는 중(`deliveries > 0`)에 온 재개·취소는 `pendingWake` 에 두고,
  /// 마지막 넘기기가 끝날 때 깨운다. 깨우면 목록에서 빠지므로 그 받기의 onProgress 를 다시 부르지 않는다.
  private struct SuspendedDownload {
    let continuation: CheckedContinuation<Bool, Never>
    let onProgress: @Sendable (DownloadProgress) async -> Void
    var deliveries = 0
    /// 넘기는 중에 온 첫 깨우기 (재개 true, 취소 false). nil 이면 아직 깨우지 않았다.
    var pendingWake: Bool?
  }

  private struct State {
    var calls: [Call] = []
    var downloadProgress: [DownloadProgress] = DownloadProgress.samples
    var downloadResult: Result<DownloadedFile, DownloadError>?
    var fetchResult: Result<Data, DownloadError> = .success(Data())
    var delay: Duration?
    var downloadCount = 0
    var leftoverCleanupCount = 0
    var downloadsSuspended = false
    /// 멈춘 받기. 재개면 true, 취소면 false 로 깨우고 목록에서 뺀다.
    var suspendedDownloads: [UUID: SuspendedDownload] = [:]
    /// 기다리기 전에 취소가 먼저 온 받기.
    var cancelledWaits: Set<UUID> = []
  }

  private let state = Mutex(State())

  public init() {}

  /// 들어온 호출 순서대로. 멈춘 호출도 들어오는 즉시 기록된다. `removeLeftoverDownloads()` 는 넣지 않는다
  /// (`leftoverCleanupCount` 로 센다).
  public var calls: [Call] {
    self.state.withLock { $0.calls }
  }

  /// `removeLeftoverDownloads()` 가 불린 횟수.
  public var leftoverCleanupCount: Int {
    self.state.withLock { $0.leftoverCleanupCount }
  }

  /// 지금 멈춰 있고 아직 재개·취소를 받지 않은 받기 수. 테스트가 `sendDownloadProgress(_:)` 를 보내기 전에 기다린다.
  public var suspendedDownloadCount: Int {
    self.state.withLock { state in
      var count = 0
      for download in state.suspendedDownloads.values where download.pendingWake == nil {
        count += 1
      }
      return count
    }
  }

  /// 이후 `download` 가 `progress` 를 순서대로 알린 뒤 `result` 로 끝난다. `result` 가 nil 이면 `.fake(index: k)`.
  /// 결과는 끝날 때의 설정을 쓴다.
  public func setDownloadScript(
    progress: [DownloadProgress],
    result: Result<DownloadedFile, DownloadError>?
  ) {
    self.state.withLock { state in
      state.downloadProgress = progress
      state.downloadResult = result
    }
  }

  /// 이후 `fetchData` 결과 (기본은 빈 Data).
  public func setFetchResult(_ result: Result<Data, DownloadError>) {
    self.state.withLock { $0.fetchResult = result }
  }

  /// Example 용. `download` 는 진행 알림 사이와 결과 전에, `fetchData` 는 결과 전에 이만큼 기다린다 (`nil` 이면 바로).
  public func setDelay(_ delay: Duration?) {
    self.state.withLock { $0.delay = delay }
  }

  /// 이후 `download` 가 진행 알림을 모두 보낸 뒤 결과 전에 `resumeDownloads()` 까지 기다린다.
  /// 기다리는 동안 Task 가 취소되면 `.cancelled` 를 던진다 (진행을 넘기는 중이면 그 콜백이 끝난 뒤).
  public func suspendDownloads() {
    self.state.withLock { $0.downloadsSuspended = true }
  }

  /// 멈춘 받기를 모두 재개하고, 이후 호출은 기다리지 않는다. 진행을 넘기는 중인 받기는 그 콜백이 끝난 뒤 재개한다.
  public func resumeDownloads() {
    let ready: [CheckedContinuation<Bool, Never>] = self.state.withLock { state in
      state.downloadsSuspended = false
      var ready: [CheckedContinuation<Bool, Never>] = []
      for id in Array(state.suspendedDownloads.keys) {
        if let continuation = Self.wake(id, with: true, in: &state) {
          ready.append(continuation)
        }
      }
      return ready
    }
    for continuation in ready {
      continuation.resume(returning: true)
    }
  }

  /// 멈춘 받기 중 아직 재개·취소를 받지 않은 받기마다 차례로 그 받기의 `onProgress` 로 `progress` 를 알리고,
  /// 모두 끝난 뒤 돌아온다. 넘기기 직전에 재개·취소된 받기는 건너뛴다. 넘기는 중에 온 재개·취소는 그 콜백이 끝난 뒤
  /// 받기를 깨우므로, 받기가 돌아온 뒤에는 `onProgress` 를 부르지 않는다. 한 번에 하나만 부른다(앞 호출이 끝난 뒤 다음).
  /// 콜백 안에서 같은 받기가 끝나기를 기다리면 교착한다 (Impl 도 `onProgress` 가 끝나야 돌아간다).
  /// 멈춘 받기가 없으면 아무 일도 하지 않는다.
  public func sendDownloadProgress(_ progress: DownloadProgress) async {
    let ids: [UUID] = self.state.withLock { Array($0.suspendedDownloads.keys) }
    for id in ids {
      // 넘기기 직전에 다시 본다: 그사이 재개·취소된 받기는 건너뛴다 (Impl 도 취소 뒤에는 부르지 않는다).
      let onProgress: (@Sendable (DownloadProgress) async -> Void)? = self.state.withLock { state in
        guard var download = state.suspendedDownloads[id], download.pendingWake == nil else {
          return nil
        }
        download.deliveries += 1
        state.suspendedDownloads[id] = download
        return download.onProgress
      }
      guard let onProgress else {
        continue
      }
      await onProgress(progress)
      let ready: (continuation: CheckedContinuation<Bool, Never>, wake: Bool)? = self.state.withLock { state in
        guard var download = state.suspendedDownloads[id] else {
          return nil
        }
        download.deliveries -= 1
        guard download.deliveries == 0, let wake = download.pendingWake else {
          state.suspendedDownloads[id] = download
          return nil
        }
        state.suspendedDownloads[id] = nil
        return (download.continuation, wake)
      }
      if let ready {
        ready.continuation.resume(returning: ready.wake)
      }
    }
  }

  /// 기록 → 취소 확인 → 진행 알림(사이마다 지연·취소 확인) → 멈춤 → 지연 → 취소 확인 → 결과.
  /// k 는 기록할 때 같은 lock 안에서 정하므로, 멈춘 호출을 어떤 순서로 깨워도 먼저 들어온 호출이 `.fake(index: 1)` 이다.
  public func download(
    _ url: DownloadURL,
    onProgress: @escaping @Sendable (DownloadProgress) async -> Void
  ) async throws(DownloadError) -> DownloadedFile {
    let (index, script) = self.state.withLock { state in
      state.calls.append(.download(url.url))
      state.downloadCount += 1
      return (state.downloadCount, state.downloadProgress)
    }
    guard !Task.isCancelled else {
      throw .cancelled
    }
    for (offset, progress) in script.enumerated() {
      if offset > 0 {
        await self.sleepIfNeeded()
      }
      guard !Task.isCancelled else {
        throw .cancelled
      }
      await onProgress(progress)
    }
    guard await self.waitIfDownloadsSuspended(onProgress: onProgress) else {
      throw .cancelled
    }
    await self.sleepIfNeeded()
    guard !Task.isCancelled else {
      throw .cancelled
    }
    let result = self.state.withLock { $0.downloadResult } ?? .success(.fake(index: index))
    return try result.get()
  }

  /// 기록 → 취소 확인 → 지연 → 취소 확인 → 결과.
  public func fetchData(_ url: DownloadURL, maxBytes: Int) async throws(DownloadError) -> Data {
    self.state.withLock { $0.calls.append(.fetchData(url.url, maxBytes: maxBytes)) }
    guard !Task.isCancelled else {
      throw .cancelled
    }
    await self.sleepIfNeeded()
    guard !Task.isCancelled else {
      throw .cancelled
    }
    return try self.state.withLock { $0.fetchResult }.get()
  }

  /// 기록만 한다.
  public func removeDownloaded(_ file: DownloadedFile) async {
    self.state.withLock { $0.calls.append(.removeDownloaded(file)) }
  }

  /// `leftoverCleanupCount` 만 늘린다.
  public func removeLeftoverDownloads() async {
    self.state.withLock { $0.leftoverCleanupCount += 1 }
  }

  private func sleepIfNeeded() async {
    if let delay = self.state.withLock({ $0.delay }) {
      try? await Task.sleep(for: delay)
    }
  }

  /// 멈춤이 아니면 바로 true. 멈춤이면 재개(true)나 Task 취소(false)까지 기다린다.
  /// 기다리는 동안 `onProgress` 를 `sendDownloadProgress(_:)` 가 쓸 수 있게 둔다.
  /// 넘기는 중에 온 재개·취소는 `pendingWake` 에 두고 넘기기가 끝날 때 깨운다.
  private func waitIfDownloadsSuspended(
    onProgress: @escaping @Sendable (DownloadProgress) async -> Void
  ) async -> Bool {
    let id = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
        // 플래그·취소 확인과 continuation 저장을 한 lock 안에서 해야 재개·취소를 놓치지 않는다.
        let immediate: Bool? = self.state.withLock { state in
          if state.cancelledWaits.remove(id) != nil {
            return false
          }
          guard state.downloadsSuspended else {
            return true
          }
          state.suspendedDownloads[id] = SuspendedDownload(continuation: continuation, onProgress: onProgress)
          return nil
        }
        if let immediate {
          continuation.resume(returning: immediate)
        }
      }
    } onCancel: {
      let ready: CheckedContinuation<Bool, Never>? = self.state.withLock { state in
        guard state.suspendedDownloads[id] != nil else {
          if state.downloadsSuspended {
            state.cancelledWaits.insert(id)
          }
          return nil
        }
        return Self.wake(id, with: false, in: &state)
      }
      ready?.resume(returning: false)
    }
  }

  /// lock 안에서만 부른다. 넘기는 중이 아니면 목록에서 빼고 continuation 을 돌려준다 (부르는 쪽이 lock 밖에서 깨운다).
  /// 넘기는 중이면 처음 온 깨우기만 `pendingWake` 에 남긴다.
  private static func wake(
    _ id: UUID,
    with value: Bool,
    in state: inout State
  ) -> CheckedContinuation<Bool, Never>? {
    guard var download = state.suspendedDownloads[id] else {
      return nil
    }
    guard download.deliveries == 0 else {
      if download.pendingWake == nil {
        download.pendingWake = value
        state.suspendedDownloads[id] = download
      }
      return nil
    }
    state.suspendedDownloads[id] = nil
    return download.continuation
  }
}
