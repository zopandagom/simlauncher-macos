import AndroidEmulatorInterface
import CommandInterface
import Core
import DevEnvironmentInterface
import Foundation
import ScreenLayoutInterface
import SimulatorInterface

/// 플랫폼별 Client 를 조합하는 `ScreenLayoutClient`. Android 는 `AndroidEmulatorClient.layoutSnapshot` 에 맡기고
/// (그 Client 가 기기별로 한 번에 하나씩 읽는다), iOS 는 SimLauncher 가 빌드해 띄운 XCUITest 러너로 읽는다
/// (Simulator·DevEnvironment·Command Client 조합, `IOSLayoutReader`·`LayoutRunnerPool`).
/// 러너 수명 알림(끄기 전후·목록 읽기·앱 종료)은 Interface 밖 공개 메서드로 App 이 잇는다.
public struct ScreenLayoutClientImpl: ScreenLayoutClient {
  let androidEmulator: any AndroidEmulatorClient
  let simulator: any SimulatorClient
  let iOSReader: IOSLayoutReader
  let pool: LayoutRunnerPool

  /// - Parameter androidEmulator: App 이 만든 하나뿐인 `AndroidEmulatorClientImpl` (기기별 읽기 차례를 함께 쓴다).
  /// - Parameter runnerDirectory: 러너 빌드 캐시·세션 폴더의 뿌리 (App 이 `~/Library/Caches/<번들 ID>/LayoutRunner` 를 준다).
  ///   생성자는 파일·명령을 건드리지 않는다.
  public init(
    androidEmulator: any AndroidEmulatorClient,
    simulator: any SimulatorClient,
    devEnvironment: any DevEnvironmentClient,
    command: any CommandClient,
    runnerDirectory: URL
  ) {
    self.init(
      androidEmulator: androidEmulator,
      simulator: simulator,
      devEnvironment: devEnvironment,
      command: command,
      runnerDirectory: runnerDirectory,
      timing: .standard,
      baseEnvironment: ProcessInfo.processInfo.environment
    )
  }

  /// 테스트용: 시간 값과 기본 환경을 정한다.
  init(
    androidEmulator: any AndroidEmulatorClient,
    simulator: any SimulatorClient,
    devEnvironment: any DevEnvironmentClient,
    command: any CommandClient,
    runnerDirectory: URL,
    timing: IOSLayoutTiming,
    baseEnvironment: [String: String]
  ) {
    self.androidEmulator = androidEmulator
    self.simulator = simulator
    let pool = LayoutRunnerPool(
      simulator: simulator,
      command: command,
      runnerDirectory: runnerDirectory,
      timing: timing,
      baseEnvironment: baseEnvironment
    )
    self.pool = pool
    self.iOSReader = IOSLayoutReader(
      simulator: simulator,
      devEnvironment: devEnvironment,
      pool: pool,
      queue: KeyedSerialQueue(),
      timing: timing
    )
  }

  /// Android: `.reading` 을 한 번 알린 뒤 AVD ID 로 읽는다.
  /// iOS: 러너를 새로 띄워야 하면(첫 사용, 러너가 멈춘 뒤 — 10분 유휴·기기 끄기나 다시 켜기·요청 시간 초과·러너 종료 — ,
  /// Xcode 교체 뒤) `.preparing` 뒤 `.reading`, 아니면 `.reading` 한 번.
  @concurrent
  public func snapshot(
    of target: LayoutTarget,
    onPhase: @escaping @Sendable (LayoutReadPhase) async -> Void
  ) async throws(ScreenLayoutError) -> LayoutSnapshot {
    switch target.platform {
    case .iOS:
      return try await self.iOSReader.read(VirtualDevice.ID(target.deviceID), onPhase: onPhase)
    case .android:
      await onPhase(.reading)
      do throws(AndroidEmulatorError) {
        return try await self.androidEmulator.layoutSnapshot(on: AndroidVirtualDevice.ID(target.deviceID))
      } catch {
        throw ScreenLayoutError(error)
      }
    }
  }

  /// iOS: 시뮬레이터 기기 목록(`simctl list`)에서 그 UDID 의 이름. 읽지 못하거나 없으면 nil. Android: nil.
  @concurrent
  public func deviceName(of target: LayoutTarget) async -> String? {
    guard target.platform == .iOS else { return nil }
    do throws(SimulatorError) {
      let inventory = try await self.simulator.fetchInventory()
      return inventory.devices.first { $0.id.rawValue == target.deviceID }?.name
    } catch {
      return nil
    }
  }

  // MARK: - iOS 러너 수명 (App 이 잇는다. Interface 밖)

  /// Launcher 의 "끄기" 직전: 그 기기를 "끄는 중" 으로 표시해(새 준비·정리를 받지 않는다) 러너를 멈추고 지운다.
  /// 상한: 준비됨이면 quit 2초 + SIGTERM 3초 + uninstall(보통 0.3초), 준비 중(띄운 뒤)이면 SIGTERM 3초 + uninstall,
  /// 빌드 대기 중·남은 러너 정리 중·러너 없음이면 곧바로 돌아온다.
  public func iOSDeviceWillShutDown(_ id: VirtualDevice.ID) async {
    await self.pool.willShutDown(id)
  }

  /// Launcher 의 "끄기" 가 끝난 뒤(성공·실패 모두): "끄는 중" 표시를 지운다.
  public func iOSDeviceDidShutDown(_ id: VirtualDevice.ID) async {
    await self.pool.didShutDown(id)
  }

  /// iOS 기기 목록을 읽을 때마다(Launcher): 켜진 기기 중 이번 켜짐에서 아직 정리하지 않았고 러너가 없는 기기의 남은 러너 앱을
  /// 백그라운드에서 지운다(기다리지 않는다). 목록에 켜진 것으로 없는 기기는 "정리함" 표시를 지워 다음 켜짐에 다시 정리한다.
  /// 부른 순서대로 처리한다: 동기로 순번을 붙여 비구조 Task 로 넘기고, 풀은 이미 처리한 순번보다 오래된 것을 버린다.
  public func iOSDevicesListed(booted: Set<VirtualDevice.ID>) {
    let pool = self.pool
    let sequence = pool.nextListedSequence()
    Task { await pool.devicesListed(booted, sequence: sequence) }
  }

  /// 모든 iOS 러너를 멈추고 지운다. 다 끝나거나 5초가 지나면 돌아온다(멈춤은 계속). 앱 종료 때.
  public func stopAllIOSRunners() async {
    await self.pool.stopAll()
  }

  /// 준비 중·준비됨·멈추는 중인 iOS 러너가 하나라도 있다 (동기). AppDelegate 가 종료 요청 때 본다.
  public var hasActiveIOSRunners: Bool {
    self.pool.hasActiveRunners
  }
}

extension ScreenLayoutError {
  /// Android 실패를 레이아웃 실패로 옮긴다. 레이아웃 읽기에서 나오지 않는 그 밖의 실패는 `.unreadable`.
  init(_ error: AndroidEmulatorError) {
    switch error {
    case .deviceNotFound: self = .deviceNotFound
    case .deviceUnavailable: self = .deviceUnavailable
    case .deviceNotBooted: self = .deviceNotBooted
    case .sdkUnavailable, .adbUnavailable: self = .toolsUnavailable
    case .cancelled: self = .cancelled
    default: self = Self.layoutFailure(error)
    }
  }

  /// 레이아웃 읽기에서 나오는 실패. 그 밖의 실패는 `.unreadable`.
  private static func layoutFailure(_ error: AndroidEmulatorError) -> ScreenLayoutError {
    switch error {
    case .layoutNotIdle: .screenNotIdle
    case .layoutDisplayOff: .displayOff
    case .layoutBusy: .automationBusy
    case .layoutTimedOut: .timedOut
    default: .unreadable
    }
  }
}
