import AndroidEmulatorInterface
import CommandInterface
import Core
import Foundation

// MARK: - 켜진 기기의 앱 작업

public extension AndroidEmulatorClientImpl {
  @concurrent
  func deviceTraits(_ id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) -> AndroidDeviceTraits {
    let tools = try await SDKTools.resolve(self.sdkRoot())
    let serial = try await self.bootedSerial(id, tools: tools)
    let arguments = ADBAppCommands.traitsArguments(serial: serial)
    let apiLevel = try await ADBAppCommands.parseAPILevel(self.runApp(arguments.apiLevel, tools: tools)).get()
    let abis = try await ADBAppCommands.parseABIs(self.runApp(arguments.abis, tools: tools)).get()
    return AndroidDeviceTraits(apiLevel: apiLevel, abis: abis)
  }

  /// 시간 한도는 `installTimeout` (넘으면 `.installTimedOut`).
  @concurrent
  func install(_ apk: URL, on id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) {
    let tools = try await SDKTools.resolve(self.sdkRoot())
    let serial = try await self.bootedSerial(id, tools: tools)
    let result = try await self.runApp(
      ADBAppCommands.installArguments(serial: serial, apk: apk),
      tools: tools,
      timeout: self.timing.installTimeout,
      timedOut: .installTimedOut
    )
    try ADBAppCommands.parseInstall(result).get()
  }

  /// resolve → 화면이 있으면 `am start -n`. 기기가 하나로 고르지 못하면(launcher 가 둘 이상) `query-activities` 의 첫 화면을 띄운다.
  /// 화면이 없으면(질의 사이에 지워진 경우 포함) `pm path` 로 설치 여부를 가린다.
  @concurrent
  func launch(_ package: AndroidPackageName, on id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) {
    let tools = try await SDKTools.resolve(self.sdkRoot())
    let serial = try await self.bootedSerial(id, tools: tools)
    let resolved = try await self.runApp(
      ADBAppCommands.resolveArguments(serial: serial, package: package),
      tools: tools
    )
    let component: String?
    switch try ADBAppCommands.parseResolve(resolved, package: package).get() {
    case let .component(found):
      component = found
    case .none:
      component = nil
    case .ambiguous:
      let launchers = try await self.runApp(
        ADBAppCommands.launchersArguments(serial: serial, package: package),
        tools: tools
      )
      component = try ADBAppCommands.parseLaunchers(launchers, package: package).get().first
    }
    guard let component else {
      let path = try await self.runApp(
        ADBAppCommands.packagePathArguments(serial: serial, package: package),
        tools: tools
      )
      let installed = try ADBAppCommands.parsePackagePath(path).get()
      throw .launchFailed(installed ? .noLauncherActivity : .notInstalled)
    }
    let started = try await self.runApp(
      ADBAppCommands.startArguments(serial: serial, component: component),
      tools: tools
    )
    try ADBAppCommands.parseStart(started).get()
  }

  @concurrent
  func openURL(_ link: DeepLink, on id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) {
    let tools = try await SDKTools.resolve(self.sdkRoot())
    let serial = try await self.bootedSerial(id, tools: tools)
    let result = try await self.runApp(ADBAppCommands.openURLArguments(serial: serial, link: link), tools: tools)
    try ADBAppCommands.parseStart(result).get()
  }

  @concurrent
  func installedPackages(on id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError)
    -> [AndroidPackageName]
  {
    let tools = try await SDKTools.resolve(self.sdkRoot())
    let serial = try await self.bootedSerial(id, tools: tools)
    let result = try await self.runApp(ADBAppCommands.listPackagesArguments(serial: serial), tools: tools)
    return try ADBAppCommands.parsePackages(result).get()
  }

  /// 다시 읽기 → 쓸 수 없으면 `.deviceUnavailable` → adb 로 본 상태가 켜짐이면 serial. 잠금만으로 켜짐이 된 경우(adb 가 답하지 않음)는
  /// `.adbUnavailable`, 그 밖(꺼짐·켜는 중·잠금은 있는데 adb 에 아직 없음)은 `.deviceNotBooted`.
  internal func bootedSerial(
    _ id: AndroidVirtualDevice.ID,
    tools: SDKTools
  ) async throws(AndroidEmulatorError) -> String {
    let target = try await self.read(id, tools: tools)
    if case let .unavailable(reason) = target.device.availability {
      throw .deviceUnavailable(reason)
    }
    if let emulator = target.emulator, emulator.state == .booted {
      return emulator.serial
    }
    // 잠금이 있는데 adb 로 찾지 못한 기기는 adb 실패면 켜짐(잠금만), adb 가 답했으면 켜는 중으로 판정된다 (`AndroidDeviceJudge.state`).
    if target.facts.lockHeld == true, target.emulator == nil, target.device.state == .booted {
      throw .adbUnavailable
    }
    throw .deviceNotBooted
  }

  /// adb 앱 명령 하나 (`ADBCommand` 와 같은 환경). 시작 실패는 `.adbUnavailable`, 취소는 `.cancelled`, 시간 초과는 `timedOut`.
  /// 화면 캡처(`+Capture`)도 쓴다.
  internal func runApp(
    _ arguments: [String],
    tools: SDKTools,
    timeout: Duration? = nil,
    timedOut: AndroidEmulatorError = .adbUnavailable
  ) async throws(AndroidEmulatorError) -> CommandResult {
    do throws(CommandError) {
      return try await self.command.runCancellable(
        tools.adb,
        arguments,
        environment: ADBCommand.environment(home: self.home),
        timeout: timeout ?? self.timing.adbTimeout,
        onOutput: { _ in }
      )
    } catch {
      switch error {
      case .cancelled: throw .cancelled
      case .timedOut: throw timedOut
      case .launchFailed: throw .adbUnavailable
      }
    }
  }
}
