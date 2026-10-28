import Core

/// Google Android SDK 저장소 XML 의 주소와, archive 파일 이름을 붙일 그 폴더 주소. 앱이 정한 고정 주소다 (사용자 설정 아님).
struct RepositoryEndpoints: Sendable {
  /// `repository2-3.xml` (platform-tools·emulator).
  let repository: DownloadURL
  let repositoryBase: DownloadURL
  /// `sys-img/google_apis/sys-img2-3.xml` (Google APIs 시스템 이미지).
  let systemImages: DownloadURL
  let systemImagesBase: DownloadURL

  static let google = RepositoryEndpoints(
    repository: Self.url("https://dl.google.com/android/repository/repository2-3.xml"),
    repositoryBase: Self.url("https://dl.google.com/android/repository/"),
    systemImages: Self.url("https://dl.google.com/android/repository/sys-img/google_apis/sys-img2-3.xml"),
    systemImagesBase: Self.url("https://dl.google.com/android/repository/sys-img/google_apis/")
  )

  /// 고정 리터럴이라 실패하지 않는다.
  private static func url(_ raw: String) -> DownloadURL {
    guard let url = DownloadURL(raw) else {
      preconditionFailure("고정 주소가 DownloadURL 규칙에 맞지 않는다: \(raw)")
    }
    return url
  }
}
