import Core
import Foundation

/// 기기 행 ⋯ 메뉴(행 끝 버튼과 행 컨텍스트 메뉴가 같은 항목)에 그릴 것: 묶음마다 맨 위 이유 줄과 항목별 활성.
/// `LauncherText.deviceMenu(_:)` 가 만들고 `DeviceRow` 는 이 값만 그린다.
/// 묶음: 앱(설치된 앱·링크 열기) / 화면(스크린샷·녹화·레이아웃 보기·테스트 조건) / 기기(초기화·삭제).
struct DeviceRowMenu: Equatable {
  /// 메뉴를 고르는 데 쓰는 행의 값 (`DeviceRow` 의 입력 그대로).
  struct Input {
    let device: VirtualDevice
    /// 이 기기에 진행 중인 작업이 있다.
    let isBusy: Bool
    /// 이 기기가 녹화 중이다 (시작·저장 중 포함).
    let isRecording: Bool
    /// 이 기기의 스크린샷을 찍는 중이다.
    let isTakingScreenshot: Bool
    let canOpenInstalledApps: Bool
    let canTakeScreenshot: Bool
    let canStartRecording: Bool
    let canViewLayout: Bool
    let canChangeTestConditions: Bool
  }

  /// 앱 묶음 맨 위 이유 줄. nil 이면 줄이 없다.
  let appReason: String?
  let canOpenInstalledApps: Bool
  let canOpenURL: Bool
  /// 화면 묶음 맨 위 이유 줄.
  let screenReason: String?
  let canTakeScreenshot: Bool
  let canRecord: Bool
  let canViewLayout: Bool
  let canChangeTestConditions: Bool
  /// 기기 묶음 맨 위 이유 줄.
  let deviceReason: String?
  let canErase: Bool
  let canDelete: Bool
}

extension LauncherText {
  /// 기기 행 ⋯ 메뉴의 묶음별 이유 줄과 항목별 활성.
  /// - 항목 활성은 행 버튼이던 때의 값 그대로다: 링크 열기는 앱 설치와 같은 규칙(작업 없음 + `appInstallAvailability`),
  ///   스크린샷은 찍는 중이 아닐 때, 녹화는 `canStartRecording`(녹화 중이면 false, 행의 "중지"로 멈춘다).
  ///   초기화·삭제만 진행 작업·녹화 중에 막는다. 스크린샷·레이아웃·테스트 조건은 앱 작업 중에도 된다 (메뉴 전체를 막지 않는다).
  /// - 이유 줄은 기기 상태로 고른다. 진행 작업으로만 막힌 항목은 행의 진행 표시가 이유라 줄을 두지 않는다.
  ///   앱 묶음: 두 항목이 함께 막히면 묶음 이유, 꺼진 기기처럼 설치된 앱만 막히면 설치된 앱 이유.
  ///   화면 묶음: 켜지지 않았거나 쓸 수 없으면 묶음 이유, 아니면 러너보다 낮은 iOS 의 레이아웃 이유.
  ///   기기 묶음: 녹화 중이면 녹화 이유를 먼저, 작업 중이면 줄 없음, 아니면 켜짐·쓸 수 없음 이유.
  static func deviceMenu(_ input: DeviceRowMenu.Input) -> DeviceRowMenu {
    let device = input.device
    let appReason: String? = if case let .blocked(reason) = device.appInstallAvailability {
      self.appGroupBlockReason(reason)
    } else if case let .blocked(reason) = device.screenshotAvailability {
      self.installedAppsBlockReason(reason)
    } else {
      nil
    }
    let screenReason: String? = if case let .blocked(reason) = device.screenshotAvailability {
      self.screenGroupBlockReason(reason)
    } else if !IOSLayoutAvailability.supportsRunner(device) {
      self.layoutUnsupportedOS
    } else {
      nil
    }
    let canChangeDevice = !input.isBusy && !input.isRecording
    return DeviceRowMenu(
      appReason: appReason,
      canOpenInstalledApps: input.canOpenInstalledApps,
      canOpenURL: !input.isBusy && device.appInstallAvailability == .allowed,
      screenReason: screenReason,
      canTakeScreenshot: input.canTakeScreenshot && !input.isTakingScreenshot,
      canRecord: input.canStartRecording && !input.isRecording,
      canViewLayout: input.canViewLayout,
      canChangeTestConditions: input.canChangeTestConditions,
      deviceReason: self.deviceGroupBlockReason(input),
      canErase: canChangeDevice && device.eraseAvailability == .allowed,
      canDelete: canChangeDevice && device.deleteAvailability == .allowed
    )
  }

  /// 기기 묶음(초기화·삭제) 이유 줄. 녹화 중이면 녹화 이유를 먼저 보인다. 작업 중이면 진행 표시가 이유라 줄이 없다.
  /// 켜져 있으면 삭제·초기화 모두, 쓸 수 없으면 초기화가 막힌다.
  private static func deviceGroupBlockReason(_ input: DeviceRowMenu.Input) -> String? {
    if input.isRecording {
      return self.recordingBlocksDeviceActions
    }
    if input.isBusy {
      return nil
    }
    if case .blocked(.notShutdown) = input.device.deleteAvailability {
      return self.blockReason(.notShutdown)
    }
    if case .blocked(.unavailable) = input.device.eraseAvailability {
      return self.blockReason(.unavailable)
    }
    return nil
  }

  /// 앱 묶음(설치된 앱·링크 열기)이 함께 막힌 이유 줄. 항목 이름이 바로 아래 있어 무엇을 쓸 수 없는지는 말하지 않는다.
  static func appGroupBlockReason(_ reason: AppInstallBlockReason) -> String {
    switch reason {
    case .unavailable:
      String(localized: "사용할 수 없는 기기에서는 쓸 수 없습니다", bundle: .module)
    case .stateChanging:
      String(localized: "기기를 켜거나 끄는 중에는 쓸 수 없습니다. 끝난 뒤 다시 시도하세요", bundle: .module)
    }
  }

  /// 화면 묶음(스크린샷·녹화·레이아웃 보기·테스트 조건)이 막힌 이유 줄.
  static func screenGroupBlockReason(_ reason: ScreenshotBlockReason) -> String {
    switch reason {
    case .notBooted:
      String(localized: "켜진 기기에서만 쓸 수 있습니다. 기기를 켠 뒤 다시 시도하세요", bundle: .module)
    case .unavailable:
      String(localized: "사용할 수 없는 기기에서는 쓸 수 없습니다", bundle: .module)
    }
  }
}
