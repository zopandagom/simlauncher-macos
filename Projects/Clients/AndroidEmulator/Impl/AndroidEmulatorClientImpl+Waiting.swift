import AndroidEmulatorInterface
import CommandInterface
import Core
import Foundation

// MARK: - 켜기·끄기 기다리기

extension AndroidEmulatorClientImpl {
  /// emulator 를 띄우고 표에 넣는다. 띄우기 전에 취소됐으면 띄우지 않는다.
  func launchEmulator(_ name: String, tools: SDKTools) async throws(AndroidEmulatorError) -> LaunchedProcess {
    guard !Task.isCancelled else {
      throw .cancelled
    }
    do throws(CommandError) {
      let process = try await self.command.launch(
        tools.emulator,
        EmulatorLaunch.arguments(name: name),
        environment: EmulatorLaunch.environment(home: self.home)
      )
      self.launched.insert(process, for: name)
      return process
    } catch {
      throw .emulatorLaunchFailed
    }
  }

  /// `pollInterval` 마다 `sys.boot_completed=1` 을 확인한다. 이 앱이 띄운 프로세스가 끝나면 잠금을 한 번 더 보고, 다른 프로세스가
  /// 잡고 있으면(그사이 앱 밖에서 켬) 그 완료를 기다리고 아니면 `.emulatorExited(종료 상태)`. 띄우지 않고 기다리는 중 잠금이 풀리면
  /// `.emulatorExited(nil)`. `bootLimit` 이 지나면 `.bootTimedOut`, 취소면 `.cancelled` (둘 다 끄지 않는다).
  func waitForBoot(
    _ name: String,
    folder: URL,
    process: LaunchedProcess?,
    tools: SDKTools
  ) async throws(AndroidEmulatorError) {
    let adb = self.adb(tools)
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: self.timing.bootLimit)
    var process = process
    while true {
      guard !Task.isCancelled else {
        throw .cancelled
      }
      if let current = process, let status = self.command.exitStatus(current) {
        self.launched.remove(current, for: name)
        guard AVDLock.isHeld(folder: folder) == true else {
          throw .emulatorExited(status)
        }
        process = nil
      } else if process == nil, AVDLock.isHeld(folder: folder) != true {
        throw .emulatorExited(nil)
      }
      if await adb.emulators(names: [name])?[name]?.state == .booted {
        return
      }
      guard clock.now < deadline else {
        throw .bootTimedOut
      }
      try await self.sleep(self.timing.pollInterval)
    }
  }

  /// 끌 serial 을 `serialSearchLimit` 동안 `pollInterval` 마다 다시 찾는다 (앱 밖에서 막 켜 adb 에 아직 안 보이는 경우).
  /// 그사이 잠금이 풀리면 nil (이미 꺼짐). 끝까지 없으면 `.adbUnavailable`.
  func searchSerial(_ name: String, folder: URL?, adb: ADBCommand) async throws(AndroidEmulatorError) -> String? {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: self.timing.serialSearchLimit)
    while true {
      guard !Task.isCancelled else {
        throw .cancelled
      }
      if let serial = await adb.emulators(names: [name])?[name]?.serial {
        return serial
      }
      if folder.map({ AVDLock.isHeld(folder: $0) != true }) ?? true {
        return nil
      }
      guard clock.now < deadline else {
        throw .adbUnavailable
      }
      try await self.sleep(self.timing.pollInterval)
    }
  }

  /// 잠금이 풀리거나 이 앱이 띄운 프로세스가 끝날 때까지 `shutdownPollInterval` 마다 확인한다. `shutdownLimit` 이 지나면
  /// `.shutdownTimedOut`, 취소면 `.cancelled`.
  func waitForShutdown(
    _ name: String,
    folder: URL?,
    process: LaunchedProcess?
  ) async throws(AndroidEmulatorError) {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: self.timing.shutdownLimit)
    while true {
      guard !Task.isCancelled else {
        throw .cancelled
      }
      let lockReleased = folder.map { AVDLock.isHeld(folder: $0) != true } ?? true
      let processEnded = process.map { self.command.exitStatus($0) != nil } ?? false
      if lockReleased || processEnded {
        if let process, processEnded {
          self.launched.remove(process, for: name)
        }
        return
      }
      guard clock.now < deadline else {
        throw .shutdownTimedOut
      }
      try await self.sleep(self.timing.shutdownPollInterval)
    }
  }

  /// 취소되면 `.cancelled`.
  func sleep(_ duration: Duration) async throws(AndroidEmulatorError) {
    do {
      try await Task.sleep(for: duration)
    } catch {
      throw .cancelled
    }
  }
}
