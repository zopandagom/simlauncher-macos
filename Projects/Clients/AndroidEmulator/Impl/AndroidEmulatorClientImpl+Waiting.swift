import AndroidEmulatorInterface
import CommandInterface
import Core
import Foundation

// MARK: - 켜기·끄기 기다리기

extension AndroidEmulatorClientImpl {
  /// emulator 를 띄우고 표에 넣는다. 띄우기 전에 `adb devices` 를 한 번 불러(결과·실패는 무시) `~/.android/adbkey` 가 없으면
  /// adb 가 먼저 만들게 한다: emulator 는 키를 만들면 0777 로 바꾸고, adb 는 0600 으로 만든다(둘 다 있는 키는 그대로 둔다).
  /// 순서는 adb → 취소 확인 → 띄우기다. adb 호출 중 들어온 취소도 여기서 보고 띄우지 않는다.
  func launchEmulator(_ name: String, tools: SDKTools) async throws(AndroidEmulatorError) -> LaunchedProcess {
    _ = try? await self.adb(tools).devices()
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

  /// `searchSerial` 의 결과.
  enum SerialSearch: Equatable {
    case found(String)
    /// 잠금이 풀렸다 (이미 꺼짐).
    case released
    /// adb 는 답하는데 그 이름이 끝까지 없다. 앱 밖에서 끄는 중이면 저장이 끝날 때까지 콘솔이 이름에 답하지 않는다(실측).
    case unidentified
  }

  /// 끌 serial 을 `serialSearchLimit` 동안 `pollInterval` 마다 다시 찾는다 (앱 밖에서 막 켜 adb 에 아직 안 보이거나, 앱 밖에서 끄는 중).
  /// 그사이 잠금이 풀리면 `.released`. 끝까지 없으면 마지막 adb 목록이 성공했을 때 `.unidentified`, 실패했을 때 `.adbUnavailable`.
  func searchSerial(_ name: String, folder: URL?, adb: ADBCommand) async throws(AndroidEmulatorError) -> SerialSearch {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: self.timing.serialSearchLimit)
    while true {
      guard !Task.isCancelled else {
        throw .cancelled
      }
      let emulators = await adb.emulators(names: [name])
      if let serial = emulators?[name]?.serial {
        return .found(serial)
      }
      if folder.map({ AVDLock.isHeld(folder: $0) != true }) ?? true {
        return .released
      }
      guard clock.now < deadline else {
        // emulators 는 취소를 nil 로 삼키므로 adb 실패로 보기 전에 취소를 먼저 본다.
        guard !Task.isCancelled else {
          throw .cancelled
        }
        guard emulators != nil else {
          throw .adbUnavailable
        }
        return .unidentified
      }
      try await self.sleep(self.timing.pollInterval)
    }
  }

  /// `emu kill` 이 실패하고 이 앱이 띄운 프로세스가 없을 때, 앱 밖에서 끄는 중(또는 이미 꺼짐)으로 보고 기다려도 되는지.
  /// 잠금을 알 수 없으면(폴더 없음·`isHeld == nil`) false: 기다림은 잠금 풀림으로 끝을 판정하므로 확인 없이 성공하게 된다.
  /// 잠금이 확실히 풀렸으면(`isHeld == false`) true. 잡혀 있으면 adb 목록을 한 번 읽어 adb 가 답하는데 그 이름이 없으면 true,
  /// adb 가 답하지 않거나 그 기기가 이름에 답하면(끄는 중이 아닌데 `emu kill` 만 실패) false. 취소면 `.cancelled`.
  func externalShutdownInProgress(
    _ name: String,
    folder: URL?,
    adb: ADBCommand
  ) async throws(AndroidEmulatorError) -> Bool {
    guard let folder, let held = AVDLock.isHeld(folder: folder) else {
      return false
    }
    if !held {
      return true
    }
    let emulators = await adb.emulators(names: [name])
    guard !Task.isCancelled else {
      throw .cancelled
    }
    guard let emulators else {
      return false
    }
    return emulators[name] == nil
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
