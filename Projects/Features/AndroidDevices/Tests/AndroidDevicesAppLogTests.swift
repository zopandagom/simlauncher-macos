import AndroidEmulatorInterface
import AndroidEmulatorTesting
import AndroidPackageInterface
import AndroidPackageTesting
import AppLogInterface
import AppLogTesting
import Core
import Foundation
import Synchronization
import Testing
@testable import AndroidDevicesFeature

/// 앱 실행이 로그 받기와 함께 가는 경로(`AppLogClient.launchAndroidApp`)의 실패 되돌리기와, 행 "로그 보기" 를 누를 수 있는 기기
/// (`AndroidAppSheetsModel.logDevices`).
@MainActor
struct AndroidDevicesAppLogTests: AndroidDevicesTesting {
  static let tablet = AndroidVirtualDevice.bootedTabletSample
  static let label = AndroidDeviceLabel(.bootedTabletSample)
  static let apk = URL(filePath: "/Users/me/Downloads/app.apk", directoryHint: .notDirectory)
  static let info = AndroidPackageInfo.sample()

  /// AppLog 실행 실패 → 에뮬레이터 실행 실패 (흔한 실패는 같은 뜻으로 되돌리고, 그 밖은 앱 명령 실패).
  static let mapped: [(AppLogLaunchError, AndroidEmulatorError)] = [
    (.developerToolsUnavailable, .sdkUnavailable),
    (.deviceNotFound, .deviceNotFound),
    (.deviceUnavailable(.folderMissing), .deviceUnavailable(.folderMissing)),
    (.deviceNotBooted, .deviceNotBooted),
    (.appNotInstalled, .launchFailed(.notInstalled)),
    (.noLauncherActivity, .launchFailed(.noLauncherActivity)),
    (.adbUnavailable, .adbUnavailable),
    (.commandFailed, .appCommandFailed),
    (.appLaunchFailed, .appCommandFailed),
    (.sessionNotFound, .appCommandFailed),
  ]

  // MARK: - 실행 실패 되돌리기

  @Test("행 \"앱 실행…\" 의 실행 실패는 에뮬레이터 실행 실패로 되돌려 지금과 같은 알림이 된다")
  func launchFailureIsMappedBack() async throws {
    let package = try #require(AndroidPackageName("com.example.a"))
    for (error, expected) in Self.mapped {
      let setup = await Self.loadedFixture()
      setup.launchErrors.set(error)
      await setup.model.launchAppRequested(AndroidLaunchAppRequest(
        deviceID: Self.tablet.id,
        device: Self.label,
        package: package
      ))
      #expect(Self.notices(setup.model) == [.launchFailed(Self.label, .emulator(expected))], "\(error)")
      #expect(setup.appLog.sessions.isEmpty)
      #expect(Self.fetchCount(setup.fake) == 2)
    }
  }

  @Test("설치 뒤 실행 실패도 같은 표로 되돌려 \"설치는 됐다\" 알림이 된다")
  func launchAfterInstallFailureIsMappedBack() async {
    for (error, expected) in Self.mapped {
      let setup = await Self.loadedFixture()
      setup.launchErrors.set(error)
      await setup.model.appFileSelected(Self.apk, for: Self.tablet.id)
      #expect(Self.notices(setup.model) == [.installedButNotLaunched(Self.label, expected)], "\(error)")
    }
  }

  @Test("설치 후 실행은 패키지 이름을 앱 이름으로, 기기 표시 이름을 기기 이름으로 Android 세션을 만든다")
  func installedAppSession() async {
    let setup = await Self.loadedFixture()
    await setup.model.appFileSelected(Self.apk, for: Self.tablet.id)
    let session = setup.appLog.sessions.first
    #expect(setup.appLog.sessions.count == 1)
    #expect(session?.target == .android(Self.tablet.id))
    #expect(session?.appID == Self.info.packageName.rawValue)
    #expect(session?.appName == Self.info.packageName.rawValue)
    #expect(session?.deviceName == Self.label.name)
    #expect(session?.state == .receiving)
  }

  // MARK: - 행 "로그 보기"

  @Test("onAppear 전에는 구독하지 않고, 뒤에는 Android 대상 세션이 있는 기기만 logDevices 다 (iOS 세션은 무시)")
  func logDevicesFollowAndroidSessions() async {
    let iOSDevice = VirtualDevice.ID("A1B2C3")
    let appLog = CountingAppLog(sessions: [
      Self.summary(on: .android(Self.tablet.id), state: .ended(.appExited)),
      Self.summary(on: .iOS(iOSDevice), state: .receiving),
    ])
    let sheets = Self.sheets(appLog)
    await Self.settle()
    #expect(sheets.logDevices.isEmpty)
    #expect(appLog.subscriptionCount == 0)

    sheets.onAppear()
    await Self.waitUntil { sheets.logDevices == [Self.tablet.id] }

    let phone = AndroidVirtualDevice.phoneSample.id
    let receiving = Self.summary(on: .android(phone), state: .receiving)
    appLog.base.publish(receiving)
    // 같은 문자열의 iOS 기기 ID 는 Android 기기로 보지 않는다.
    let secondPhone = AndroidVirtualDevice.secondPhoneSample.id.rawValue
    appLog.base.publish(Self.summary(on: AppLogTarget(platform: .iOS, deviceID: secondPhone), state: .receiving))
    await Self.waitUntil { sheets.logDevices == [Self.tablet.id, phone] }

    appLog.base.remove(receiving.id)
    await Self.waitUntil { sheets.logDevices == [Self.tablet.id] }
  }

  @Test("onAppear 를 여러 번 불러도 구독은 하나다")
  func subscribesOnce() async {
    let appLog = CountingAppLog()
    let sheets = Self.sheets(appLog)
    sheets.onAppear()
    sheets.onAppear()
    sheets.onAppear()
    appLog.base.publish(Self.summary(on: .android(Self.tablet.id), state: .receiving))
    await Self.waitUntil { sheets.logDevices == [Self.tablet.id] }
    #expect(appLog.subscriptionCount == 1)
  }

  @Test("실행하면 그 기기에 세션이 생겨 행의 로그 보기를 누를 수 있다")
  func launchedAppShowsLog() async {
    let setup = await Self.loadedFixture()
    setup.sheets.onAppear()
    await setup.model.appFileSelected(Self.apk, for: Self.tablet.id)
    await Self.waitUntil { setup.sheets.logDevices == [Self.tablet.id] }
  }

  // MARK: - 도움

  static func sheets(_ appLog: any AppLogClient) -> AndroidAppSheetsModel {
    AndroidAppSheetsModel(
      emulator: AndroidEmulatorClientFake(inventory: .sample),
      appLog: appLog,
      target: { _, _ in nil }
    )
  }

  static func summary(on target: AppLogTarget, state: AppLogSessionState) -> AppLogSessionSummary {
    AppLogSessionSummary(
      id: AppLogSessionID(UUID()),
      target: target,
      deviceName: "기기",
      appID: "com.example.app",
      appName: "com.example.app",
      startedAt: Date(timeIntervalSince1970: 0),
      state: state
    )
  }
}

/// `sessionUpdates()` 를 부른 수를 세고 나머지는 `AppLogClientFake` 에 넘기는 `AppLogClient`.
final class CountingAppLog: AppLogClient {
  /// 넘겨받는 Fake (세션을 직접 넣을 때 쓴다).
  let base: AppLogClientFake
  private let subscriptions = Mutex(0)

  init(sessions: [AppLogSessionSummary] = []) {
    self.base = AppLogClientFake(sessions: sessions)
  }

  var subscriptionCount: Int {
    self.subscriptions.withLock { $0 }
  }

  func launchIOSApp(
    _ bundleID: AppBundleID,
    appName: String,
    on device: VirtualDevice.ID,
    deviceName: String
  ) async throws(AppLogLaunchError) -> AppLogSessionID {
    try await self.base.launchIOSApp(bundleID, appName: appName, on: device, deviceName: deviceName)
  }

  func launchAndroidApp(
    _ package: AndroidPackageName,
    appName: String,
    on device: AndroidVirtualDevice.ID,
    deviceName: String
  ) async throws(AppLogLaunchError) -> AppLogSessionID {
    try await self.base.launchAndroidApp(package, appName: appName, on: device, deviceName: deviceName)
  }

  func relaunch(_ session: AppLogSessionID) async throws(AppLogLaunchError) -> AppLogSessionID {
    try await self.base.relaunch(session)
  }

  func replacementWillStart(_ bundleID: AppBundleID, on device: VirtualDevice.ID) async {
    await self.base.replacementWillStart(bundleID, on: device)
  }

  func replacementCancelled(_ bundleID: AppBundleID, on device: VirtualDevice.ID) async {
    await self.base.replacementCancelled(bundleID, on: device)
  }

  func replacementWillStart(_ package: AndroidPackageName, on device: AndroidVirtualDevice.ID) async {
    await self.base.replacementWillStart(package, on: device)
  }

  func replacementCancelled(_ package: AndroidPackageName, on device: AndroidVirtualDevice.ID) async {
    await self.base.replacementCancelled(package, on: device)
  }

  func sessionUpdates() async -> AsyncStream<[AppLogSessionSummary]> {
    self.subscriptions.withLock { $0 += 1 }
    return await self.base.sessionUpdates()
  }

  func lineUpdates(of session: AppLogSessionID) async -> AsyncStream<AppLogLineUpdate> {
    await self.base.lineUpdates(of: session)
  }

  func stopAll() {
    self.base.stopAll()
  }
}
