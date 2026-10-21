import DownloadInterface

/// 테스트·Example 이 함께 쓰는 진행 값.
public extension DownloadProgress {
  /// 1024 바이트 중 0 → 512 → 1024 (`DownloadedFile.fake(index:)` 의 크기와 같다).
  static let samples: [DownloadProgress] = [
    DownloadProgress(receivedBytes: 0, expectedBytes: 1024),
    DownloadProgress(receivedBytes: 512, expectedBytes: 1024),
    DownloadProgress(receivedBytes: 1024, expectedBytes: 1024),
  ]

  /// 전체 크기를 모르는 받기 (청크 전송).
  static let unknownTotalSamples: [DownloadProgress] = [
    DownloadProgress(receivedBytes: 0, expectedBytes: nil),
    DownloadProgress(receivedBytes: 4096, expectedBytes: nil),
  ]
}
