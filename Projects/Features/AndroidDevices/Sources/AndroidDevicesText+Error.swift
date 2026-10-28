import AndroidEmulatorInterface
import Core
import Foundation

/// 에러 본문(원인 + 다음 할 일)과 행의 "사용할 수 없음" 이유. emulator·adb 출력 원문은 보이지 않는다
/// (emulator 의 실패 문구는 원인과 맞지 않는다, 실측. Client 가 켜기 전에 파일로 원인을 정한다).
extension AndroidDevicesText {
  /// 에러 본문. 취소(`.cancelled`)는 알리지 않으므로 nil.
  static func message(for error: AndroidEmulatorError) -> String? {
    switch error {
    case .sdkUnavailable:
      String(
        localized: "Android 도구(emulator·platform-tools)를 찾지 못했습니다. 오른쪽 위 Android 도구에서 상태를 확인하세요.",
        bundle: .module
      )
    case .deviceNotFound:
      String(localized: "기기를 찾지 못했습니다. 목록을 새로 고친 뒤 다시 시도하세요.", bundle: .module)
    case let .deviceUnavailable(reason):
      self.reason(for: reason)
    case .deviceRunning:
      String(localized: "기기가 켜져 있습니다. 기기를 끈 뒤에 다시 시도하세요.", bundle: .module)
    case .emulatorLaunchFailed, .emulatorExited, .bootTimedOut, .adbUnavailable, .shutdownTimedOut:
      self.runMessage(for: error)
    case .invalidDeviceName, .nameUnavailable, .creationOptionUnavailable, .avdFolderUnavailable,
         .fileOperationFailed, .unsafeDeviceFolder:
      self.fileMessage(for: error)
    case .cancelled:
      nil
    }
  }

  /// 켜기·끄기 실패 본문.
  private static func runMessage(for error: AndroidEmulatorError) -> String? {
    switch error {
    case .emulatorLaunchFailed:
      String(
        localized: "에뮬레이터를 실행하지 못했습니다. 오른쪽 위 Android 도구에서 emulator 상태를 확인하세요.",
        bundle: .module
      )
    case .emulatorExited:
      String(
        localized: "켜는 도중 에뮬레이터가 끝났습니다. 저장 공간이 넉넉한지 확인하고 다시 켜 보세요. 계속 켜지지 않으면 기기를 초기화해 보세요.",
        bundle: .module
      )
    case .bootTimedOut:
      String(
        localized: "10분이 지나도 켜기를 마치지 못했습니다. 에뮬레이터 창에서 상태를 확인하세요. 계속 켜지지 않으면 기기를 끈 뒤 초기화해 보세요.",
        bundle: .module
      )
    case .adbUnavailable:
      String(
        localized: "기기 상태를 확인하지 못했습니다. 잠시 뒤 다시 시도하세요. 계속되면 오른쪽 위 Android 도구에서 platform-tools 상태를 확인하세요.",
        bundle: .module
      )
    case .shutdownTimedOut:
      String(localized: "기기가 꺼지지 않았습니다. 에뮬레이터 창을 닫아 끈 뒤 목록을 새로 고치세요.", bundle: .module)
    default:
      nil
    }
  }

  /// 만들기·삭제·초기화의 파일 작업 실패 본문.
  private static func fileMessage(for error: AndroidEmulatorError) -> String? {
    switch error {
    case let .invalidDeviceName(problem):
      self.nameProblem(problem)
    case .nameUnavailable:
      String(localized: "같은 이름의 기기가 너무 많습니다. 다른 이름으로 만드세요.", bundle: .module)
    case .creationOptionUnavailable:
      String(localized: "고른 시스템 이미지를 더 이상 찾을 수 없습니다. 목록을 새로 고친 뒤 다시 만드세요.", bundle: .module)
    case .avdFolderUnavailable:
      String(localized: "기기 폴더(~/.android/avd)에 쓰지 못했습니다. 폴더 권한과 저장 공간을 확인하세요.", bundle: .module)
    case .fileOperationFailed:
      String(localized: "기기 파일을 모두 지우지 못했습니다. 폴더 권한을 확인한 뒤 다시 시도하세요.", bundle: .module)
    case let .unsafeDeviceFolder(folder):
      self.unsafeDeviceFolderMessage(folder)
    default:
      nil
    }
  }

  /// 행의 "사용할 수 없음" 이유. 켜기 실패(`.deviceUnavailable`)의 본문도 같다.
  static func reason(for reason: AndroidVirtualDevice.UnavailableReason) -> String {
    switch reason {
    case .unsupportedName:
      return String(
        localized: "이름에 영문·숫자·. _ - 밖의 문자가 있어 에뮬레이터로 켤 수 없는 기기입니다. 삭제만 할 수 있습니다.",
        bundle: .module
      )
    case .folderMissing:
      return String(localized: "기기 폴더가 없어 사용할 수 없습니다. 삭제만 할 수 있습니다.", bundle: .module)
    case .configUnreadable:
      return String(localized: "기기 설정 파일을 읽지 못해 사용할 수 없습니다. 삭제만 할 수 있습니다.", bundle: .module)
    case let .systemImageMissing(image):
      guard let image else {
        return String(localized: "이 기기의 시스템 이미지 설정을 읽지 못해 사용할 수 없습니다. 삭제만 할 수 있습니다.", bundle: .module)
      }
      let api = image.apiLabel
      let tag = image.tag
      return String(
        localized: """
        이 기기에 필요한 시스템 이미지(API \(api), \(tag))가 지금 Android 도구 위치에 없어 사용할 수 없습니다. \
        설정에서 Android 도구 위치를 확인하거나, 기기를 삭제하세요.
        """,
        bundle: .module
      )
    case let .unsupportedABI(abi):
      return String(localized: "이 Mac 에서 실행할 수 없는 시스템 이미지(\(abi))를 쓰는 기기입니다. 삭제만 할 수 있습니다.", bundle: .module)
    }
  }

  /// 초기화 거절: 기기 폴더가 링크이거나 `.avd` 로 끝나지 않는다. 경로를 알면 끝에 보인다.
  private static func unsafeDeviceFolderMessage(_ folder: URL?) -> String {
    guard let folder else {
      return String(localized: "기기 폴더 위치가 예상과 달라 초기화하지 않았습니다. 기기를 삭제한 뒤 새로 만드세요.", bundle: .module)
    }
    let path = self.path(folder)
    return String(
      localized: "기기 폴더 위치가 예상과 달라 초기화하지 않았습니다. 기기를 삭제한 뒤 새로 만드세요. (\(path))",
      bundle: .module
    )
  }
}
