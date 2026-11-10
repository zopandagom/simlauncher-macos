import AndroidEmulatorInterface
import CommandInterface
import Core
import Foundation

/// 켜진 기기의 화면 레이아웃 읽기 adb 인자와 결과 판정 (순수). 원격 명령은 고정 값이라 인용하지 않는다.
///
/// `uiautomator dump /dev/tty` 는 실패해도 종료 코드 0 이다(실측). 그래서 종료 코드가 아니라 stdout 의 `</hierarchy>` 로 성공을 가린다.
/// 덤프 뒤에는 `UI hierchary dumped to: /dev/tty` 가 붙으므로 첫 `</hierarchy>` 까지만 돌려준다. 파일로 덤프하지 않는다
/// (실패하면 이전 파일이 남아 오래된 화면을 읽을 수 있다).
enum ADBLayoutCommands {
  static let hierarchyEnd = Data("</hierarchy>".utf8)
  /// 화면이 계속 바뀌어 idle 을 기다리다 포기했다 (약 11초, 실측).
  static let notIdleMarker = "could not get idle state"
  /// 화면이 꺼져 있다 (약 2초, 실측).
  static let displayOffMarker = "null root node"
  /// 같은 기기에서 다른 uiautomator 가 돌고 있어 이 덤프가 죽었다 (뒤에 시작한 쪽이 죽는다, 실측).
  static let busyMarker = "Killed"
  /// 덤프 중 기기가 꺼지거나 끊겼을 때 adb 가 내는 문구 (종료 코드 ≠ 0 일 때만 본다).
  static let disconnectedMarkers = ["device offline", "not found", "no devices"]

  static func dumpArguments(serial: String) -> [String] {
    ["-s", serial, "exec-out", "uiautomator", "dump", "/dev/tty"]
  }

  static func densityArguments(serial: String) -> [String] {
    ["-s", serial, "exec-out", "wm", "density"]
  }

  /// `wm density` 출력의 밀도: `Override density: N` 줄이 있으면 그 값(앱이 실제로 쓰는 밀도), 없으면 `Physical density: N`.
  /// 양의 정수가 아니면 nil.
  static func parseDensity(_ stdout: Data) -> Int? {
    let text = String(bytes: stdout, encoding: .utf8) ?? ""
    var physical: Int?
    var override: Int?
    for line in text.split(whereSeparator: \.isNewline) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if let value = self.value(trimmed, prefix: "Override density:") {
        override = value
      } else if let value = self.value(trimmed, prefix: "Physical density:") {
        physical = value
      }
    }
    return override ?? physical
  }

  /// 종료 코드와 무관하게 stdout 에 `</hierarchy>` 가 있으면 그 끝까지의 XML. 없으면 출력 문구로 실패를 가른다:
  /// idle 실패 → `.layoutNotIdle`, null root → `.layoutDisplayOff`, 출력이 `Killed` 로 끝남 → `.layoutBusy`,
  /// 종료 코드 ≠ 0 이고 끊김 문구 → `.deviceNotBooted`, 그 밖 `.layoutUnreadable`.
  static func classifyDump(_ result: CommandResult) -> Result<Data, AndroidEmulatorError> {
    if let range = result.stdout.range(of: self.hierarchyEnd) {
      return .success(Data(result.stdout[result.stdout.startIndex ..< range.upperBound]))
    }
    let stdout = String(bytes: result.stdout, encoding: .utf8) ?? ""
    let stderr = String(bytes: result.stderr, encoding: .utf8) ?? ""
    let output = stdout + "\n" + stderr
    if output.contains(self.notIdleMarker) {
      return .failure(.layoutNotIdle)
    }
    if output.contains(self.displayOffMarker) {
      return .failure(.layoutDisplayOff)
    }
    if stdout.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(self.busyMarker)
      || stderr.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(self.busyMarker)
    {
      return .failure(.layoutBusy)
    }
    if result.exitCode != 0, self.disconnectedMarkers.contains(where: output.contains) {
      return .failure(.deviceNotBooted)
    }
    return .failure(.layoutUnreadable)
  }

  /// PNG IHDR 의 너비·높이 (16~24 바이트, big-endian). PNG 가 아니거나 짧거나 0 이면 nil.
  static func pngPixelSize(_ data: Data) -> LayoutSize? {
    guard ADBCaptureCommands.isPNG(data), data.count >= 24 else { return nil }
    let bytes = [UInt8](data.prefix(24))
    guard bytes[12 ..< 16].elementsEqual(Array("IHDR".utf8)) else { return nil }
    let width = bytes[16 ..< 20].reduce(0) { $0 << 8 | Int($1) }
    let height = bytes[20 ..< 24].reduce(0) { $0 << 8 | Int($1) }
    guard width > 0, height > 0 else { return nil }
    return LayoutSize(width: width, height: height)
  }

  private static func value(_ line: String, prefix: String) -> Int? {
    guard line.hasPrefix(prefix) else { return nil }
    let rest = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    guard let value = Int(rest), value > 0 else { return nil }
    return value
  }
}
