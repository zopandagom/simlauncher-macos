import AppBundleInterface
import Core
import DownloadInterface
import Foundation

/// 카탈로그 버전 설치의 받기·받은 파일 실패 문구. 사용자가 고칠 주소가 없으므로 빌드 주소·빌드 파일 쪽 원인은 카탈로그를 만든
/// 사람에게 알리도록 안내한다 (빌드가 없거나 접근이 거부되면 다른 버전 고르기도). 빌드 주소와 관계없는 원인(오프라인·프록시 인증·
/// 서버 오류·시간 초과·연결 끊김·디스크·임시 폴더)과 받은 zip 의 그 밖의 풀기 실패(`catalogDownloadedZipMessage(for:)` 의 마지막
/// 분기)는 URL 설치와 같은 문구다. 키는 다른 문구와 같은 `Localizable.xcstrings` 에 있다.
extension LauncherText {
  /// 카탈로그 버전 설치 실패의 본문 (`message(for: AppInstallFailure)` 가 넘기는 카탈로그 출처 케이스만 온다. 복잡도를 나눈다).
  static func catalogInstallMessage(for failure: AppInstallFailure) -> String {
    switch failure {
    case let .catalogDownload(error):
      self.catalogInstallDownloadMessage(for: error)
    case let .catalogDownloadedNotZip(isWebPage):
      self.catalogDownloadedNotZipMessage(isWebPage: isWebPage)
    case let .catalogDownloadedZip(error):
      self.catalogDownloadedZipMessage(for: error)
    case .multipleItems, .bundle, .download, .downloadedNotZip, .downloadedZip, .rejected, .deviceNotReady, .deviceBusy,
         .simulator:
      self.message(for: failure)
    }
  }

  /// 카탈로그 버전의 받기 실패.
  static func catalogInstallDownloadMessage(for error: DownloadError) -> String {
    switch error {
    case .insecureRedirect:
      String(
        localized: """
        서버가 https 가 아닌 주소(http 등)로 넘겨 보내 빌드를 받지 않았습니다. \
        이 버전의 빌드를 https 로 바로 받을 수 있게 해 달라고 카탈로그를 만든 사람에게 알려 주세요.
        """,
        bundle: .module
      )
    case let .httpStatus(code):
      self.catalogInstallHTTPStatusMessage(code)
    case .hostNotFound:
      String(
        localized: """
        빌드 서버 주소를 찾지 못했습니다. 회사 안의 주소라면 사내망(VPN 등)에 연결되어 있는지 확인하고, \
        계속되면 카탈로그를 만든 사람에게 알려 주세요.
        """,
        bundle: .module
      )
    case .cannotConnect:
      String(
        localized: """
        빌드 서버에 연결하지 못했습니다. 회사 안의 주소라면 사내망(VPN 등) 연결과 프록시 설정을 확인하고, \
        계속되면 카탈로그를 만든 사람에게 알려 주세요.
        """,
        bundle: .module
      )
    case .secureConnectionFailed:
      String(
        localized: """
        빌드 서버와 보안 연결(TLS)을 맺지 못했습니다(인증서 문제 등). \
        계속되면 서버 관리자나 카탈로그를 만든 사람에게 알려 주세요.
        """,
        bundle: .module
      )
    case .offline, .timedOut, .connectionLost, .insufficientDiskSpace, .storageUnavailable:
      self.message(for: error)
    case .tooLarge, .failed, .cancelled:
      // `.tooLarge` 는 작은 파일 받기에서만, `.cancelled` 는 취소를 누르지 않았을 때만 알림이 되며 둘 다 나오지 않는다.
      String(localized: "빌드 파일을 받지 못했습니다. 다시 시도하고, 계속되면 카탈로그를 만든 사람에게 알려 주세요.", bundle: .module)
    }
  }

  /// 2xx 가 아닌 HTTP 상태. 407·5xx 는 URL 설치와 같은 문구다.
  private static func catalogInstallHTTPStatusMessage(_ code: Int) -> String {
    switch code {
    case 401, 403:
      // 403 은 권한 없는 저장소(S3 등)의 없는 파일에도 온다. 원인은 둘 다 가능성으로 쓴다.
      String(
        localized: """
        서버가 접근을 거부해 빌드를 받지 못했습니다 (HTTP \(code)). 지워졌거나 로그인이 필요한 빌드일 수 있습니다. \
        다른 버전을 고르거나 카탈로그를 만든 사람에게 알려 주세요.
        """,
        bundle: .module
      )
    case 407, 500 ..< 600:
      self.httpStatusMessage(code)
    case 404, 410:
      String(
        localized: """
        서버에 이 버전의 빌드 파일이 없습니다 (HTTP \(code)). 지워진 빌드일 수 있습니다. \
        다른 버전을 고르거나 카탈로그를 만든 사람에게 알려 주세요.
        """,
        bundle: .module
      )
    default:
      String(
        localized: "서버가 빌드 파일을 주지 않았습니다 (HTTP \(code)). 다시 시도하고, 계속되면 카탈로그를 만든 사람에게 알려 주세요.",
        bundle: .module
      )
    }
  }

  /// 카탈로그 버전에서 받은 내용이 zip 으로 읽히지 않는다.
  static func catalogDownloadedNotZipMessage(isWebPage: Bool) -> String {
    if isWebPage {
      String(
        localized: """
        zip 파일 대신 웹 페이지를 받았습니다. 이 버전의 빌드 주소가 로그인이 필요한 주소이거나 내려받기 페이지일 수 있습니다. \
        카탈로그를 만든 사람에게 알려 주세요.
        """,
        bundle: .module
      )
    } else {
      String(
        localized: "받은 파일이 zip 이 아니거나 손상되었습니다. 다시 시도하고, 계속되면 카탈로그를 만든 사람에게 알려 주세요.",
        bundle: .module
      )
    }
  }

  /// 카탈로그 버전에서 받은 zip 의 풀기 실패. 맨 위 .app 이 없거나 여럿이면 카탈로그 문맥 문구,
  /// zip 으로 읽히지 않으면 받은 내용이 zip 아님과 같은 문구, 그 밖은 URL 설치와 같은 문구다 (주소를 전제하지 않는 문구).
  static func catalogDownloadedZipMessage(for error: AppBundleError) -> String {
    switch error {
    case .zipWithoutApp:
      String(
        localized: """
        받은 zip 맨 위에 .app 이 없습니다. .ipa 이거나 .app 이 폴더 안에 있을 수 있습니다. \
        시뮬레이터용 .app 을 바로 압축한 zip 을 올려 달라고 카탈로그를 만든 사람에게 알려 주세요.
        """,
        bundle: .module
      )
    case .zipWithMultipleApps:
      String(
        localized: "받은 zip 맨 위에 .app 이 여러 개 있습니다. .app 하나만 압축한 zip 을 올려 달라고 카탈로그를 만든 사람에게 알려 주세요.",
        bundle: .module
      )
    case .zipUnreadable:
      // `AppInstallFailure.downloaded` 가 `.catalogDownloadedNotZip` 으로 나누므로 오지 않는다.
      self.catalogDownloadedNotZipMessage(isWebPage: false)
    case .insufficientDiskSpace, .notLocalFile, .fileNotFound, .zipUnsafeEntry, .extractionUnavailable, .ipaFile,
         .notAppBundle, .macOSApp, .invalidBundle:
      self.downloadedZipMessage(for: error)
    }
  }
}
