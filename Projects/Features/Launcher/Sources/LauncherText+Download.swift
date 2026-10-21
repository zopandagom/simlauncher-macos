import AppBundleInterface
import Core
import DownloadInterface
import Foundation

/// URL 에서 설치 문구 (메뉴 항목·시트·행의 받기 표시·받기와 받은 파일의 실패). 키는 다른 문구와 같은
/// `Localizable.xcstrings` 에 있다.
extension LauncherText {
  // MARK: - 기기 행

  static var installFromFileMenuItem: String {
    String(localized: "파일에서 고르기…", bundle: .module)
  }

  static var installFromURLMenuItem: String {
    String(localized: "URL 에서…", bundle: .module)
  }

  /// 받는 중 상태 글자. 전체 크기를 알면(0 보다 크면) 받은 크기와 함께 보인다 (행의 막대와 같은 규칙).
  static func downloadingLabel(_ progress: DownloadProgress?) -> String {
    guard let progress else {
      return String(localized: "받는 중…", bundle: .module)
    }
    let received = progress.receivedBytes.formatted(.byteCount(style: .file))
    guard let expected = progress.expectedBytes, expected > 0 else {
      return String(localized: "받는 중… \(received)", bundle: .module)
    }
    let total = expected.formatted(.byteCount(style: .file))
    return String(localized: "받는 중… \(received) / \(total)", bundle: .module)
  }

  static var cancellingDownloadLabel: String {
    String(localized: "취소하는 중…", bundle: .module)
  }

  static var cancelDownloadAccessibilityLabel: String {
    String(localized: "받기 취소", bundle: .module)
  }

  static var cancelDownloadHelp: String {
    String(localized: "받기를 멈추고 받은 부분을 지웁니다", bundle: .module)
  }

  // MARK: - 시트

  static func installURLSheetTitle(for device: LauncherNotice.Device) -> String {
    String(localized: "“\(device.name)” (\(device.runtimeName)) 기기에 URL 에서 앱 설치", bundle: .module)
  }

  static var downloadURLField: String {
    String(localized: "주소", bundle: .module)
  }

  static var downloadURLPrompt: String {
    String(localized: "예: https://example.com/MyApp.zip", bundle: .module)
  }

  static var downloadURLGuide: String {
    String(
      localized: "시뮬레이터용 .app 을 압축한 zip 파일의 https 주소를 입력하세요. 로그인이 필요한 주소에서는 받을 수 없습니다.",
      bundle: .module
    )
  }

  static var installURLConfirmButton: String {
    String(localized: "받아서 설치", bundle: .module)
  }

  /// 입력란 아래 안내. 비어 있으면 문구 없이 버튼만 비활성이다 (nil).
  static func downloadURLProblem(_ problem: DownloadURLProblem) -> String? {
    switch problem {
    case .empty:
      nil
    case .malformed:
      String(localized: "주소로 읽을 수 없습니다. 공백이나 쓸 수 없는 문자가 섞이지 않았는지 확인하세요.", bundle: .module)
    case .notHTTPS:
      String(localized: "https:// 로 시작하는 주소만 받을 수 있습니다.", bundle: .module)
    case .missingHost:
      String(localized: "https:// 뒤에 서버 주소(예: example.com)를 입력하세요.", bundle: .module)
    case .hasCredentials:
      String(
        localized: "사용자 이름이나 비밀번호가 든 주소는 쓸 수 없습니다. 로그인 없이 받을 수 있는 주소를 입력하세요.",
        bundle: .module
      )
    }
  }

  // MARK: - 알림

  /// 받기 실패의 본문. 케이스마다 원인과 다음 할 일.
  static func message(for error: DownloadError) -> String {
    switch error {
    case .insecureRedirect:
      String(
        localized: """
        서버가 안전하지 않은 주소(http)로 넘겨 보내 받지 않았습니다. \
        https 로 바로 받을 수 있는 주소인지 빌드를 올린 사람에게 확인하세요.
        """,
        bundle: .module
      )
    case let .httpStatus(code):
      self.httpStatusMessage(code)
    case .offline, .hostNotFound, .cannotConnect, .timedOut, .connectionLost, .secureConnectionFailed:
      self.connectionMessage(for: error)
    case .insufficientDiskSpace:
      String(localized: "Mac 의 저장 공간이 부족해 받지 못했습니다. 공간을 확보한 뒤 다시 시도하세요.", bundle: .module)
    case .storageUnavailable:
      String(
        localized: "받은 파일을 둘 임시 폴더를 준비하지 못했습니다. 잠시 뒤 다시 시도하고, 계속되면 Mac 을 다시 시작해 보세요.",
        bundle: .module
      )
    case .tooLarge, .failed, .cancelled:
      // `.tooLarge` 는 작은 파일 받기에서만, `.cancelled` 는 취소를 누르지 않았을 때만 알림이 되며 둘 다 나오지 않는다.
      self.downloadFailed
    }
  }

  /// 연결·전송 실패의 본문 (`message(for:)` 가 넘기는 케이스만 온다. 복잡도를 나눈다).
  private static func connectionMessage(for error: DownloadError) -> String {
    switch error {
    case .offline:
      String(localized: "인터넷에 연결되어 있지 않습니다. 연결을 확인한 뒤 다시 시도하세요.", bundle: .module)
    case .hostNotFound:
      String(
        localized: "서버 주소를 찾지 못했습니다. 주소의 철자를 확인하고, 회사 안의 주소라면 사내망(VPN 등)에 연결되어 있는지 확인하세요.",
        bundle: .module
      )
    case .cannotConnect:
      String(
        localized: "서버에 연결하지 못했습니다. 주소를 확인하고, 회사 안의 주소라면 사내망(VPN 등) 연결과 프록시 설정을 확인하세요.",
        bundle: .module
      )
    case .timedOut:
      String(localized: "서버가 오래 응답하지 않아 멈췄습니다. 연결을 확인한 뒤 다시 시도하세요.", bundle: .module)
    case .connectionLost:
      String(localized: "받는 중 연결이 끊겨 받은 부분을 지웠습니다. 다시 시도하세요.", bundle: .module)
    case .secureConnectionFailed:
      String(
        localized: "서버의 보안 인증서를 확인하지 못해 받지 않았습니다. 주소가 맞는지 확인하고, 계속되면 서버 관리자에게 알려 주세요.",
        bundle: .module
      )
    case .insecureRedirect, .httpStatus, .insufficientDiskSpace, .storageUnavailable, .tooLarge, .failed, .cancelled:
      self.downloadFailed
    }
  }

  private static var downloadFailed: String {
    String(localized: "파일을 받지 못했습니다. 주소를 확인한 뒤 다시 시도하세요.", bundle: .module)
  }

  /// 2xx 가 아닌 HTTP 상태. 407 은 숫자를 넣은 고정 문구다.
  static func httpStatusMessage(_ code: Int) -> String {
    switch code {
    case 401, 403:
      String(
        localized: "서버가 로그인이나 접근 권한을 요구해 받지 못했습니다 (HTTP \(code)). 로그인 없이 받을 수 있는 주소인지 확인하세요.",
        bundle: .module
      )
    case 407:
      String(
        localized: "이 Mac 이 쓰는 프록시가 인증을 요구해 받지 못했습니다 (HTTP 407). 회사 네트워크라면 관리자에게 프록시 설정을 문의하세요.",
        bundle: .module
      )
    case 404, 410:
      String(
        localized: "서버에 파일이 없습니다 (HTTP \(code)). 주소가 맞는지, 파일이 지워지지 않았는지 확인하세요.",
        bundle: .module
      )
    case 500 ..< 600:
      String(localized: "서버 오류로 받지 못했습니다 (HTTP \(code)). 잠시 뒤 다시 시도하세요.", bundle: .module)
    default:
      String(localized: "서버가 파일을 주지 않았습니다 (HTTP \(code)). 주소를 확인한 뒤 다시 시도하세요.", bundle: .module)
    }
  }

  /// 받은 내용이 zip 으로 읽히지 않는다. 웹 페이지면 로그인 페이지일 수 있다고 안내한다.
  static func downloadedNotZipMessage(isWebPage: Bool) -> String {
    if isWebPage {
      String(
        localized: """
        zip 파일 대신 웹 페이지를 받았습니다. 로그인이 필요한 주소이거나 내려받기 페이지의 주소일 수 있습니다. \
        로그인 없이 zip 파일을 바로 받을 수 있는 주소를 입력하세요.
        """,
        bundle: .module
      )
    } else {
      String(
        localized: "받은 파일이 zip 이 아니거나 손상되었습니다. 주소가 .app 을 압축한 zip 파일을 바로 가리키는지 확인하세요.",
        bundle: .module
      )
    }
  }

  /// 받은 zip 의 풀기 실패. 받은 파일 문맥의 문구가 없는 경우는 고른 zip 과 같은 문구다 (출처와 무관한 문구).
  static func downloadedZipMessage(for error: AppBundleError) -> String {
    switch error {
    case .zipWithoutApp:
      String(
        localized: """
        받은 zip 맨 위에 .app 이 없습니다. .ipa 이거나 .app 이 폴더 안에 있을 수 있습니다. \
        시뮬레이터용 .app 을 바로 압축한 zip 의 주소를 입력하세요.
        """,
        bundle: .module
      )
    case .zipWithMultipleApps:
      String(localized: "받은 zip 맨 위에 .app 이 여러 개 있습니다. .app 하나만 압축한 zip 의 주소를 입력하세요.", bundle: .module)
    case .insufficientDiskSpace:
      String(localized: "Mac 의 저장 공간이 부족해 받은 zip 을 풀지 못했습니다. 공간을 확보한 뒤 다시 시도하세요.", bundle: .module)
    case .zipUnreadable:
      // `AppInstallFailure.downloaded` 가 `.downloadedNotZip` 으로 나누므로 오지 않는다.
      self.downloadedNotZipMessage(isWebPage: false)
    case .notLocalFile, .fileNotFound:
      // 받은 파일은 늘 로컬 일반 파일이라 나오지 않는다.
      String(localized: "받은 파일을 읽지 못했습니다. 다시 시도하세요.", bundle: .module)
    case .zipUnsafeEntry, .extractionUnavailable, .ipaFile, .notAppBundle, .macOSApp, .invalidBundle:
      self.message(for: error)
    }
  }
}
