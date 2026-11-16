import AndroidEmulatorTesting
import Core
import Foundation
import Testing
@testable import AndroidDevicesFeature

/// 기기 행 ⋯ 메뉴의 묶음별 이유 줄과 항목별 활성 (`AndroidDevicesText.deviceMenu(_:)`). 입력의 활성 값은 행이 받는 것과 같은 규칙
/// (`AndroidScreenshotActivity`·`AndroidRecordingActivity`·`AndroidInstalledAppsAvailability`·`AndroidLayoutAvailability`·
/// `AndroidTestConditionsAvailability`)으로 만든다.
struct AndroidDeviceRowTextTests {
  // MARK: - 상태별

  @Test("꺼진 기기: 앱·화면 묶음은 켜진 기기 이유 줄과 함께 모두 막히고, 초기화·삭제는 된다")
  func shutdown() {
    let menu = Self.menu(.phoneSample)

    #expect(menu.appReason == AndroidDevicesText.deviceMenuGroupBlockReason(.notBooted))
    #expect(!menu.canOpenInstalledApps && !menu.canOpenURL)
    #expect(menu.screenReason == AndroidDevicesText.deviceMenuGroupBlockReason(.notBooted))
    #expect(!menu.canTakeScreenshot && !menu.canRecord && !menu.canViewLayout && !menu.canChangeTestConditions)
    #expect(menu.deviceReason == nil)
    #expect(menu.canErase && menu.canDelete)
  }

  @Test("앱 밖에서 켜는 중: 앱·화면 묶음은 켜진 기기 이유 줄, 기기 묶음은 끈 뒤에 하라는 이유 줄과 함께 막힌다")
  func booting() {
    let menu = Self.menu(.bootingSample)

    #expect(menu.appReason == AndroidDevicesText.deviceMenuGroupBlockReason(.notBooted))
    #expect(!menu.canOpenInstalledApps && !menu.canOpenURL)
    #expect(menu.screenReason == AndroidDevicesText.deviceMenuGroupBlockReason(.notBooted))
    #expect(!menu.canTakeScreenshot && !menu.canRecord && !menu.canViewLayout && !menu.canChangeTestConditions)
    #expect(menu.deviceReason == AndroidDevicesText.blockReason(.notShutdown))
    #expect(!menu.canErase && !menu.canDelete)
  }

  @Test("앱이 켜는 중: 모든 항목이 막히고, 기기 묶음은 진행 표시가 이유라 줄이 없다")
  func bootTask() {
    let menu = Self.menu(.phoneSample.with(state: .booting), task: .boot)

    #expect(menu.appReason == AndroidDevicesText.deviceMenuGroupBlockReason(.notBooted))
    #expect(menu.screenReason == AndroidDevicesText.deviceMenuGroupBlockReason(.notBooted))
    #expect(!menu.canOpenInstalledApps && !menu.canOpenURL)
    #expect(!menu.canTakeScreenshot && !menu.canRecord && !menu.canViewLayout && !menu.canChangeTestConditions)
    #expect(menu.deviceReason == nil)
    #expect(!menu.canErase && !menu.canDelete)
  }

  @Test("켜진 기기: 앱·화면 항목이 모두 되고 이유 줄이 없으며, 기기 묶음은 끈 뒤에 하라는 이유 줄과 함께 막힌다")
  func booted() {
    let menu = Self.menu(.bootedTabletSample)

    #expect(menu.appReason == nil)
    #expect(menu.canOpenInstalledApps && menu.canOpenURL)
    #expect(menu.screenReason == nil)
    #expect(menu.canTakeScreenshot && menu.canRecord && menu.canViewLayout && menu.canChangeTestConditions)
    #expect(menu.deviceReason == AndroidDevicesText.blockReason(.notShutdown))
    #expect(!menu.canErase && !menu.canDelete)
  }

  @Test(
    "앱 설치·실행·링크 열기 중: 스크린샷·녹화·레이아웃·테스트 조건은 되고, 설치된 앱·링크 열기·초기화·삭제는 이유 줄 없이 막힌다",
    arguments: [AndroidDeviceTask.installApp, .launchApp, .openURL]
  )
  func appTask(task: AndroidDeviceTask) {
    let menu = Self.menu(.bootedTabletSample, task: task)

    #expect(menu.appReason == nil)
    #expect(!menu.canOpenInstalledApps && !menu.canOpenURL)
    #expect(menu.screenReason == nil)
    #expect(menu.canTakeScreenshot && menu.canRecord && menu.canViewLayout && menu.canChangeTestConditions)
    #expect(menu.deviceReason == nil)
    #expect(!menu.canErase && !menu.canDelete)
  }

  @Test("스크린샷 찍는 중: 스크린샷만 막히고 녹화·레이아웃·테스트 조건은 된다")
  func takingScreenshot() {
    let menu = Self.menu(.bootedTabletSample, isTakingScreenshot: true)

    #expect(menu.screenReason == nil)
    #expect(!menu.canTakeScreenshot)
    #expect(menu.canRecord && menu.canViewLayout && menu.canChangeTestConditions)
    #expect(menu.canOpenInstalledApps && menu.canOpenURL)
  }

  @Test("녹화 중: 녹화·초기화·삭제가 막히고 기기 묶음 이유 줄은 녹화 이유다. 스크린샷·레이아웃·테스트 조건은 된다")
  func recording() {
    let menu = Self.menu(.bootedTabletSample, isRecording: true)

    #expect(!menu.canRecord)
    #expect(menu.canTakeScreenshot && menu.canViewLayout && menu.canChangeTestConditions)
    #expect(menu.screenReason == nil)
    #expect(menu.deviceReason == AndroidDevicesText.recordingBlocksDeviceActions)
    #expect(!menu.canErase && !menu.canDelete)
  }

  @Test("녹화 중에 앱을 설치하는 중이어도 기기 묶음 이유 줄은 녹화 이유다")
  func recordingDuringAppTask() {
    let menu = Self.menu(.bootedTabletSample, task: .installApp, isRecording: true)

    #expect(menu.deviceReason == AndroidDevicesText.recordingBlocksDeviceActions)
    #expect(!menu.canErase && !menu.canDelete)
  }

  @Test("끄기·삭제·초기화 중: 모든 항목이 막히고 이유 줄이 없다", arguments: [AndroidDeviceTask.shutdown, .delete, .erase])
  func deviceTask(task: AndroidDeviceTask) {
    let menu = Self.menu(.bootedTabletSample, task: task)

    #expect(!menu.canOpenInstalledApps && !menu.canOpenURL)
    #expect(!menu.canTakeScreenshot && !menu.canRecord && !menu.canViewLayout && !menu.canChangeTestConditions)
    #expect(!menu.canErase && !menu.canDelete)
    #expect(menu.appReason == nil)
    #expect(menu.screenReason == nil)
    #expect(menu.deviceReason == nil)
  }

  @Test("쓸 수 없는 꺼진 기기: 앱·화면 묶음은 쓸 수 없음 이유 줄과 함께 막히고, 초기화는 막히고 삭제만 된다")
  func unavailableShutdown() {
    let menu = Self.menu(.unsupportedNameSample)

    #expect(menu.appReason == AndroidDevicesText.deviceMenuGroupBlockReason(.unavailable))
    #expect(!menu.canOpenInstalledApps && !menu.canOpenURL)
    #expect(menu.screenReason == AndroidDevicesText.deviceMenuGroupBlockReason(.unavailable))
    #expect(!menu.canTakeScreenshot && !menu.canRecord && !menu.canViewLayout && !menu.canChangeTestConditions)
    #expect(menu.deviceReason == AndroidDevicesText.blockReason(.unavailable))
    #expect(!menu.canErase)
    #expect(menu.canDelete)
  }

  @Test("쓸 수 없는 켜진 기기: 기기 묶음 이유 줄은 끈 뒤에 하라는 것이다 (삭제가 막힌 이유를 먼저)")
  func unavailableBooted() {
    let menu = Self.menu(.sdkUnavailableBootedSample)

    #expect(menu.appReason == AndroidDevicesText.deviceMenuGroupBlockReason(.unavailable))
    #expect(menu.screenReason == AndroidDevicesText.deviceMenuGroupBlockReason(.unavailable))
    #expect(menu.deviceReason == AndroidDevicesText.blockReason(.notShutdown))
    #expect(!menu.canErase && !menu.canDelete)
  }

  // MARK: - 문구

  @Test("묶음 이유 문구는 케이스마다 다르고, 비어 있지 않은 한국어다")
  func groupReasonTexts() {
    let texts = [AndroidAppActionBlockReason.notBooted, .unavailable].map {
      AndroidDevicesText.deviceMenuGroupBlockReason($0)
    }

    #expect(Set(texts).count == 2)
    for text in texts {
      #expect(text.unicodeScalars.contains { (0xAC00 ... 0xD7A3).contains($0.value) }, "\(text)")
    }
  }

  // MARK: - 도우미

  /// 행이 받는 것과 같은 규칙으로 입력을 만들어 메뉴를 고른다.
  private static func menu(
    _ device: AndroidVirtualDevice,
    task: AndroidDeviceTask? = nil,
    isRecording: Bool = false,
    isTakingScreenshot: Bool = false
  ) -> AndroidDeviceRowMenu {
    AndroidDevicesText.deviceMenu(
      AndroidDeviceRowMenu.Input(
        device: device,
        isBusy: task != nil,
        isRecording: isRecording,
        isTakingScreenshot: isTakingScreenshot,
        canOpenInstalledApps: AndroidInstalledAppsAvailability.canOpen(device: device, during: task),
        canTakeScreenshot: !isTakingScreenshot && AndroidScreenshotActivity().canStart(on: device, during: task),
        canStartRecording: !isRecording && AndroidRecordingActivity().canStart(on: device, during: task),
        canViewLayout: AndroidLayoutAvailability.canOpen(device: device, during: task),
        canChangeTestConditions: AndroidTestConditionsAvailability.canOpen(device: device, during: task)
      )
    )
  }
}
