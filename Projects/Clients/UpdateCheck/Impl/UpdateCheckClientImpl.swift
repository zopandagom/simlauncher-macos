import Core
import DownloadInterface
import Foundation
import UpdateCheckInterface

/// 최신 정식 릴리스의 버전 파일(`releases/latest/download/SimLauncher-version.json`)을 Download Client 의 `fetchData` 로 받아
/// (GitHub 의 리다이렉트를 https 로 따라간다) `version` 을 숫자 버전으로 해석한다.
/// 네트워크 API 를 직접 쓰지 않는다 (lint `network_only_in_download_impl`). 헤더를 따로 넣지 않고 Download Impl 의 기본 요청 그대로다.
public struct UpdateCheckClientImpl: UpdateCheckClient {
  /// 응답 상한 64 KiB. 버전 파일은 약 20 B 다 (실측 2026-11-15). 넘으면 받지 않고 `.unexpectedResponse`.
  static let maxResponseBytes = 65536

  private let repository: ReleaseRepository?
  private let download: any DownloadClient

  /// - Parameters:
  ///   - repository: 빌드 설정의 배포 저장소. nil 이면 이 빌드에 업데이트 기능이 없다 (요청하지 않는다).
  ///   - download: 앱의 다른 받기와 같은 Download Client 인스턴스.
  public init(repository: ReleaseRepository?, download: any DownloadClient) {
    self.repository = repository
    self.download = download
  }

  public var releasePageURL: URL? {
    self.repository?.latestReleasePageURL
  }

  public func latestReleaseVersion() async throws(UpdateCheckError) -> AppVersion? {
    guard let repository = self.repository else {
      throw .notConfigured
    }
    let data: Data
    do throws(DownloadError) {
      data = try await self.download.fetchData(repository.versionFileURL, maxBytes: Self.maxResponseBytes)
    } catch {
      throw UpdateCheckErrorMapping.map(error)
    }
    return try ReleaseVersionFile.version(from: data)
  }
}
