import AndroidEmulatorInterface
import CommandInterface
import Core
import Foundation

// MARK: - 켜진 기기의 화면 레이아웃

public extension AndroidEmulatorClientImpl {
  /// 기기별 차례(`LayoutReadQueue`) 안에서 `readLayout`.
  @concurrent
  func layoutSnapshot(on id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) -> LayoutSnapshot {
    try await self.layoutQueue.run(id) { () async throws(AndroidEmulatorError) -> LayoutSnapshot in
      try await self.readLayout(id)
    }
  }

  /// SDK 확인 → 켜진 기기(serial·표시 이름) → 밀도(실패해도 nil) → 덤프 → 판정·해석 → 스크린샷 → PNG 크기.
  /// 덤프가 idle 을 기다리므로 덤프 뒤 곧바로 찍는다 (덤프와 스크린샷 사이 약 0.1초에 회전·접기가 바뀌면 어긋난다. 새로 고침으로 회복).
  @concurrent
  internal func readLayout(_ id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) -> LayoutSnapshot {
    let tools = try await SDKTools.resolve(self.sdkRoot())
    let (serial, device) = try await self.bootedDevice(id, tools: tools)
    let density = try await self.layoutDensity(serial: serial, tools: tools)
    let dump = try await self.runApp(
      ADBLayoutCommands.dumpArguments(serial: serial),
      tools: tools,
      timeout: self.timing.layoutDumpTimeout,
      timedOut: .layoutTimedOut
    )
    let parsed = try UIAutomatorDumpParser.parse(ADBLayoutCommands.classifyDump(dump).get())
    let screenshot = try await self.runApp(
      ADBCaptureCommands.screenshotArguments(serial: serial),
      tools: tools,
      timeout: self.timing.screenshotTimeout,
      timedOut: .captureFailed
    )
    guard screenshot.exitCode == 0, let size = ADBLayoutCommands.pngPixelSize(screenshot.stdout) else {
      throw .captureFailed
    }
    return LayoutSnapshot(
      deviceName: device.displayName,
      capturedAt: Date(),
      screenshotPNG: screenshot.stdout,
      pixelSize: size,
      unit: .dp,
      pixelsPerUnit: density.map { Double($0) / 160 },
      nodes: parsed.nodes,
      appIdentifier: parsed.appIdentifier,
      isSystemScreen: parsed.isSystemScreen
    )
  }

  /// `wm density` 의 밀도. 실패(시간 초과·adb 실패·종료 코드 ≠ 0·해석 실패)는 nil 이고, 취소만 던진다.
  private func layoutDensity(serial: String, tools: SDKTools) async throws(AndroidEmulatorError) -> Int? {
    do throws(AndroidEmulatorError) {
      let result = try await self.runApp(ADBLayoutCommands.densityArguments(serial: serial), tools: tools)
      guard result.exitCode == 0 else { return nil }
      return ADBLayoutCommands.parseDensity(result.stdout)
    } catch {
      if error == .cancelled {
        throw .cancelled
      }
      return nil
    }
  }
}
