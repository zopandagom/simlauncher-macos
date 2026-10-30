import Core
import DownloadInterface
import Foundation

/// URLSession 데이터 작업으로 받는 `DownloadClient`. 큰 파일은 delegate 가 `SimLauncher-Download-<UUID>/<고정 이름>`
/// (`DownloadedFileName`: `download`·`download.apk`) 에 직접 쓴다 (다운로드 작업은 성공·취소·실패 때 시스템 임시 폴더에
/// 지울 수 없는 파일을 남겨 쓰지 않는다).
/// 호출마다 세션을 새로 만든다: 쿠키·캐시·자격 증명 저장소 없음, 요청 유휴 시간 제한 60초, 연결을 기다리지 않음.
public struct DownloadClientImpl: DownloadClient {
  /// 요청 유휴 시간 제한, `fetchData` 의 전체 시간 제한.
  static let timeout: TimeInterval = 60

  private let temporaryDirectory: URL
  private let availableCapacity: @Sendable (URL) -> Int64?
  private let openSink: @Sendable (URL) throws -> any FileSink
  private let protocolClasses: [AnyClass]
  private let now: @Sendable () -> ContinuousClock.Instant
  private let folders: DownloadFolders

  /// `FileManager.default.temporaryDirectory`, 그 볼륨의 실제 여유, 실제 네트워크, 실제 시계를 쓴다.
  /// App 은 이 Impl 을 하나만 만든다 (지금 쓰는 폴더 목록을 함께 쓴다).
  public init() {
    self.init(temporaryDirectory: FileManager.default.temporaryDirectory)
  }

  /// 테스트용. `temporaryDirectory` 는 기본값이 없다: 테스트가 실수로 실제 임시 폴더를 쓰면, 같은 Mac 에서 켜 둔
  /// SimLauncher 의 받는 중 폴더를 남은 폴더 정리가 지울 수 있다. 여유가 nil 이면 비교를 건너뛴다.
  /// - Parameter protocolClasses: 비어 있지 않으면 세션의 프로토콜 클래스를 이것으로 바꾼다 (테스트의 URLProtocol 스텁).
  init(
    temporaryDirectory: URL,
    availableCapacity: @escaping @Sendable (URL) -> Int64? = Self.volumeAvailableCapacity,
    openSink: @escaping @Sendable (URL) throws -> any FileSink = FileHandleSink.create,
    protocolClasses: [AnyClass] = [],
    now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
  ) {
    self.temporaryDirectory = temporaryDirectory
    self.availableCapacity = availableCapacity
    self.openSink = openSink
    self.protocolClasses = protocolClasses
    self.now = now
    self.folders = DownloadFolders(temporaryDirectory: temporaryDirectory)
  }

  /// 첫 실패에서 멈춘다: 취소 확인 → 임시 폴더 실제 경로 → 이름 등록 → 폴더(0o700) 만들기 → 받기.
  /// 응답 판정·파일 만들기는 delegate 가 응답을 받을 때 한다. 폴더를 만든 뒤의 실패는 폴더를 지운 뒤 던진다.
  /// 성공해도 이름 등록은 `removeDownloaded(_:)` 까지 남겨 남은 폴더 정리가 지우지 않게 한다.
  @concurrent
  public func download(
    _ url: DownloadURL,
    savingAs fileName: DownloadedFileName,
    onProgress: @escaping @Sendable (DownloadProgress) async -> Void
  ) async throws(DownloadError) -> DownloadedFile {
    guard !Task.isCancelled else {
      throw .cancelled
    }
    guard let tmp = RealPath.of(self.temporaryDirectory) else {
      throw .storageUnavailable
    }
    let name = DownloadFolders.newName()
    self.folders.register(name)
    let tmpURL = URL(filePath: tmp, directoryHint: .isDirectory)
    let folder = tmpURL.appending(path: name, directoryHint: .isDirectory)
    do {
      try FileManager.default.createDirectory(
        at: folder,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
    } catch {
      self.folders.unregister(name)
      throw DownloadErrorMapping.writeFailure(error)
    }
    let file = folder.appending(path: fileName.rawValue, directoryHint: .notDirectory)
    let availableCapacity = self.availableCapacity
    do throws(DownloadError) {
      let received = try await self.run(
        url.url,
        target: .file(file),
        availableCapacity: { availableCapacity(tmpURL) },
        resourceTimeout: nil,
        onProgress: onProgress
      )
      return DownloadedFile(file: file, folder: folder, byteCount: received.byteCount, mimeType: received.mimeType)
    } catch {
      self.folders.remove(folder)
      throw error
    }
  }

  @concurrent
  public func fetchData(_ url: DownloadURL, maxBytes: Int) async throws(DownloadError) -> Data {
    let received = try await self.run(
      url.url,
      target: .memory(maxBytes: maxBytes),
      availableCapacity: { nil },
      resourceTimeout: Self.timeout,
      onProgress: { _ in }
    )
    return received.data
  }

  @concurrent
  public func removeDownloaded(_ file: DownloadedFile) async {
    self.folders.remove(file.folder)
  }

  @concurrent
  public func removeLeftoverDownloads() async {
    self.folders.removeLeftovers()
  }

  /// 임시 폴더 볼륨의 여유. 중요 용도 여유가 0 이거나 읽지 못하면 일반 여유 (`DownloadErrorMapping.chooseCapacity`).
  static func volumeAvailableCapacity(_ url: URL) -> Int64? {
    let values = try? url.resourceValues(
      forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
    )
    return DownloadErrorMapping.chooseCapacity(
      important: values?.volumeAvailableCapacityForImportantUsage,
      plain: values?.volumeAvailableCapacity
    )
  }

  /// `download`·`fetchData` 공용. 진행 값은 가장 최근 하나만 버퍼에 두고(`bufferingNewest(1)`), 앞 콜백이 끝난 뒤 다음을 넘긴다.
  /// 취소되면 남은 값은 넘기지 않고, 전송이 끝나기(`didCompleteWithError`)를 취소와 무관하게 기다린 뒤 돌아간다
  /// (취소된 Task 에서는 스트림 반복이 완료보다 먼저 끝나므로, 기다리지 않으면 delegate 가 쓰는 중에 폴더를 지운다).
  private func run(
    _ url: URL,
    target: DownloadTransfer.Target,
    availableCapacity: @escaping @Sendable () -> Int64?,
    resourceTimeout: TimeInterval?,
    onProgress: @escaping @Sendable (DownloadProgress) async -> Void
  ) async throws(DownloadError) -> DownloadTransfer.Received {
    guard !Task.isCancelled else {
      throw .cancelled
    }
    let (stream, continuation) = AsyncStream<DownloadProgress>.makeStream(bufferingPolicy: .bufferingNewest(1))
    let transfer = DownloadTransfer(
      target: target,
      availableCapacity: availableCapacity,
      openSink: self.openSink,
      now: self.now,
      progress: continuation
    )
    let session = URLSession(
      configuration: self.configuration(resourceTimeout: resourceTimeout),
      delegate: transfer,
      delegateQueue: nil
    )
    let request = URLRequest(url: url)
    let result: Result<DownloadTransfer.Received, DownloadError> = await withTaskCancellationHandler {
      guard transfer.start(session, request) else {
        session.invalidateAndCancel()
        return .failure(.cancelled)
      }
      // 시작과 첫 `next()` 사이에 suspend 지점(await)을 두지 않는다. 소비자가 먼저 기다려야 첫 값 (0, 전체) 이
      // 버퍼를 거치지 않고 넘어간다. 사이에 await 가 있으면 `bufferingNewest(1)` 이 첫 값을 덮을 수 있다.
      for await progress in stream {
        guard !Task.isCancelled else {
          break
        }
        await onProgress(progress)
      }
      await transfer.waitForCompletion()
      return transfer.outcome()
    } onCancel: {
      transfer.cancel()
    }
    return try result.get()
  }

  /// 호출마다 새 설정. delegate 큐는 시스템 기본(직렬)이다.
  private func configuration(resourceTimeout: TimeInterval?) -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.timeoutIntervalForRequest = Self.timeout
    configuration.waitsForConnectivity = false
    if let resourceTimeout {
      configuration.timeoutIntervalForResource = resourceTimeout
    }
    if !self.protocolClasses.isEmpty {
      configuration.protocolClasses = self.protocolClasses
    }
    return configuration
  }
}
