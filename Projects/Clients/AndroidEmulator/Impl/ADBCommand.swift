import AndroidEmulatorInterface
import CommandInterface
import Core
import Foundation

/// adb 로 본 에뮬레이터 하나.
struct ADBEmulator: Hashable, Sendable {
  let serial: String
  let state: AndroidADBBootState
}

/// SDK 의 adb 실행과 출력 해석. 서버를 띄우는 경우를 위해 `ADB_MDNS=0`(LAN mDNS 탐색 끔)을 준다 (실측: 루프백 TCP 5037 만 연다).
/// 멈춘 서버에 막히지 않게 `runCancellable` 과 시간 제한으로 실행한다.
struct ADBCommand: Sendable {
  let command: any CommandClient
  let executable: URL
  let home: URL
  let timeout: Duration

  /// 환경 전체: `HOME`·`ADB_MDNS=0` 만.
  static func environment(home: URL) -> [String: String] {
    ["HOME": FileFacts.path(home), "ADB_MDNS": "0"]
  }

  /// AVD 이름 → 에뮬레이터. `adb devices` 가 실패하면 nil. `emu avd name` 이 실패한 serial 은 뺀다.
  /// `sys.boot_completed` 는 `names` 에 든 AVD 이면서 `device` 인 serial 만 묻는다.
  func emulators(names: Set<String>) async -> [String: ADBEmulator]? {
    guard let devices = try? await self.devices() else {
      return nil
    }
    var result: [String: ADBEmulator] = [:]
    for device in devices {
      guard let name = await self.avdName(serial: device.serial), names.contains(name) else {
        continue
      }
      let state: AndroidADBBootState = if !device.isOnline {
        .offline
      } else {
        await self.bootCompleted(serial: device.serial) ? .booted : .booting
      }
      result[name] = ADBEmulator(serial: device.serial, state: state)
    }
    return result
  }

  /// `adb devices` 의 에뮬레이터 serial.
  func devices() async throws(AndroidEmulatorError) -> [(serial: String, isOnline: Bool)] {
    let result = try await self.run(["devices"])
    guard result.exitCode == 0 else {
      throw .adbUnavailable
    }
    return Self.parseDevices(result.stdout)
  }

  /// `adb -s <serial> emu avd name`. 실패하면 nil.
  func avdName(serial: String) async -> String? {
    guard let result = try? await self.run(["-s", serial, "emu", "avd", "name"]), result.exitCode == 0 else {
      return nil
    }
    return Self.parseAVDName(result.stdout)
  }

  /// `adb -s <serial> shell getprop sys.boot_completed` 가 `1` 이다. 실패하면 false.
  func bootCompleted(serial: String) async -> Bool {
    guard
      let result = try? await self.run(["-s", serial, "shell", "getprop", "sys.boot_completed"]),
      result.exitCode == 0
    else {
      return false
    }
    return Self.parseBootCompleted(result.stdout)
  }

  /// `adb -s <serial> emu kill`. 실행 실패·0 이 아닌 종료 코드는 `.adbUnavailable`.
  func emuKill(serial: String) async throws(AndroidEmulatorError) {
    let result = try await self.run(["-s", serial, "emu", "kill"])
    guard result.exitCode == 0 else {
      throw .adbUnavailable
    }
  }

  private func run(_ arguments: [String]) async throws(AndroidEmulatorError) -> CommandResult {
    do throws(CommandError) {
      return try await self.command.runCancellable(
        self.executable,
        arguments,
        environment: Self.environment(home: self.home),
        timeout: self.timeout,
        onOutput: { _ in }
      )
    } catch {
      throw error == .cancelled ? .cancelled : .adbUnavailable
    }
  }

  // MARK: - 출력 해석

  /// `List of devices attached` 다음 줄마다 `<serial>\t<상태>`. 헤더·`* daemon …` 줄·빈 줄은 건너뛰고,
  /// `emulator-` 로 시작하는 serial 만 남긴다 (USB 기기는 보지 않는다). 상태가 `device` 면 online.
  static func parseDevices(_ data: Data) -> [(serial: String, isOnline: Bool)] {
    self.lines(data).compactMap { line in
      guard !line.hasPrefix("List of devices"), !line.hasPrefix("*") else {
        return nil
      }
      let fields = line.split(whereSeparator: { $0 == "\t" || $0 == " " })
      guard fields.count >= 2, fields[0].hasPrefix("emulator-") else {
        return nil
      }
      return (String(fields[0]), fields[1] == "device")
    }
  }

  /// `<이름>\r\nOK\r\n` → 이름. 뒤에 `OK` 줄이 없으면 nil (콘솔 오류 `KO: …` 등).
  static func parseAVDName(_ data: Data) -> String? {
    let lines = self.lines(data)
    guard lines.count >= 2, lines[1] == "OK", lines[0] != "OK", !lines[0].hasPrefix("KO") else {
      return nil
    }
    return lines[0]
  }

  /// `1\r\n` → true. 빈 값·그 밖은 false.
  static func parseBootCompleted(_ data: Data) -> Bool {
    String(bytes: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
  }

  /// 앞뒤 공백을 뺀 비지 않은 줄 (CRLF 포함).
  private static func lines(_ data: Data) -> [String] {
    guard let text = String(bytes: data, encoding: .utf8) else {
      return []
    }
    return text.split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }
}

/// SDK 의 emulator 띄우기 인자·환경.
enum EmulatorLaunch {
  /// 사용 통계와 크래시 보고를 끈다 (끌 수 없는 업데이트 확인·기능 플래그 접속은 ARCHITECTURE §4 네트워크 행).
  /// 이름은 `AndroidAVDName.isValid` 를 통과한 값만 넘긴다 (`-` 로 시작하지 않는다).
  static func arguments(name: String) -> [String] {
    ["-avd", name, "-no-metrics", "-crash-report-mode", "disabled"]
  }

  /// 환경 전체: `HOME` 과, 끄기 때 스냅샷 저장이 기본 20초를 넘겨 강제 종료되지 않게 하는 대기 시간(120초, 실측).
  static func environment(home: URL) -> [String: String] {
    ["HOME": FileFacts.path(home), "ANDROID_EMULATOR_WAIT_TIME_BEFORE_KILL": "120"]
  }
}
