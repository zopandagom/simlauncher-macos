import AndroidSDKInterface
import Core
import Foundation

/// 계획·설치 실패와 설치 결과 문구. 받기 실패의 다음 할 일은 주소가 아니라 Google 서버·인터넷 연결이라
/// Launcher 의 URL 받기 문구와 조각을 함께 쓰지 않는다 (동기화 테스트 대상이 아니다).
extension AndroidSetupText {
  // MARK: - 계획 실패

  /// 계획 실패 줄. `.cancelled` 는 줄을 보이지 않는다 (nil).
  static func message(for error: AndroidSDKPlanError) -> String? {
    switch error {
    case let .download(failure):
      "\(self.planDownloadFailed) \(self.message(for: failure))"
    case .repositoryUnreadable:
      String(
        localized: "Android 도구 목록의 형식을 읽지 못했습니다. 잠시 뒤 다시 시도하고, 계속되면 앱을 업데이트하세요.",
        bundle: .module
      )
    case let .noCompatiblePackage(component):
      self.noCompatiblePackage(self.componentTitle(component))
    case .sdkFolderUnavailable:
      String(localized: "SDK 폴더에 쓸 수 없습니다. 다시 확인을 누르고 화면의 안내를 따르세요.", bundle: .module)
    case .cancelled:
      nil
    }
  }

  static var planDownloadFailed: String {
    String(localized: "Android 도구 목록을 Google 서버에서 받지 못했습니다.", bundle: .module)
  }

  static func noCompatiblePackage(_ name: String) -> String {
    String(localized: "이 Mac 에 맞는 \(name) 을(를) 찾지 못했습니다. 앱 업데이트가 필요할 수 있습니다.", bundle: .module)
  }

  // MARK: - 받기 실패

  /// 받기 실패 원인과 다음 할 일 (Google 서버·인터넷 연결).
  static func message(for failure: AndroidDownloadFailure) -> String {
    switch failure {
    case .offline, .hostNotFound, .cannotConnect, .timedOut, .connectionLost, .secureConnectionFailed:
      self.connectionMessage(for: failure)
    case .insecureRedirect:
      String(localized: "서버가 안전하지 않은 주소(http)로 넘겨 보내 받지 않았습니다. 잠시 뒤 다시 시도하세요.", bundle: .module)
    case let .httpStatus(code):
      self.httpStatusMessage(code)
    case .insufficientDiskSpace:
      String(localized: "시동 디스크의 저장 공간이 부족해 받지 못했습니다. 공간을 확보한 뒤 다시 시도하세요.", bundle: .module)
    case .tooLarge:
      String(localized: "Google 서버의 도구 목록이 예상보다 커서 받지 않았습니다. 앱을 업데이트하세요.", bundle: .module)
    case .storageUnavailable:
      String(
        localized: "받은 파일을 둘 임시 폴더를 준비하지 못했습니다. 잠시 뒤 다시 시도하고, 계속되면 Mac 을 다시 시작해 보세요.",
        bundle: .module
      )
    case .failed:
      String(localized: "받지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시도하세요.", bundle: .module)
    }
  }

  static func httpStatusMessage(_ code: Int) -> String {
    String(
      localized: "Google 서버가 요청을 받아 주지 않았습니다 (HTTP \(code)). 잠시 뒤 다시 시도하고, 계속되면 앱을 업데이트하세요.",
      bundle: .module
    )
  }

  /// 연결·전송 실패 (`message(for:)` 가 넘기는 케이스만 온다. 복잡도를 나눈다).
  private static func connectionMessage(for failure: AndroidDownloadFailure) -> String {
    switch failure {
    case .offline:
      String(localized: "인터넷에 연결되어 있지 않습니다. 연결을 확인한 뒤 다시 시도하세요.", bundle: .module)
    case .hostNotFound:
      String(
        localized: "Google 서버 주소를 찾지 못했습니다. 인터넷 연결과, 회사망이라면 dl.google.com 접속이 막혀 있지 않은지 확인하세요.",
        bundle: .module
      )
    case .cannotConnect:
      String(
        localized: "Google 서버에 연결하지 못했습니다. 인터넷 연결과, 회사망이라면 프록시 설정을 확인하세요.",
        bundle: .module
      )
    case .timedOut:
      String(localized: "Google 서버가 오래 응답하지 않아 멈췄습니다. 연결을 확인한 뒤 다시 시도하세요.", bundle: .module)
    case .connectionLost:
      String(localized: "받는 중 연결이 끊겨 받은 부분을 지웠습니다. 다시 시도하세요.", bundle: .module)
    case .secureConnectionFailed:
      String(
        localized: "Google 서버의 보안 인증서를 확인하지 못해 받지 않았습니다. Mac 의 날짜·시간과 네트워크의 보안 소프트웨어를 확인하세요.",
        bundle: .module
      )
    case .insecureRedirect, .httpStatus, .insufficientDiskSpace, .tooLarge, .storageUnavailable, .failed:
      String(localized: "받지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시도하세요.", bundle: .module)
    }
  }

  // MARK: - 설치 결과

  /// 설치 결과 줄. 설치 중이거나 설치 결과를 확인하는 중이면 View 가 부르지 않는다.
  static func resultMessage(for result: AndroidSetupInstallResult) -> String {
    switch result.kind {
    case let .finished(outcome):
      self.finishedMessage(outcome)
    case let .failed(error):
      self.message(for: error)
    }
  }

  /// 설치 중 설정에서 위치를 바꿨을 때 결과 줄 아래에 덧붙인다 (원래 위치에 설치한 것은 새 위치 판정에 보이지 않는다).
  static func originalLocationNote(_ root: AndroidSDKRoot) -> String {
    let path = self.path(root.url)
    return String(localized: "원래 위치(\(path))에 설치했습니다. 지금 SDK 위치에는 보이지 않습니다.", bundle: .module)
  }

  private static func finishedMessage(_ outcome: AndroidSDKInstallOutcome) -> String {
    if outcome.installed.isEmpty {
      return String(localized: "설치할 도구가 이미 있어 아무것도 받지 않았습니다.", bundle: .module)
    }
    if outcome.alreadyPresent.isEmpty {
      return String(localized: "Android 도구를 설치했습니다.", bundle: .module)
    }
    return String(localized: "Android 도구를 설치했습니다. 일부는 이미 있어 건너뛰었습니다.", bundle: .module)
  }

  /// 설치 실패 줄. 다시 설치를 누르면 아직 없는 도구만 받는다.
  static func message(for error: AndroidSDKInstallError) -> String {
    switch error {
    case let .download(component, failure):
      "\(self.componentFailed(self.componentTitle(component))) \(self.message(for: failure))"
    case let .insufficientDiskSpace(_, required, available):
      self.insufficientSpaceMessage(required: required, available: available, locale: .current)
    case .checksumMismatch, .archiveUnreadable, .archiveUnsafe:
      self.archiveMessage(for: error)
    case .sdkFolderUnavailable:
      String(
        localized: "SDK 폴더에 쓸 수 없어 설치하지 못했습니다. Finder 에서 폴더 권한을 확인하거나 설정에서 다른 폴더를 고르세요.",
        bundle: .module
      )
    case let .destinationExists(component):
      self.destinationExists(self.componentTitle(component))
    case .licenseNotAccepted:
      String(localized: "라이선스 동의를 확인하지 못해 설치하지 않았습니다. 다시 설치를 누르세요.", bundle: .module)
    case .sdkLocationChanged:
      String(localized: "SDK 위치가 바뀌어 설치하지 않고 새 위치를 다시 확인했습니다.", bundle: .module)
    case .cancelled:
      String(localized: "설치를 취소했습니다.", bundle: .module)
    }
  }

  static func componentFailed(_ name: String) -> String {
    String(localized: "\(name) 을(를) 받지 못했습니다.", bundle: .module)
  }

  static func destinationExists(_ name: String) -> String {
    String(
      localized: "같은 이름의 폴더가 이미 있어 \(name) 을(를) 설치하지 않았습니다. Android Studio 가 설치 중이었을 수 있습니다. 다시 확인을 누르세요.",
      bundle: .module
    )
  }

  /// 필요한 양과(읽었으면) 남은 양을 함께 보인다.
  static func insufficientSpaceMessage(required: Int64, available: Int64?, locale: Locale) -> String {
    let needed = self.bytes(required, locale: locale)
    guard let available else {
      return String(
        localized: "저장 공간이 부족해 설치하지 못했습니다. \(needed) 가 필요합니다. 공간을 확보한 뒤 다시 시도하세요.",
        bundle: .module
      )
    }
    let left = self.bytes(available, locale: locale)
    return String(
      localized: "저장 공간이 부족해 설치하지 못했습니다. \(needed) 가 필요한데 \(left) 남아 있습니다. 공간을 확보한 뒤 다시 시도하세요.",
      bundle: .module
    )
  }

  /// 받은 파일 문제 (`message(for:)` 가 넘기는 케이스만 온다. 복잡도를 나눈다).
  private static func archiveMessage(for error: AndroidSDKInstallError) -> String {
    switch error {
    case .checksumMismatch:
      String(localized: "받은 파일이 손상되었습니다. 다시 설치를 누르세요.", bundle: .module)
    case .archiveUnsafe:
      String(localized: "받은 파일의 형식이 예상과 달라 설치하지 않았습니다. 앱을 업데이트하세요.", bundle: .module)
    case .archiveUnreadable, .download, .insufficientDiskSpace, .sdkFolderUnavailable, .destinationExists,
         .licenseNotAccepted, .sdkLocationChanged, .cancelled:
      String(localized: "받은 파일을 풀지 못했습니다. 다시 설치를 누르고, 계속되면 앱을 업데이트하세요.", bundle: .module)
    }
  }
}
