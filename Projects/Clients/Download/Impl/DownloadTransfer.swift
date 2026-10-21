import DownloadInterface
import Foundation
import Synchronization

/// 한 번의 받기 상태와 그 데이터 작업의 delegate. 세션마다 하나 만든다.
/// 상태는 둘로 나눈다. `control`(취소·실패·완료)은 `start`·`cancel`(취소 핸들러)·delegate 가 짧게 만지고,
/// `payload`(파일·버퍼·바이트·스로틀)는 직렬 delegate 큐의 콜백만 만진다. 그래서 파일 쓰기가 취소 핸들러를 막지 않는다.
/// 두 lock 을 겹쳐 잡지 않고, `task.cancel()`·`resume()`·continuation 깨우기는 lock 밖에서 한다.
final class DownloadTransfer: NSObject, URLSessionDataDelegate, Sendable {
  enum Target: Sendable {
    /// 이 경로에 새 파일을 만들어 쓴다.
    case file(URL)
    /// 메모리에 모은다. 넘으면 `.tooLarge`.
    case memory(maxBytes: Int)
  }

  /// 성공한 전송의 결과. 파일 대상이면 `data` 는 비어 있다.
  struct Received: Sendable {
    let byteCount: Int64
    let mimeType: String?
    let data: Data
  }

  private struct Control {
    var task: URLSessionDataTask?
    var cancelRequested = false
    /// 첫 실패만 남는다. 그 뒤 오는 -999 완료는 무시된다.
    var failure: DownloadError?
    var finished = false
    var completion: CheckedContinuation<Void, Never>?
  }

  private struct Payload {
    var sink: (any FileSink)?
    var memory = Data()
    var received: Int64 = 0
    var expected: Int64?
    var mimeType: String?
    var throttle = ProgressThrottle()
  }

  private let control = Mutex(Control())
  private let payload = Mutex(Payload())
  private let target: Target
  private let availableCapacity: @Sendable () -> Int64?
  private let openSink: @Sendable (URL) throws -> any FileSink
  private let now: @Sendable () -> ContinuousClock.Instant
  private let progress: AsyncStream<DownloadProgress>.Continuation

  init(
    target: Target,
    availableCapacity: @escaping @Sendable () -> Int64?,
    openSink: @escaping @Sendable (URL) throws -> any FileSink,
    now: @escaping @Sendable () -> ContinuousClock.Instant,
    progress: AsyncStream<DownloadProgress>.Continuation
  ) {
    self.target = target
    self.availableCapacity = availableCapacity
    self.openSink = openSink
    self.now = now
    self.progress = progress
  }

  // MARK: - 호출하는 쪽

  /// 취소가 먼저 왔으면 false (작업을 만들지 않는다). 아니면 데이터 작업을 만들어 저장하고 lock 밖에서 시작한다.
  /// 저장한 뒤 온 `cancel()` 은 시작 전이어도 그 작업을 -999 로 끝낸다.
  func start(_ session: URLSession, _ request: URLRequest) -> Bool {
    let task: URLSessionDataTask? = self.control.withLock { control in
      guard !control.cancelRequested else { return nil }
      let task = session.dataTask(with: request)
      control.task = task
      return task
    }
    guard let task else {
      return false
    }
    task.resume()
    return true
  }

  /// Task 취소 핸들러. 취소 표시를 먼저 세운 뒤 작업을 멈춘다 (그 -999 완료가 늘 이 표시를 보게).
  func cancel() {
    let task = self.control.withLock { control in
      control.cancelRequested = true
      return control.task
    }
    task?.cancel()
  }

  /// `didCompleteWithError` 가 끝날 때까지 기다린다. Task 취소와 무관하다.
  func waitForCompletion() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      // 완료 확인과 continuation 저장을 한 lock 안에서 해야 저장보다 완료가 먼저 와도 놓치지 않는다.
      let finished = self.control.withLock { control in
        guard !control.finished else { return true }
        control.completion = continuation
        return false
      }
      if finished {
        continuation.resume()
      }
    }
  }

  /// 완료 뒤 결과. 호출한 Task 가 취소됐으면 전송 결과와 관계없이 `.cancelled`, 아니면 첫 실패, 없으면 성공.
  func outcome() -> Result<Received, DownloadError> {
    if Task.isCancelled {
      return .failure(.cancelled)
    }
    if let failure = self.control.withLock({ $0.failure }) {
      return .failure(failure)
    }
    return self.payload.withLock { payload in
      .success(Received(byteCount: payload.received, mimeType: payload.mimeType, data: payload.memory))
    }
  }

  // MARK: - URLSessionDataDelegate (직렬 delegate 큐)

  /// https 로만 따라간다. 아니면 요청을 보내지 않고 실패를 먼저 기록한 뒤 작업을 멈춘다
  /// (`nil` 만 주면 리다이렉트 응답이 마지막 응답으로 와 오류 없이 끝난다).
  func urlSession(
    _: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection _: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    guard request.url?.scheme?.lowercased() == "https" else {
      completionHandler(nil)
      self.fail(.insecureRedirect, task: task)
      return
    }
    completionHandler(request)
  }

  /// Negotiate·NTLM 은 세션 단계로 온다.
  func urlSession(
    _: URLSession,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    completionHandler(Self.disposition(for: challenge), nil)
  }

  /// Basic 은 작업 단계로 온다.
  func urlSession(
    _: URLSession,
    task _: URLSessionTask,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    completionHandler(Self.disposition(for: challenge), nil)
  }

  func urlSession(
    _: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
  ) {
    switch self.accept(response) {
    case let .success(first):
      self.progress.yield(first)
      completionHandler(.allow)
    case let .failure(error):
      completionHandler(.cancel)
      self.fail(error, task: dataTask)
    }
  }

  func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    // cancel 뒤에 조각이 오는 것은 측정에서 보지 못했지만 보장되지 않으므로 버린다.
    guard !self.control.withLock({ $0.failure != nil || $0.cancelRequested }) else {
      return
    }
    let now = self.now()
    let step: Result<DownloadProgress?, DownloadError> = self.payload.withLock { payload in
      payload.received += Int64(data.count)
      switch self.target {
      case .file:
        do {
          try payload.sink?.write(data)
        } catch {
          return .failure(DownloadErrorMapping.writeFailure(error))
        }
      case let .memory(maxBytes):
        guard payload.received <= Int64(maxBytes) else {
          return .failure(.tooLarge)
        }
        payload.memory.append(data)
      }
      guard payload.throttle.shouldEmit(received: payload.received, at: now) else {
        return .success(nil)
      }
      return .success(DownloadProgress(receivedBytes: payload.received, expectedBytes: payload.expected))
    }
    switch step {
    case let .success(progress):
      if let progress {
        self.progress.yield(progress)
      }
    case let .failure(error):
      self.fail(error, task: dataTask)
    }
  }

  /// 파일을 닫고 결과를 정한 뒤(`finished`) 마지막 진행 값을 넘긴다. 그래서 진행 콜백이 마지막 값을 받을 때
  /// 결과는 이미 정해져 있다. URLProtocol 처럼 길이를 검사하지 않는 경로를 위해 받은 크기 < Content-Length 도 본다.
  func urlSession(_ session: URLSession, task _: URLSessionTask, didCompleteWithError error: (any Error)?) {
    let (received, expected) = self.payload.withLock { payload in
      payload.sink?.close()
      payload.sink = nil
      return (payload.received, payload.expected)
    }
    let short = error == nil && expected.map { received < $0 } == true
    let (succeeded, completion) = self.control.withLock { control in
      if control.failure == nil {
        if let error {
          control.failure = control.cancelRequested ? .cancelled : DownloadErrorMapping.map(error)
        } else if short {
          control.failure = .connectionLost
        }
      }
      control.finished = true
      let completion = control.completion
      control.completion = nil
      return (control.failure == nil, completion)
    }
    if succeeded, self.payload.withLock({ $0.throttle.shouldEmitFinal(received: received) }) {
      self.progress.yield(DownloadProgress(receivedBytes: received, expectedBytes: expected))
    }
    self.progress.finish()
    completion?.resume()
    session.finishTasksAndInvalidate()
  }

  // MARK: - 판정

  /// 2xx HTTP 응답만 받는다. 파일 대상은 Content-Length 를 여유와 비교한 뒤 파일을 만들고,
  /// 메모리 대상은 Content-Length 를 `maxBytes` 와 비교한다. 받으면 첫 진행 값 (0, 전체).
  private func accept(_ response: URLResponse) -> Result<DownloadProgress, DownloadError> {
    guard let http = response as? HTTPURLResponse else {
      return .failure(.failed)
    }
    guard (200 ..< 300).contains(http.statusCode) else {
      return .failure(.httpStatus(http.statusCode))
    }
    // 청크 전송·압축 전송은 -1.
    let expected: Int64? = response.expectedContentLength >= 0 ? response.expectedContentLength : nil
    var sink: (any FileSink)?
    switch self.target {
    case let .file(file):
      if let expected, let available = self.availableCapacity(), expected > available {
        return .failure(.insufficientDiskSpace)
      }
      do {
        sink = try self.openSink(file)
      } catch {
        return .failure(DownloadErrorMapping.writeFailure(error))
      }
    case let .memory(maxBytes):
      if let expected, expected > Int64(maxBytes) {
        return .failure(.tooLarge)
      }
    }
    let now = self.now()
    self.payload.withLock { payload in
      payload.sink = sink
      payload.expected = expected
      payload.mimeType = response.mimeType
      _ = payload.throttle.start(at: now)
    }
    return .success(DownloadProgress(receivedBytes: 0, expectedBytes: expected))
  }

  /// 첫 실패만 기록하고 작업을 멈춘다.
  private func fail(_ error: DownloadError, task: URLSessionTask) {
    let first = self.control.withLock { control in
      guard control.failure == nil else { return false }
      control.failure = error
      return true
    }
    if first {
      task.cancel()
    }
  }

  private static func disposition(for challenge: URLAuthenticationChallenge) -> URLSession.AuthChallengeDisposition {
    switch ChallengePolicy.answer(forAuthenticationMethod: challenge.protectionSpace.authenticationMethod) {
    case .defaultHandling:
      .performDefaultHandling
    case .reject:
      .rejectProtectionSpace
    }
  }
}
