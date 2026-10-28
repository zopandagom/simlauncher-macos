import AndroidSDKInterface
import Core
import Foundation

/// 화면 문구. 모두 이 모듈의 `Localizable.xcstrings` 에서 찾는다 (`bundle: .module`).
/// 경로·revision·바이트·패키지 번호·라이선스 id·원문은 카탈로그를 거치지 않고 그대로 보인다.
/// 값이 들어가는 문구는 문자열 보간이라 카탈로그 키가 `%@`·`%lld` 자리표시를 담는다.
/// 케이스를 기본값 없이 모두 적어, 상태·오류가 늘면 컴파일러가 잡는다.
enum AndroidSetupText {
  // MARK: - 머리말

  static let checkingTitle = String(localized: "Android 도구를 확인하는 중…", bundle: .module)
  static let readyTitle = String(localized: "Android 도구가 준비되었습니다", bundle: .module)
  static let readyMessage = String(
    localized: "기기 목록에서 Android 기기를 만들고 켤 수 있습니다. 앱 설치는 다음 업데이트에서 제공합니다.",
    bundle: .module
  )
  static let notReadyTitle = String(localized: "Android 도구를 설치하세요", bundle: .module)
  static let notReadyMessage = String(
    localized: """
    Android 에뮬레이터를 쓰려면 platform-tools·emulator·시스템 이미지가 필요합니다. \
    설치를 누르면 Google 서버에서 받아 설치합니다. 약 2.5 GB 를 받아 시간이 걸릴 수 있습니다.
    """,
    bundle: .module
  )
  static let locationProblemTitle = String(localized: "SDK 폴더를 쓸 수 없습니다", bundle: .module)
  static let installingTitle = String(localized: "Android 도구를 설치하는 중입니다", bundle: .module)
  static let installingMessage = String(
    localized: "창을 닫거나 iOS 화면으로 가도 설치는 계속됩니다.",
    bundle: .module
  )
  static let verifyingInstallTitle = String(localized: "설치 결과를 확인하는 중…", bundle: .module)

  // MARK: - SDK 위치

  static let locationLabel = String(localized: "SDK 위치", bundle: .module)
  static let defaultLocationNote = String(localized: "기본 위치", bundle: .module)
  static let absentLocationNote = String(localized: "아직 없습니다. 설치하면 이 위치에 만듭니다.", bundle: .module)
  static let lockedLocationNote = String(localized: "관리자가 정한 위치입니다. 바꾸려면 담당자에게 문의하세요.", bundle: .module)

  /// 화면에 보일 폴더 경로. 디렉터리 URL 의 끝 `/` 를 뗀다.
  static func path(_ url: URL) -> String {
    let path = url.path(percentEncoded: false)
    guard path.count > 1, path.hasSuffix("/") else { return path }
    return String(path.dropLast())
  }

  static func locationTitle(for problem: AndroidSDKLocationProblem) -> String {
    switch problem {
    case .missing:
      String(localized: "고른 SDK 폴더를 찾을 수 없습니다", bundle: .module)
    case .notDirectory:
      String(localized: "SDK 위치가 폴더가 아닙니다", bundle: .module)
    case .brokenLink:
      String(localized: "SDK 위치의 링크가 가리키는 폴더가 없습니다", bundle: .module)
    case .unreadable:
      String(localized: "SDK 폴더를 읽을 수 없습니다 (권한)", bundle: .module)
    case .invalidSetting:
      String(localized: "설정된 SDK 위치를 읽을 수 없습니다", bundle: .module)
    }
  }

  /// 위치 문제의 다음 할 일. 위치가 잠겼으면 설정 창에서 바꿀 수 없어 담당자 문의를 안내한다.
  static func locationMessage(for problem: AndroidSDKLocationProblem, isLocked: Bool) -> String {
    if isLocked {
      return String(localized: "관리자가 정한 위치라 이 Mac 에서 바꿀 수 없습니다. 담당자에게 문의하세요.", bundle: .module)
    }
    switch problem {
    case .missing:
      return String(localized: "외장 디스크면 연결하고, 아니면 설정에서 SDK 위치를 다시 고르세요.", bundle: .module)
    case .notDirectory, .brokenLink:
      return String(localized: "Finder 에서 확인하거나 설정에서 다른 폴더를 고르세요.", bundle: .module)
    case .unreadable:
      return String(localized: "Finder 에서 폴더 권한을 확인하거나 설정에서 다른 폴더를 고르세요.", bundle: .module)
    case .invalidSetting:
      return String(localized: "설정에서 SDK 위치를 다시 고르세요.", bundle: .module)
    }
  }

  /// 구성 요소는 판정해 보이지만 설치를 막는 이유.
  static func blockerMessage(_ blocker: AndroidSDKInstallBlocker) -> String {
    switch blocker {
    case .notWritable:
      String(
        localized: "이 위치에 쓸 수 없어 없는 도구를 설치할 수 없습니다. Finder 에서 권한을 확인하거나 설정에서 다른 폴더를 고르세요.",
        bundle: .module
      )
    case .unsupportedVolume:
      String(
        localized: "이 디스크 형식(exFAT 등)에는 설치할 수 없습니다. 설정에서 APFS 나 Mac OS 확장 디스크의 폴더를 고르세요.",
        bundle: .module
      )
    }
  }

  // MARK: - 구성 요소

  static func componentTitle(_ component: AndroidSDKComponent) -> String {
    switch component {
    case .platformTools:
      String(localized: "플랫폼 도구 (platform-tools)", bundle: .module)
    case .emulator:
      String(localized: "에뮬레이터 (emulator)", bundle: .module)
    case .systemImage:
      String(localized: "시스템 이미지 (system-images)", bundle: .module)
    }
  }

  static func statusLabel(_ status: AndroidComponentStatus) -> String {
    switch status {
    case .installed:
      String(localized: "설치됨", bundle: .module)
    case .missing:
      String(localized: "없음", bundle: .module)
    case .unusable:
      String(localized: "쓸 수 없음", bundle: .module)
    }
  }

  static func problemMessage(_ problem: AndroidComponentProblem) -> String {
    switch problem {
    case .executableMissing:
      String(localized: "실행 파일이 없습니다. 덮어쓰지 않으므로 설치하지 않습니다.", bundle: .module)
    case .notExecutable:
      String(localized: "실행 파일에 실행 권한이 없습니다. 덮어쓰지 않으므로 설치하지 않습니다.", bundle: .module)
    case .imageFilesMissing:
      String(localized: "이미지 파일(system.img)이 없습니다. 덮어쓰지 않으므로 설치하지 않습니다.", bundle: .module)
    case .unreadable:
      String(localized: "폴더를 읽을 수 없습니다 (권한). 덮어쓰지 않으므로 설치하지 않습니다.", bundle: .module)
    }
  }

  /// 구성 요소 줄의 상세 (그대로 보인다). platform-tools·emulator 는 revision, 시스템 이미지는 API 폴더 이름
  /// (이미지의 `source.properties` revision 은 저장소 XML 과 다를 수 있어 보이지 않는다). 없으면 nil.
  static func componentDetail(
    _ component: AndroidSDKComponent,
    status: AndroidComponentStatus,
    installedSystemImages: [String]
  ) -> String? {
    guard case let .installed(revision) = status else { return nil }
    switch component {
    case .platformTools, .emulator:
      return revision.map(\.description)
    case .systemImage:
      return installedSystemImages.isEmpty ? nil : installedSystemImages.joined(separator: ", ")
    }
  }

  // MARK: - 버튼

  static let installButton = String(localized: "Android 도구 설치", bundle: .module)
  static let recheckButton = String(localized: "다시 확인", bundle: .module)
  static let deviceListButton = String(localized: "기기 목록 열기", bundle: .module)
  static let recheckingLabel = String(localized: "확인 중…", bundle: .module)
  static let revealButton = String(localized: "Finder 에서 보기", bundle: .module)
  static let openSettingsButton = String(localized: "설정 열기", bundle: .module)
  static let cancelButton = String(localized: "취소", bundle: .module)
  static let okButton = String(localized: "확인", bundle: .module)
  static let fetchingPlanLabel = String(localized: "Google 서버에서 도구 목록을 받는 중…", bundle: .module)

  // MARK: - 동의 시트

  static let consentTitle = String(localized: "Android SDK 라이선스에 동의하세요", bundle: .module)
  static let consentMessage = String(
    localized: "설치할 도구가 쓰는 라이선스입니다. 읽고 동의하면 설치를 시작합니다.",
    bundle: .module
  )
  static let consentRecordNote = String(
    localized: """
    이 동의는 SimLauncher 에만 기록됩니다. Android Studio·sdkmanager 로 다른 도구를 설치할 때는 \
    그쪽에서 따로 라이선스에 동의해야 합니다.
    """,
    bundle: .module
  )
  static let acceptButton = String(localized: "동의하고 설치", bundle: .module)
  static let downloadSizeLabel = String(localized: "받을 크기", bundle: .module)
  static let installSizeLabel = String(localized: "설치 후 크기", bundle: .module)
  static let requiredSpaceLabel = String(localized: "필요한 저장 공간", bundle: .module)
  static let unknownVolumeName = String(localized: "SDK 위치의 디스크", bundle: .module)

  static func bytes(_ count: Int64, locale: Locale) -> String {
    count.formatted(ByteCountFormatStyle(style: .file, locale: locale))
  }

  /// 설치 후 크기 어림 (예: `약 7.61 GB`).
  static func approximateInstallSize(_ plan: AndroidSDKInstallPlan, locale: Locale) -> String {
    let size = self.bytes(plan.estimatedInstallBytes, locale: locale)
    return String(localized: "약 \(size)", bundle: .module)
  }

  /// 필요한 저장 공간 줄. 같은 볼륨이면 설치 후 어림과 가장 큰 받기를 더한 한 줄, 다르면 받기(시동 디스크)·설치 두 줄
  /// (AndroidSDK Client 의 설치 전 여유 확인과 같은 어림이다).
  static func requiredSpaceLines(_ plan: AndroidSDKInstallPlan, locale: Locale) -> [String] {
    let largest = plan.packages.map(\.archive.size).max() ?? 0
    let volume = plan.sdkVolumeName ?? self.unknownVolumeName
    let install = self.bytes(plan.estimatedInstallBytes, locale: locale)
    guard !plan.sameVolumeAsDownloads else {
      let (sum, overflow) = plan.estimatedInstallBytes.addingReportingOverflow(largest)
      let total = self.bytes(overflow ? .max : sum, locale: locale)
      return [String(localized: "\(volume) 에 약 \(total)", bundle: .module)]
    }
    let download = self.bytes(largest, locale: locale)
    return [
      String(localized: "받기: 시동 디스크에 \(download)", bundle: .module),
      String(localized: "설치: \(volume) 에 약 \(install)", bundle: .module),
    ]
  }

  // MARK: - 설치 진행

  static let installLocationLabel = String(localized: "설치 위치", bundle: .module)
  static let cancellingLabel = String(localized: "취소하는 중…", bundle: .module)
  static let cannotCancelNote = String(localized: "마무리 단계라 취소할 수 없습니다. 곧 끝납니다.", bundle: .module)
  static let startingLabel = String(localized: "설치를 준비하는 중…", bundle: .module)
  static let quitAfterCancelNote = String(localized: "취소를 마치면 앱을 종료합니다.", bundle: .module)
  static let quitAfterInstallNote = String(localized: "이 도구의 마무리를 마치면 앱을 종료합니다.", bundle: .module)

  static func phaseTitle(_ phase: AndroidSDKInstallProgress.Phase) -> String {
    switch phase {
    case .downloading:
      String(localized: "받는 중…", bundle: .module)
    case .verifying:
      String(localized: "받은 파일을 확인하는 중…", bundle: .module)
    case .extracting:
      String(localized: "푸는 중…", bundle: .module)
    case .finishing:
      String(localized: "마무리하는 중…", bundle: .module)
    }
  }

  /// 패키지 줄 (예: `2/3 · 에뮬레이터 (emulator)`). 번호는 그대로, 이름은 카탈로그 문구.
  static func packageLine(_ progress: AndroidSDKInstallProgress) -> String {
    "\(progress.packageIndex)/\(progress.packageCount) · \(self.componentTitle(progress.component))"
  }

  /// 지금 패키지의 받은 바이트 (받는 중일 때만, 예: `120 MB / 416.1 MB`).
  static func packageBytes(_ progress: AndroidSDKInstallProgress, locale: Locale) -> String? {
    guard case let .downloading(received, expected) = progress.phase else { return nil }
    return "\(self.bytes(received, locale: locale)) / \(self.bytes(expected, locale: locale))"
  }

  /// 전체 받은 바이트 (예: `536.1 MB / 2.54 GB`).
  static func totalBytes(_ progress: AndroidSDKInstallProgress, locale: Locale) -> String {
    "\(self.bytes(progress.completedBytes, locale: locale)) / \(self.bytes(progress.totalBytes, locale: locale))"
  }

  /// 전체 막대 값 (0…1). 전체가 0 이면 nil (막대를 움직이지 않는다).
  static func totalFraction(_ progress: AndroidSDKInstallProgress) -> Double? {
    guard progress.totalBytes > 0 else { return nil }
    return min(max(Double(progress.completedBytes) / Double(progress.totalBytes), 0), 1)
  }

  // MARK: - 알림

  /// 알림 제목. 알림이 없으면 빈 문자열 (알림을 띄우기 전, 표시되지 않는 `.alert` 가 읽는다).
  static func title(for notice: AndroidSetupNotice?) -> String {
    switch notice {
    case .none:
      ""
    case .revealFailed:
      String(localized: "Finder 에서 보이지 못했습니다", bundle: .module)
    }
  }

  static func message(for notice: AndroidSetupNotice) -> String {
    switch notice {
    case .revealFailed:
      String(localized: "폴더가 옮겨졌거나 지워졌을 수 있습니다. 다시 확인을 누르세요.", bundle: .module)
    }
  }

  // MARK: - 종료 확인

  static let terminationTitle = String(localized: "Android 도구 설치를 멈추고 종료할까요?", bundle: .module)
  static let terminationMessage = String(
    localized: """
    지금 종료하면 받고 있는 도구의 설치가 취소됩니다. 이미 설치를 마친 도구는 남습니다. \
    마무리 단계에 들어간 도구는 마친 뒤 종료합니다.
    """,
    bundle: .module
  )
  static let continueInstallButton = String(localized: "계속 설치", bundle: .module)
  static let quitButton = String(localized: "종료", bundle: .module)
}
