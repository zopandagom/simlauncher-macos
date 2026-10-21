import Foundation

/// 받은 조각을 쓰는 곳. 테스트가 쓰기 실패를 주입한다.
protocol FileSink: Sendable {
  func write(_ data: Data) throws
  func close()
}

/// 파일 하나에 이어 쓴다.
struct FileHandleSink: FileSink {
  private let handle: FileHandle

  /// 새 파일을 0o600 으로 만든다. 이미 있으면 실패한다 (`O_EXCL`, 링크도 따라가지 않는다).
  /// 실패하면 `open(2)` 의 errno 로 `POSIXError` 를 던진다.
  static func create(_ url: URL) throws -> any FileSink {
    let descriptor = open(url.path(percentEncoded: false), O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return FileHandleSink(handle: FileHandle(fileDescriptor: descriptor, closeOnDealloc: true))
  }

  func write(_ data: Data) throws {
    try self.handle.write(contentsOf: data)
  }

  func close() {
    try? self.handle.close()
  }
}
