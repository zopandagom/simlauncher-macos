import AndroidEmulatorInterface
import Core
import ScreenLayoutInterface

/// 플랫폼별 Client 를 조합하는 `ScreenLayoutClient`. Android 는 `AndroidEmulatorClient.layoutSnapshot` 에 맡기고
/// (그 Client 가 기기별로 한 번에 하나씩 읽는다), iOS 는 아직 `.unsupportedPlatform` 이다.
public struct ScreenLayoutClientImpl: ScreenLayoutClient {
  let androidEmulator: any AndroidEmulatorClient

  /// - Parameter androidEmulator: App 이 만든 하나뿐인 `AndroidEmulatorClientImpl` (기기별 읽기 차례를 함께 쓴다).
  public init(androidEmulator: any AndroidEmulatorClient) {
    self.androidEmulator = androidEmulator
  }

  /// Android: `.reading` 을 한 번 알린 뒤 AVD ID 로 읽는다.
  @concurrent
  public func snapshot(
    of target: LayoutTarget,
    onPhase: @escaping @Sendable (LayoutReadPhase) async -> Void
  ) async throws(ScreenLayoutError) -> LayoutSnapshot {
    switch target.platform {
    case .iOS:
      throw .unsupportedPlatform
    case .android:
      await onPhase(.reading)
      do throws(AndroidEmulatorError) {
        return try await self.androidEmulator.layoutSnapshot(on: AndroidVirtualDevice.ID(target.deviceID))
      } catch {
        throw ScreenLayoutError(error)
      }
    }
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
