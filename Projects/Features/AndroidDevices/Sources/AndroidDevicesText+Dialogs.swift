import AndroidEmulatorInterface
import Core
import Foundation

/// 삭제·초기화 확인 대화상자와 만들기 시트의 문구.
extension AndroidDevicesText {
  // MARK: - 삭제·초기화 확인

  /// 확인 대화상자 제목. 확인할 것이 없으면 빈 문자열 (닫힌 대화상자가 읽는다).
  static func confirmationTitle(for confirmation: AndroidDeviceConfirmation?) -> String {
    guard let confirmation else { return "" }
    let label = self.label(confirmation.device)
    return switch confirmation.action {
    case .delete:
      String(localized: "\(label) 기기를 삭제할까요?", bundle: .module)
    case .erase:
      String(localized: "\(label) 기기를 초기화할까요?", bundle: .module)
    }
  }

  static func confirmationMessage(for action: AndroidDeviceConfirmation.Action) -> String {
    switch action {
    case .delete:
      String(localized: "기기와 그 안의 앱·데이터가 모두 지워지며 되돌릴 수 없습니다.", bundle: .module)
    case .erase:
      String(
        localized: "기기에 설치한 앱과 데이터, 설정이 모두 지워지고 처음 상태로 돌아갑니다. 다음에 켤 때 시간이 더 걸립니다. 되돌릴 수 없습니다.",
        bundle: .module
      )
    }
  }

  static func confirmButton(for action: AndroidDeviceConfirmation.Action) -> String {
    switch action {
    case .delete:
      String(localized: "삭제", bundle: .module)
    case .erase:
      String(localized: "초기화", bundle: .module)
    }
  }

  static var cancelButton: String {
    String(localized: "취소", bundle: .module)
  }

  // MARK: - 만들기

  static var createSheetTitle: String {
    String(localized: "새 Android 기기 만들기", bundle: .module)
  }

  static var nameField: String {
    String(localized: "이름", bundle: .module)
  }

  static var imagePicker: String {
    String(localized: "시스템 이미지", bundle: .module)
  }

  static var profilePicker: String {
    String(localized: "화면", bundle: .module)
  }

  static var createConfirmButton: String {
    String(localized: "만들기", bundle: .module)
  }

  /// 시스템 이미지 선택 항목 "API 37.0 · google_apis". 태그는 SDK 폴더 이름 그대로 보인다.
  static func imageOption(_ image: AndroidSystemImageRef) -> String {
    String(localized: "API \(image.apiLabel) · \(image.tag)", bundle: .module)
  }

  /// 화면 모양 선택 항목 "휴대전화 (1080×2400)".
  static func profileOption(_ profile: AndroidDeviceProfile) -> String {
    let size = "\(profile.width)×\(profile.height)"
    return switch profile.id {
    case .phone:
      String(localized: "휴대전화 (\(size))", bundle: .module)
    case .smallPhone:
      String(localized: "작은 휴대전화 (\(size))", bundle: .module)
    case .tablet:
      String(localized: "태블릿 (\(size))", bundle: .module)
    case .foldable:
      String(localized: "폴더블 (\(size))", bundle: .module)
    }
  }

  /// 폴더블을 골랐는데 고른 시스템 이미지에 접기 설정 파일이 없을 때 화면 모양 아래에 보인다.
  static var foldableImageUnsupported: String {
    String(
      localized: "이 시스템 이미지에는 폴더블 설정이 없어 폴더블을 만들 수 없습니다. 다른 시스템 이미지를 고르세요.",
      bundle: .module
    )
  }

  /// 화면 모양 아래 안내. 앱이 만드는 화면 모양은 셋뿐이고, Android Studio 가 만든 기기(폴더블 포함)도 이 목록에서 켠다.
  static var studioDevicesGuide: String {
    String(
      localized: "폴더블 등 더 많은 기기는 Android Studio 의 기기 관리자(Device Manager)에서 만들면 이 목록에 보입니다.",
      bundle: .module
    )
  }

  static var studioLinkTitle: String {
    String(localized: "Android Studio 내려받기 페이지", bundle: .module)
  }

  /// Android Studio 내려받기 공개 페이지. 시트의 `Link` 가 시스템 기본 브라우저로 연다 (앱이 받는 것이 아니다).
  static let studioDownloadURL: URL = {
    let raw = "https://developer.android.com/studio"
    guard let url = URL(string: raw) else {
      preconditionFailure("고정 주소가 URL 이 아니다: \(raw)")
    }
    return url
  }()

  /// 이름 입력란 아래에 보이는 문제. iOS 기기 만들기(Launcher)와 같은 키·값이다 (`NameProblemSyncTests` 가 묶는다).
  /// 100 은 `DeviceName.maxLength` 와 맞춘 고정 문구다 (바꾸면 함께).
  static func nameProblem(_ problem: DeviceNameProblem) -> String {
    switch problem {
    case .empty:
      String(localized: "이름을 입력하세요.", bundle: .module)
    case .tooLong:
      String(localized: "이름은 100자까지 입력할 수 있습니다.", bundle: .module)
    case .containsControlCharacter:
      String(localized: "이름에 줄바꿈이나 탭은 쓸 수 없습니다.", bundle: .module)
    }
  }
}
