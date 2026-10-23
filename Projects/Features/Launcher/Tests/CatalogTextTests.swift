import AppBundleInterface
import Core
import DownloadInterface
import Foundation
import Testing
@testable import LauncherFeature

/// 카탈로그 버전 설치 실패 문구: 케이스마다 어느 문구를 고르는지.
struct CatalogTextTests {
  static let downloadErrors: [DownloadError] = [
    .insecureRedirect, .httpStatus(401), .httpStatus(403), .httpStatus(407), .httpStatus(404), .httpStatus(410),
    .httpStatus(503), .httpStatus(400), .offline, .hostNotFound, .cannotConnect, .timedOut, .connectionLost,
    .secureConnectionFailed, .tooLarge, .insufficientDiskSpace, .storageUnavailable, .failed, .cancelled,
  ]

  static func isKorean(_ text: String) -> Bool {
    text.unicodeScalars.contains { (0xAC00 ... 0xD7A3).contains($0.value) }
  }

  @Test("카탈로그 버전 설치 실패: 빌드 주소·파일 쪽 원인은 카탈로그 문맥 문구이고, 빌드 주소와 관계없는 원인과 그 밖의 받은 zip 풀기 실패는 URL 설치와 같다")
  func catalogInstallMessages() {
    let missing = LauncherText.message(for: AppInstallFailure.catalogDownload(.httpStatus(404)))
    #expect(missing == "서버에 이 버전의 빌드 파일이 없습니다 (HTTP 404). 지워진 빌드일 수 있습니다. 다른 버전을 고르거나 카탈로그를 만든 사람에게 알려 주세요.")
    #expect(missing != LauncherText.message(for: AppInstallFailure.download(.httpStatus(404))))
    #expect(
      LauncherText.message(for: AppInstallFailure.catalogDownloadedNotZip(isWebPage: true))
        != LauncherText.message(for: AppInstallFailure.downloadedNotZip(isWebPage: true))
    )
    #expect(
      LauncherText.message(for: AppInstallFailure.catalogDownloadedZip(.zipWithoutApp))
        != LauncherText.message(for: AppInstallFailure.downloadedZip(.zipWithoutApp))
    )
    let shared: [DownloadError] = [
      .httpStatus(407), .httpStatus(503), .offline, .timedOut, .connectionLost, .insufficientDiskSpace,
      .storageUnavailable,
    ]
    for error in shared {
      #expect(
        LauncherText.message(for: AppInstallFailure.catalogDownload(error))
          == LauncherText.message(for: AppInstallFailure.download(error)),
        "\(error)"
      )
    }
    let general = "빌드 파일을 받지 못했습니다. 다시 시도하고, 계속되면 카탈로그를 만든 사람에게 알려 주세요."
    for error in [DownloadError.failed, .tooLarge, .cancelled] {
      #expect(LauncherText.message(for: AppInstallFailure.catalogDownload(error)) == general, "\(error)")
    }
    for error in Self.downloadErrors {
      let text = LauncherText.message(for: AppInstallFailure.catalogDownload(error))
      #expect(Self.isKorean(text), "\(error)")
      // 입력한 주소가 없으므로 주소를 입력·확인하라고 하지 않는다.
      #expect(!text.contains("주소를 입력"), "\(error)")
    }
    let zipShared: [AppBundleError] = [
      .insufficientDiskSpace, .zipUnsafeEntry, .extractionUnavailable, .ipaFile, .notAppBundle, .macOSApp,
      .invalidBundle, .notLocalFile, .fileNotFound,
    ]
    for error in zipShared {
      #expect(
        LauncherText.message(for: AppInstallFailure.catalogDownloadedZip(error))
          == LauncherText.downloadedZipMessage(for: error),
        "\(error)"
      )
    }
    #expect(
      LauncherText.message(for: AppInstallFailure.catalogDownloadedZip(.zipUnreadable))
        == LauncherText.message(for: AppInstallFailure.catalogDownloadedNotZip(isWebPage: false))
    )
    // 카탈로그 출처가 아닌 케이스가 넘어와도 기존 문구를 돌려준다.
    #expect(LauncherText.catalogInstallMessage(for: .multipleItems) == LauncherText.message(for: .multipleItems))
  }
}
