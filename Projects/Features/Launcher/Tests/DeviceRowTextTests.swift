import Core
import Foundation
import SimulatorTesting
import Testing
@testable import LauncherFeature

/// 기기 행 ⋯ 메뉴의 묶음별 이유 줄과 항목별 활성 (`LauncherText.deviceMenu(_:)`). 입력의 활성 값은 행이 받는 것과 같은 규칙
/// (`ScreenshotActivity`·`RecordingActivity`·`InstalledAppsAvailability`·`IOSLayoutAvailability`·`TestConditionsAvailability`)으로
/// 만든다.
struct DeviceRowTextTests {
  // MARK: - 상태별

  @Test("꺼진 기기: 링크 열기만 되고(켜고 연다) 설치된 앱 이유 줄, 화면 묶음은 모두 막히고 켜진 기기 이유 줄, 초기화·삭제는 된다")
  func shutdown() {
    let menu = Self.menu(Self.device(state: .shutdown))

    #expect(menu.appReason == LauncherText.installedAppsBlockReason(.notBooted))
    #expect(!menu.canOpenInstalledApps)
    #expect(menu.canOpenURL)
    #expect(menu.screenReason == LauncherText.screenGroupBlockReason(.notBooted))
    #expect(!menu.canTakeScreenshot && !menu.canRecord && !menu.canViewLayout && !menu.canChangeTestConditions)
    #expect(menu.deviceReason == nil)
    #expect(menu.canErase && menu.canDelete)
  }

  @Test(
    "켜는 중·끄는 중·상태 모름: 앱 묶음은 상태가 바뀌는 중 이유로 함께 막히고, 화면 묶음과 초기화·삭제도 막힌다",
    arguments: [VirtualDevice.State.booting, .shuttingDown, .unknown]
  )
  func stateChanging(state: VirtualDevice.State) {
    let menu = Self.menu(Self.device(state: state))

    #expect(menu.appReason == LauncherText.appGroupBlockReason(.stateChanging))
    #expect(!menu.canOpenInstalledApps && !menu.canOpenURL)
    #expect(menu.screenReason == LauncherText.screenGroupBlockReason(.notBooted))
    #expect(!menu.canTakeScreenshot && !menu.canRecord && !menu.canViewLayout && !menu.canChangeTestConditions)
    #expect(menu.deviceReason == LauncherText.blockReason(.notShutdown))
    #expect(!menu.canErase && !menu.canDelete)
  }

  @Test("켜진 기기: 앱·화면 항목이 모두 되고 이유 줄이 없으며, 기기 묶음은 끈 뒤에 하라는 이유 줄과 함께 막힌다")
  func booted() {
    let menu = Self.menu(Self.device(state: .booted))

    #expect(menu.appReason == nil)
    #expect(menu.canOpenInstalledApps && menu.canOpenURL)
    #expect(menu.screenReason == nil)
    #expect(menu.canTakeScreenshot && menu.canRecord && menu.canViewLayout && menu.canChangeTestConditions)
    #expect(menu.deviceReason == LauncherText.blockReason(.notShutdown))
    #expect(!menu.canErase && !menu.canDelete)
  }

  @Test(
    "앱 설치·링크 열기·앱 실행 중: 스크린샷·녹화·레이아웃·테스트 조건은 되고, 설치된 앱·링크 열기·초기화·삭제는 이유 줄 없이 막힌다",
    arguments: [DeviceTask.installApp, .openURL, .launchApp]
  )
  func appTask(task: DeviceTask) {
    let menu = Self.menu(Self.device(state: .booted), task: task)

    #expect(menu.appReason == nil)
    #expect(!menu.canOpenInstalledApps && !menu.canOpenURL)
    #expect(menu.screenReason == nil)
    #expect(menu.canTakeScreenshot && menu.canRecord && menu.canViewLayout && menu.canChangeTestConditions)
    #expect(menu.deviceReason == nil)
    #expect(!menu.canErase && !menu.canDelete)
  }

  @Test("꺼진 기기에 설치하는 중(켜고 설치): 화면 묶음은 켜진 기기 이유 줄, 기기 묶음은 진행 표시가 이유라 줄 없이 막힌다")
  func installOnShutdownDevice() {
    let menu = Self.menu(Self.device(state: .shutdown), task: .installApp)

    #expect(menu.appReason == LauncherText.installedAppsBlockReason(.notBooted))
    #expect(!menu.canOpenInstalledApps && !menu.canOpenURL)
    #expect(menu.screenReason == LauncherText.screenGroupBlockReason(.notBooted))
    #expect(menu.deviceReason == nil)
    #expect(!menu.canErase && !menu.canDelete)
  }

  @Test("스크린샷 찍는 중: 스크린샷만 막히고 녹화·레이아웃·테스트 조건은 된다")
  func takingScreenshot() {
    let menu = Self.menu(Self.device(state: .booted), isTakingScreenshot: true)

    #expect(menu.screenReason == nil)
    #expect(!menu.canTakeScreenshot)
    #expect(menu.canRecord && menu.canViewLayout && menu.canChangeTestConditions)
    #expect(menu.canOpenInstalledApps && menu.canOpenURL)
  }

  @Test("녹화 중: 녹화·초기화·삭제가 막히고 기기 묶음 이유 줄은 녹화 이유다. 스크린샷·레이아웃·테스트 조건은 된다")
  func recording() {
    let menu = Self.menu(Self.device(state: .booted), isRecording: true)

    #expect(!menu.canRecord)
    #expect(menu.canTakeScreenshot && menu.canViewLayout && menu.canChangeTestConditions)
    #expect(menu.screenReason == nil)
    #expect(menu.deviceReason == LauncherText.recordingBlocksDeviceActions)
    #expect(!menu.canErase && !menu.canDelete)
  }

  @Test("녹화 중에 앱을 설치하는 중이어도 기기 묶음 이유 줄은 녹화 이유다")
  func recordingDuringAppTask() {
    let menu = Self.menu(Self.device(state: .booted), task: .installApp, isRecording: true)

    #expect(menu.deviceReason == LauncherText.recordingBlocksDeviceActions)
    #expect(!menu.canErase && !menu.canDelete)
  }

  @Test(
    "켜기·끄기·삭제·초기화 중: 모든 항목이 막히고, 화면·기기 묶음에 상태와 관계없는 이유 줄은 없다",
    arguments: [DeviceTask.boot, .shutdown, .delete, .erase]
  )
  func deviceTask(task: DeviceTask) {
    let menu = Self.menu(Self.device(state: .booted), task: task)

    #expect(!menu.canOpenInstalledApps && !menu.canOpenURL)
    #expect(!menu.canTakeScreenshot && !menu.canRecord && !menu.canViewLayout && !menu.canChangeTestConditions)
    #expect(!menu.canErase && !menu.canDelete)
    #expect(menu.appReason == nil)
    #expect(menu.screenReason == nil)
    #expect(menu.deviceReason == nil)
  }

  @Test("쓸 수 없는 꺼진 기기: 앱·화면 묶음은 쓸 수 없음 이유 줄과 함께 막히고, 초기화는 막히고 삭제만 된다")
  func unavailableShutdown() {
    let menu = Self.menu(Self.device(state: .shutdown, isAvailable: false))

    #expect(menu.appReason == LauncherText.appGroupBlockReason(.unavailable))
    #expect(!menu.canOpenInstalledApps && !menu.canOpenURL)
    #expect(menu.screenReason == LauncherText.screenGroupBlockReason(.unavailable))
    #expect(!menu.canTakeScreenshot && !menu.canRecord && !menu.canViewLayout && !menu.canChangeTestConditions)
    #expect(menu.deviceReason == LauncherText.blockReason(.unavailable))
    #expect(!menu.canErase)
    #expect(menu.canDelete)
  }

  @Test("쓸 수 없는 켜진 기기: 기기 묶음 이유 줄은 끈 뒤에 하라는 것이다 (삭제가 막힌 이유를 먼저)")
  func unavailableBooted() {
    let menu = Self.menu(Self.device(state: .booted, isAvailable: false))

    #expect(menu.appReason == LauncherText.appGroupBlockReason(.unavailable))
    #expect(menu.screenReason == LauncherText.screenGroupBlockReason(.unavailable))
    #expect(menu.deviceReason == LauncherText.blockReason(.notShutdown))
    #expect(!menu.canErase && !menu.canDelete)
  }

  @Test("러너 최소 iOS 보다 낮은 켜진 기기: 레이아웃 보기만 막히고 화면 묶음 이유 줄은 레이아웃 지원 iOS 안내다")
  func olderOS() {
    let menu = Self.menu(Self.device(state: .booted, runtime: Self.olderRuntime))

    #expect(menu.screenReason == LauncherText.layoutUnsupportedOS)
    #expect(!menu.canViewLayout)
    #expect(menu.canTakeScreenshot && menu.canRecord && menu.canChangeTestConditions)
    #expect(menu.appReason == nil)
    #expect(menu.canOpenInstalledApps && menu.canOpenURL)
  }

  @Test("러너보다 낮은 iOS 라도 꺼져 있으면 화면 묶음 이유 줄은 켜진 기기 안내다")
  func olderOSShutdown() {
    let menu = Self.menu(Self.device(state: .shutdown, runtime: Self.olderRuntime))

    #expect(menu.screenReason == LauncherText.screenGroupBlockReason(.notBooted))
  }

  // MARK: - 문구

  @Test("묶음 이유 문구는 케이스마다 다르고, 비어 있지 않은 한국어다")
  func groupReasonTexts() {
    let app = [AppInstallBlockReason.unavailable, .stateChanging].map { LauncherText.appGroupBlockReason($0) }
    let screen = [ScreenshotBlockReason.notBooted, .unavailable].map { LauncherText.screenGroupBlockReason($0) }

    #expect(Set(app).count == 2)
    #expect(Set(screen).count == 2)
    // 쓸 수 없는 기기는 두 묶음이 같은 문장이다.
    #expect(LauncherText.appGroupBlockReason(.unavailable) == LauncherText.screenGroupBlockReason(.unavailable))
    for text in app + screen {
      #expect(text.unicodeScalars.contains { (0xAC00 ... 0xD7A3).contains($0.value) }, "\(text)")
    }
  }

  // MARK: - 도우미

  private static let olderRuntime = DeviceRuntime(
    id: DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.iOS-16-4"),
    platform: .iOS,
    version: OSVersion(major: IOSLayoutRunner.minimumOSVersion.major - 1, minor: 4),
    name: "iOS 16.4",
    isAvailable: true,
    supportedDeviceTypeIDs: []
  )

  private static func device(
    state: VirtualDevice.State,
    isAvailable: Bool = true,
    runtime: DeviceRuntime = SampleRuntime.iOS27
  ) -> VirtualDevice {
    VirtualDevice(
      id: SampleID.iPhoneOn,
      name: "iPhone 17 Pro",
      family: .phone,
      state: state,
      availability: isAvailable ? .available : .unavailable(.runtimeNotInstalled),
      runtime: runtime
    )
  }

  /// 행이 받는 것과 같은 규칙으로 입력을 만들어 메뉴를 고른다.
  private static func menu(
    _ device: VirtualDevice,
    task: DeviceTask? = nil,
    isRecording: Bool = false,
    isTakingScreenshot: Bool = false
  ) -> DeviceRowMenu {
    LauncherText.deviceMenu(
      DeviceRowMenu.Input(
        device: device,
        isBusy: task != nil,
        isRecording: isRecording,
        isTakingScreenshot: isTakingScreenshot,
        canOpenInstalledApps: InstalledAppsAvailability.canOpen(device: device, during: task),
        canTakeScreenshot: !isTakingScreenshot && ScreenshotActivity().canStart(on: device, during: task),
        canStartRecording: !isRecording && RecordingActivity().canStart(on: device, during: task),
        canViewLayout: IOSLayoutAvailability.canOpen(device: device, during: task),
        canChangeTestConditions: TestConditionsAvailability.canOpen(device: device, during: task)
      )
    )
  }
}
