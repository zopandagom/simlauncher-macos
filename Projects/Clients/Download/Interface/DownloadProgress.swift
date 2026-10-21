import Foundation

/// 받는 중 진행. 받은 바이트는 늘기만 한다.
public struct DownloadProgress: Hashable, Sendable {
  public let receivedBytes: Int64
  /// 응답의 Content-Length. 없거나(청크 전송) 압축 전송이면 nil.
  public let expectedBytes: Int64?

  public init(receivedBytes: Int64, expectedBytes: Int64?) {
    self.receivedBytes = receivedBytes
    self.expectedBytes = expectedBytes
  }
}
