import AndroidEmulatorInterface
import CommandInterface
import Core
import Foundation
import Synchronization

// MARK: - 로그 받기와 함께 하는 앱 실행

public extension AndroidEmulatorClientImpl {
  /// 사전 확인 → 화면 찾기 → `am force-stop` → `date` → `am start -n` → pid 기다림 → (pid 있음) `.launched` 뒤 logcat 받기,
  /// (pid 없음) uid 줄 한 번 읽기. 시각은 force-stop **뒤에** 읽어 한 번 읽기에 앞 실행의 줄이 섞이지 않게 한다
  /// (`am start -S` 도 동기로 끄지만 끈 뒤 시각을 읽을 틈이 없어 쓰지 않는다).
  /// `.launched` 전의 취소는 던지지 않고 `.stopped` 다 (호출한 Task 가 취소된 뒤 나온 실패도 같다).
  @concurrent
  func launchWithLogcat(
    _ package: AndroidPackageName,
    on id: AndroidVirtualDevice.ID,
    onEvent: @escaping @Sendable (AndroidLogcatEvent) async -> Void
  ) async throws(AndroidEmulatorError) -> AndroidLogcatEnd {
    let launch: LogcatLaunch
    do throws(AndroidEmulatorError) {
      launch = try await self.startForLogcat(package, on: id)
    } catch {
      if error == .cancelled || Task.isCancelled {
        return .stopped
      }
      throw error
    }
    if let pid = launch.pid {
      await onEvent(.launched)
      return await self.streamLogcat(launch, pid: pid, onEvent: onEvent)
    }
    return await self.readExitedLaunch(launch, package: package, onEvent: onEvent)
  }
}

/// 실행까지 마친 결과.
struct LogcatLaunch: Sendable {
  let tools: SDKTools
  let serial: String
  /// force-stop 뒤 읽은 기기 시각 (`<초>.<밀리>`).
  let time: String
  /// 메인 프로세스 pid. nil 이면 기다리는 동안 보이지 않았다 (곧바로 끝남 또는 몹시 느린 기기).
  let pid: Int?
}

extension AndroidEmulatorClientImpl {
  /// `.launched` 전 단계. 실패는 지금 앱 작업과 같은 분류로 던진다.
  private func startForLogcat(
    _ package: AndroidPackageName,
    on id: AndroidVirtualDevice.ID
  ) async throws(AndroidEmulatorError) -> LogcatLaunch {
    let tools = try await SDKTools.resolve(self.sdkRoot())
    let serial = try await self.bootedSerial(id, tools: tools)
    let component = try await self.launcherComponent(package, serial: serial, tools: tools)
    let stopped = try await self.runApp(
      ADBLogcatCommands.forceStopArguments(serial: serial, package: package),
      tools: tools
    )
    try ADBLogcatCommands.parseForceStop(stopped).get()
    let time = try await ADBLogcatCommands.parseDeviceTime(
      self.runApp(ADBLogcatCommands.deviceTimeArguments(serial: serial), tools: tools)
    ).get()
    let started = try await self.runApp(
      ADBAppCommands.startArguments(serial: serial, component: component),
      tools: tools
    )
    try ADBAppCommands.parseStart(started).get()
    // 시간 한도를 넘으면 기본값 `.adbUnavailable` (기기 안 루프는 스스로 끝나므로 넘으면 adb 서버가 멈춘 것이다).
    let waited = try await self.runApp(
      ADBLogcatCommands.pidWaitArguments(serial: serial, package: package),
      tools: tools,
      timeout: self.timing.pidWaitTimeout
    )
    let pid = try ADBLogcatCommands.parsePID(waited).get()
    return LogcatLaunch(tools: tools, serial: serial, time: time, pid: pid)
  }

  /// 시간 제한 없이 `streamCancellable` 로 받는다 (stdout 은 쌓지 않는다). stdout 조각만 줄로 나눠 머리 줄을 빼고 넘긴다.
  /// 알림은 lock 밖에서 기다린다 (다음 조각은 앞 알림이 끝난 뒤). 멈춘(취소) 뒤 남은 조각은 넘기지 않는다.
  private func streamLogcat(
    _ launch: LogcatLaunch,
    pid: Int,
    onEvent: @escaping @Sendable (AndroidLogcatEvent) async -> Void
  ) async -> AndroidLogcatEnd {
    let splitter = LogcatSplitterBox()
    let result: StreamedCommandResult
    do throws(CommandError) {
      result = try await self.command.streamCancellable(
        launch.tools.adb,
        ADBLogcatCommands.streamArguments(serial: launch.serial, pid: pid, since: launch.time),
        environment: ADBCommand.environment(home: self.home)
      ) { output in
        guard case let .stdout(data) = output else { return }
        let texts = Self.logTexts(splitter.state.withLock { $0.feed(data) })
        if !texts.isEmpty {
          await onEvent(.lines(texts))
        }
      }
    } catch {
      switch error {
      case .cancelled: return .stopped
      // 이미 `.launched` 뒤라 던지지 않는다. 시간 제한을 주지 않아 `.timedOut` 은 오지 않는다.
      case .launchFailed, .timedOut: return .connectionLost
      }
    }
    let rest = Self.logTexts(splitter.state.withLock { $0.finish() })
    if !rest.isEmpty {
      await onEvent(.lines(rest))
    }
    return ADBLogcatCommands.end(exitCode: result.exitCode)
  }

  /// pid 전에 끝난 실행: 그 앱 uid 의 실행 뒤 줄을 한 번 읽어 `.launched`·줄 뒤 `.appExited`.
  /// uid·줄을 읽지 못하면 `.launched` 뒤 `.connectionLost`. 이 단계의 취소는 `.launched` 없이 `.stopped`.
  private func readExitedLaunch(
    _ launch: LogcatLaunch,
    package: AndroidPackageName,
    onEvent: @escaping @Sendable (AndroidLogcatEvent) async -> Void
  ) async -> AndroidLogcatEnd {
    let texts: [String]?
    do throws(AndroidEmulatorError) {
      texts = try await self.readUIDLog(launch, package: package)
    } catch {
      return .stopped
    }
    await onEvent(.launched)
    guard let texts else {
      return .connectionLost
    }
    if !texts.isEmpty {
      await onEvent(.lines(texts))
    }
    return .appExited
  }

  /// 읽은 줄(머리 줄 뺌), 읽지 못하면 nil. 던지는 것은 취소(`.cancelled`)뿐이다.
  private func readUIDLog(
    _ launch: LogcatLaunch,
    package: AndroidPackageName
  ) async throws(AndroidEmulatorError) -> [String]? {
    let listed: CommandResult
    do throws(AndroidEmulatorError) {
      listed = try await self.runApp(
        ADBLogcatCommands.uidArguments(serial: launch.serial, package: package),
        tools: launch.tools
      )
    } catch {
      if error == .cancelled {
        throw error
      }
      return nil
    }
    guard let uid = ADBLogcatCommands.parseUID(listed, package: package) else {
      return nil
    }
    let read: CommandResult
    do throws(AndroidEmulatorError) {
      read = try await self.runApp(
        ADBLogcatCommands.uidLogArguments(serial: launch.serial, uid: uid, since: launch.time),
        tools: launch.tools
      )
    } catch {
      if error == .cancelled {
        throw error
      }
      return nil
    }
    guard read.exitCode == 0 else {
      return nil
    }
    var splitter = ConsoleLineSplitter()
    return Self.logTexts(splitter.feed(read.stdout) + splitter.finish())
  }

  /// 머리 줄을 뺀 텍스트.
  private static func logTexts(_ lines: [ConsoleLineSplitter.Line]) -> [String] {
    lines.map(\.text).filter { !ADBLogcatCommands.isHeaderLine($0) }
  }
}

/// 줄 나누기 상태. 출력 전달 클로저(@Sendable)가 바꾸므로 lock 으로 감싼다.
private final class LogcatSplitterBox: Sendable {
  let state = Mutex(ConsoleLineSplitter())
}
