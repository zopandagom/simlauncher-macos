import AppBundleInterface
import AppBundleTesting
import AppLogInterface
import AppLogTesting
import Core
import DownloadTesting
import Foundation
import SimulatorInterface
import SimulatorTesting
import Synchronization
import Testing
import WorkspaceTesting
@testable import LauncherFeature

@MainActor
struct LauncherLogTests: LauncherModelTesting {
  static let picked = URL(filePath: "/Users/tester/Downloads/My App.app", directoryHint: .isDirectory)
  static let sample = AppBundleInfo.sample

  // MARK: - 행의 "로그 보기"

  @Test("세션 요약 알림으로 logDevices 가 바뀌고, 끝난 세션만 있어도 누를 수 있으며, Android 대상은 무시한다")
  func logDevicesFollowSessionUpdates() async {
    let appLog = AppLogClientFake()
    let (model, _) = await Self.loadedModel(appLog: appLog)
    #expect(model.logDevices.isEmpty)

    let receiving = Self.summary(on: .iOS(SampleID.iPhoneOn), state: .receiving)
    appLog.publish(receiving)
    await Self.waitUntil { model.logDevices == [SampleID.iPhoneOn] }

    let ended = Self.summary(on: .iOS(SampleID.iPhoneOff), state: .ended(.deviceShutDown))
    appLog.publish(ended)
    appLog.publish(Self.summary(on: AppLogTarget(platform: .android, deviceID: "Pixel_9"), state: .receiving))
    await Self.waitUntil { model.logDevices == [SampleID.iPhoneOn, SampleID.iPhoneOff] }

    appLog.remove(receiving.id)
    await Self.waitUntil { model.logDevices == [SampleID.iPhoneOff] }
  }

  @Test("이미 세션이 있으면 첫 onAppear 뒤 곧바로 누를 수 있고, onAppear 를 여러 번 불러도 구독은 하나다")
  func existingSessionsAppearOnce() async {
    let simulator = SimulatorClientFake(inventory: .sample)
    let appLog = OrderRecordingAppLog(
      simulator: simulator,
      sessions: [Self.summary(on: .iOS(SampleID.iPhoneOn), state: .ended(.appExited))]
    )
    let model = Self.model(simulator: simulator, appLog: appLog)
    await model.onAppear()
    await Self.waitUntil { model.logDevices == [SampleID.iPhoneOn] }

    await model.onAppear()
    await model.onAppear()
    appLog.base.publish(Self.summary(on: .iOS(SampleID.iPhoneOff), state: .receiving))

    await Self.waitUntil { model.logDevices == [SampleID.iPhoneOn, SampleID.iPhoneOff] }
    #expect(appLog.sessionSubscriptionCount == 1)
  }

  @Test("설치 후 실행하면 그 기기에 세션이 생겨 행의 로그 보기를 누를 수 있다")
  func installedAppShowsLog() async {
    let appLog = AppLogClientFake()
    let (model, _) = await Self.loadedModel(appLog: appLog)

    await model.appFileSelected(Self.picked, for: SampleID.iPhoneOn)

    await Self.waitUntil { model.logDevices == [SampleID.iPhoneOn] }
    #expect(appLog.sessions.map(\.appName) == [Self.sample.displayName])
    #expect(appLog.sessions.map(\.appID) == [Self.sample.bundleID.rawValue])
  }

  // MARK: - 설치 흐름의 실행 단계

  @Test("설치 흐름은 다시 설치 알림 → 설치 → 로그 받기와 함께 실행 순서다")
  func installNotifiesReplacementThenLaunchesWithLog() async {
    let simulator = SimulatorClientFake(inventory: .sample)
    let appLog = OrderRecordingAppLog(simulator: simulator)
    let model = Self.model(simulator: simulator, appLog: appLog)
    await model.onAppear()

    await model.appFileSelected(Self.picked, for: SampleID.iPhoneOn)

    let install = SimulatorClientFake.Call.install(Self.sample.location, SampleID.iPhoneOn)
    #expect(appLog.records == [
      .init(call: .replacementWillStart(Self.sample.bundleID, SampleID.iPhoneOn), installed: false),
      .init(call: .launchIOSApp(Self.sample.bundleID, SampleID.iPhoneOn), installed: true),
    ])
    #expect(simulator.calls.contains(install))
    // 실행은 AppLog 로만 한다.
    #expect(!simulator.calls.contains(.launch(Self.sample.bundleID, SampleID.iPhoneOn)))
    #expect(simulator.calls.last == .fetchInventory)
    #expect(model.notices.isEmpty)
  }

  @Test("설치가 실패하면 다시 설치 알림을 되돌리고 실행하지 않는다")
  func installFailureCancelsReplacement() async {
    let appLog = AppLogClientFake()
    let (model, _) = await Self.loadedModel(appLog: appLog) { simulator in
      simulator.setInstallError(.appIncompatible)
    }

    await model.appFileSelected(Self.picked, for: SampleID.iPhoneOn)

    #expect(appLog.calls == [
      .replacementWillStart(Self.sample.bundleID, SampleID.iPhoneOn),
      .replacementCancelled(Self.sample.bundleID, SampleID.iPhoneOn),
    ])
    #expect(
      model.notices.map(\.notice) == [.installFailed(Self.label(SampleID.iPhoneOn), .simulator(.appIncompatible))]
    )
    #expect(model.logDevices.isEmpty)
  }

  @Test(
    "로그 받기와 함께 한 실행의 실패는 지금과 같은 실행 실패 알림이다",
    arguments: [
      (AppLogLaunchError.developerToolsUnavailable, SimulatorError.developerToolsUnavailable),
      (.deviceNotFound, .deviceNotFound), (.deviceNotBooted, .deviceNotBooted),
      (.appNotInstalled, .appNotInstalled), (.appLaunchFailed, .appLaunchFailed),
      (.commandFailed, .commandFailed), (.sessionNotFound, .commandFailed),
    ]
  )
  func launchFailureNotice(error: AppLogLaunchError, expected: SimulatorError) async {
    let appLog = AppLogClientFake { _, _ throws(AppLogLaunchError) in throw error }
    let (model, simulator) = await Self.loadedModel(appLog: appLog)

    await model.appFileSelected(Self.picked, for: SampleID.iPhoneOn)

    #expect(model.notices.map(\.notice) == [.launchFailed(Self.label(SampleID.iPhoneOn), expected)])
    #expect(appLog.calls.last == .launchIOSApp(Self.sample.bundleID, SampleID.iPhoneOn))
    #expect(simulator.calls.last == .fetchInventory)
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(model.logDevices.isEmpty)
  }

  // MARK: - 도움

  static func summary(on target: AppLogTarget, state: AppLogSessionState) -> AppLogSessionSummary {
    AppLogSessionSummary(
      id: AppLogSessionID(UUID()),
      target: target,
      deviceName: "iPhone",
      appID: "com.example.app",
      appName: "Example",
      startedAt: Date(timeIntervalSince1970: 0),
      state: state
    )
  }

  static func model(simulator: SimulatorClientFake, appLog: any AppLogClient) -> LauncherModel {
    LauncherModel(
      simulator: simulator,
      appBundle: AppBundleClientFake(),
      download: DownloadClientFake(),
      workspace: WorkspaceClientFake(),
      appLog: appLog
    )
  }
}

/// 호출마다 그때 Simulator Fake 가 설치를 받았는지 기록하는 `AppLogClient` (두 Fake 사이의 순서를 본다).
/// 나머지는 기본 `AppLogClientFake` 에 넘긴다.
final class OrderRecordingAppLog: AppLogClient {
  struct Record: Hashable, Sendable {
    let call: AppLogClientFake.Call
    /// 이 호출이 들어올 때 Simulator Fake 가 이미 설치를 받았다.
    let installed: Bool
  }

  private let simulator: SimulatorClientFake
  /// 넘겨받는 Fake (세션을 직접 넣을 때 쓴다).
  let base: AppLogClientFake
  private let log = Mutex<[Record]>([])
  private let subscriptions = Mutex(0)

  init(simulator: SimulatorClientFake, sessions: [AppLogSessionSummary] = []) {
    self.simulator = simulator
    self.base = AppLogClientFake(sessions: sessions)
  }

  var records: [Record] {
    self.log.withLock { $0 }
  }

  /// `sessionUpdates()` 를 부른 수.
  var sessionSubscriptionCount: Int {
    self.subscriptions.withLock { $0 }
  }

  private func record(_ call: AppLogClientFake.Call) {
    let installed = self.simulator.calls.contains {
      if case .install = $0 {
        true
      } else {
        false
      }
    }
    self.log.withLock { $0.append(Record(call: call, installed: installed)) }
  }

  func launchIOSApp(
    _ bundleID: AppBundleID,
    appName: String,
    on device: VirtualDevice.ID,
    deviceName: String
  ) async throws(AppLogLaunchError) -> AppLogSessionID {
    self.record(.launchIOSApp(bundleID, device))
    return try await self.base.launchIOSApp(bundleID, appName: appName, on: device, deviceName: deviceName)
  }

  func relaunch(_ session: AppLogSessionID) async throws(AppLogLaunchError) -> AppLogSessionID {
    self.record(.relaunch(session))
    return try await self.base.relaunch(session)
  }

  func replacementWillStart(_ bundleID: AppBundleID, on device: VirtualDevice.ID) async {
    self.record(.replacementWillStart(bundleID, device))
  }

  func replacementCancelled(_ bundleID: AppBundleID, on device: VirtualDevice.ID) async {
    self.record(.replacementCancelled(bundleID, device))
  }

  // Android 실행은 Launcher 에서 부르지 않는다. 프로토콜을 채우려고 기록만 하고 넘긴다.
  func launchAndroidApp(
    _ package: AndroidPackageName,
    appName: String,
    on device: AndroidVirtualDevice.ID,
    deviceName: String
  ) async throws(AppLogLaunchError) -> AppLogSessionID {
    self.record(.launchAndroidApp(package, device))
    return try await self.base.launchAndroidApp(package, appName: appName, on: device, deviceName: deviceName)
  }

  func replacementWillStart(_ package: AndroidPackageName, on device: AndroidVirtualDevice.ID) async {
    self.record(.androidReplacementWillStart(package, device))
  }

  func replacementCancelled(_ package: AndroidPackageName, on device: AndroidVirtualDevice.ID) async {
    self.record(.androidReplacementCancelled(package, device))
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
