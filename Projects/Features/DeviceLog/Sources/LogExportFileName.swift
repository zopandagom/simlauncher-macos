import Foundation

/// "저장…" 패널의 기본 파일 이름: `SimLauncher-<앱>-<기기>-<yyyyMMdd-HHmmss>.txt`.
/// 앱(Android 는 패키지 이름)·기기 이름은 사용자·앱이 정한 글자라 부분마다 정리한다:
/// 1. `/ : \ * ? " < > |`·제어 문자(Cc)·U+2028·U+2029·공백류는 `_` 로, 이어진 `_` 는 하나로.
/// 2. 앞뒤의 `.`·`_`·`-` 를 뗀다 (숨김 파일·`..` 방지).
/// 3. UTF-8 60바이트를 넘으면 글자(결합 문자 단위) 경계에서 자르고 2를 다시 한다.
/// 4. 비면 `App`·`Device` (번역하지 않는다).
/// 시각은 로컬 시간대(테스트는 고정)·`en_US_POSIX`·그레고리력. 머리말 "내보낸 시각" 과 같은 순간이다.
/// 전체는 많아야 153바이트라 APFS 이름 상한(255바이트) 아래다. 같은 이름이 있으면 저장 패널이 바꿀지 묻는다.
enum LogExportFileName {
  /// 앱·기기 부분 하나의 UTF-8 바이트 상한.
  static let partByteLimit = 60

  static func make(appName: String, deviceName: String, date: Date, timeZone: TimeZone) -> String {
    let app = self.part(appName, fallback: "App")
    let device = self.part(deviceName, fallback: "Device")
    return "SimLauncher-\(app)-\(device)-\(self.timestamp(date, timeZone: timeZone)).txt"
  }

  /// 파일 이름에 넣을 수 있게 정리한 부분.
  static func part(_ value: String, fallback: String) -> String {
    var replaced = String.UnicodeScalarView()
    for scalar in value.unicodeScalars {
      let next: Unicode.Scalar = self.isReplaced(scalar) ? "_" : scalar
      // 이어진 `_` 는 하나로.
      if next == "_", replaced.last == "_" {
        continue
      }
      replaced.append(next)
    }
    var result = self.trimmed(String(replaced))
    if result.utf8.count > self.partByteLimit {
      var cut = ""
      var bytes = 0
      for character in result {
        let size = character.utf8.count
        guard bytes + size <= self.partByteLimit else { break }
        cut.append(character)
        bytes += size
      }
      result = self.trimmed(cut)
    }
    return result.isEmpty ? fallback : result
  }

  static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: date)
  }

  private static let forbidden: Set<Unicode.Scalar> = ["/", ":", "\\", "*", "?", "\"", "<", ">", "|"]
  private static let trimmedCharacters = CharacterSet(charactersIn: "._-")

  private static func isReplaced(_ scalar: Unicode.Scalar) -> Bool {
    self.forbidden.contains(scalar) || LogExportText.breaksLine(scalar) || scalar.properties.isWhitespace
  }

  private static func trimmed(_ value: String) -> String {
    value.trimmingCharacters(in: self.trimmedCharacters)
  }
}
