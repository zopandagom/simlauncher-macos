import Foundation

/// 스크린샷을 막는 이유.
public enum ScreenshotBlockReason: Hashable, Sendable {
  /// 쓸 수 없는 기기.
  case unavailable
  /// 켜져 있지 않다 (꺼짐·켜는 중·끄는 중·상태 모름).
  case notBooted
}

/// 그 기기의 화면을 지금 찍을 수 있는지.
public enum ScreenshotAvailability: Hashable, Sendable {
  case allowed
  case blocked(ScreenshotBlockReason)
}

public extension VirtualDevice {
  /// 쓸 수 없으면 blocked(.unavailable) (상태보다 먼저), `.booted` 면 allowed, 그 밖은 blocked(.notBooted).
  /// Model 가드와 View(버튼 비활성·이유)가 같은 규칙을 쓴다. 꺼진 기기는 켜지 않는다 (simctl 은 꺼진 기기에서 약 60초 뒤 실패한다).
  var screenshotAvailability: ScreenshotAvailability {
    if self.availability != .available {
      return .blocked(.unavailable)
    }
    switch self.state {
    case .booted: return .allowed
    case .shutdown, .booting, .shuttingDown, .unknown: return .blocked(.notBooted)
    }
  }
}

/// 스크린샷 파일 이름 (순수). "<기기 이름> (<런타임 이름>) <yyyy-MM-dd> <HH.mm.ss>.png",
/// 같은 이름이 있으면 확장자 앞에 " 2"…" 99". 저장 폴더 안의 파일 이름 한 단계만 만든다(경로 구분자 없음).
/// 기기 이름은 사용자·다른 도구가 붙인 임의 문자열이라, 저장 폴더 밖을 가리키거나 숨김 파일이 되지 않게 정리한다.
/// 기존 이름 목록은 읽지 않는다: 같은 이름 경쟁은 Workspace Client 가 독점 생성으로 예약해 푼다.
public struct ScreenshotFileName: Hashable, Sendable {
  /// 번호·확장자를 뺀 이름. 정리 규칙을 거친 값.
  public let stem: String
  public static let fileExtension = "png"
  /// 번호 없는 이름(1)부터 " 99" 까지.
  public static let maxAttempts = 99
  /// 기기 이름 부분의 UTF-8 상한. 번호 99 를 붙인 가장 긴 파일 이름도 APFS 이름 상한(255 바이트) 안이다.
  static let maxDeviceNameBytes = 120
  /// 런타임 이름 부분의 UTF-8 상한.
  static let maxRuntimeNameBytes = 40
  /// 정리한 기기 이름이 비었을 때 쓰는 이름.
  static let fallbackDeviceName = "Simulator"

  /// 시각은 `timeZone` 의 그레고리력 년·월·일·시·분·초로 읽는다 (로캘과 관계없이 24시간, 0 채움).
  /// 런타임 이름이 정리 뒤 비면 ` (…)` 부분을 뺀다.
  public init(deviceName: String, runtimeName: String, takenAt date: Date, timeZone: TimeZone) {
    let device = Self.sanitized(deviceName, maxUTF8Bytes: Self.maxDeviceNameBytes)
    let runtime = Self.sanitized(runtimeName, maxUTF8Bytes: Self.maxRuntimeNameBytes)
    let name = device.isEmpty ? Self.fallbackDeviceName : device
    let taken = Self.timestamp(date, timeZone: timeZone)
    self.stem = runtime.isEmpty ? "\(name) \(taken)" : "\(name) (\(runtime)) \(taken)"
  }

  /// attempt 1 → "<stem>.png", 2...maxAttempts → "<stem> <n>.png", 그 밖은 nil.
  public func fileName(attempt: Int) -> String? {
    switch attempt {
    case 1: "\(self.stem).\(Self.fileExtension)"
    case 2 ... Self.maxAttempts: "\(self.stem) \(attempt).\(Self.fileExtension)"
    default: nil
    }
  }

  /// `yyyy-MM-dd HH.mm.ss`. `:` 대신 `.` (macOS 스크린샷과 같은 관례, Finder 는 `:` 을 `/` 로 보인다).
  /// `DateFormatter` 는 로캘·사용자 설정(12시간제 등)을 따르므로 쓰지 않는다.
  static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    let day = [Self.padded(parts.year, 4), Self.padded(parts.month, 2), Self.padded(parts.day, 2)]
    let time = [Self.padded(parts.hour, 2), Self.padded(parts.minute, 2), Self.padded(parts.second, 2)]
    return "\(day.joined(separator: "-")) \(time.joined(separator: "."))"
  }

  /// 파일 이름 한 단계에 넣을 수 있게 정리한다. 순서:
  /// 1. 유니코드 스칼라 단위로 `/`·`:`·제어 문자(Cc, NUL·개행·탭·DEL 포함)·줄·문단 구분자(Zl·Zp)·방향 제어 문자를 `-` 로 바꾼다.
  ///    그 밖의 Cf(ZWJ·이모지 변형 선택자)는 그대로 둔다 (가족 이모지 같은 글자가 깨지지 않게).
  /// 2. 앞뒤 공백을 뺀다.
  /// 3. 맨 앞에 이어진 `.` 은 하나씩 `-` 로 바꾼다 (숨김 파일 방지. `.`·`..` 도 여기서 사라진다).
  ///    결합 문자가 붙은 `.` 도 스칼라로 보아 바꾼다.
  /// 4. UTF-8 바이트가 상한을 넘으면 넘지 않는 데까지 글자(Character) 단위로 앞에서부터 남기고(스칼라·글자 중간에서 자르지 않는다)
  ///    다시 뒤 공백을 뺀다.
  static func sanitized(_ raw: String, maxUTF8Bytes: Int) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in raw.unicodeScalars {
      scalars.append(Self.isReplaced(scalar) ? "-" : scalar)
    }
    var name = Self.trimmed(String(scalars))
    var leading = String.UnicodeScalarView()
    var inLeadingDots = true
    for scalar in name.unicodeScalars {
      if inLeadingDots, scalar == "." {
        leading.append("-")
      } else {
        inLeadingDots = false
        leading.append(scalar)
      }
    }
    name = String(leading)
    guard name.utf8.count > maxUTF8Bytes else {
      return name
    }
    var kept = ""
    var byteCount = 0
    for character in name {
      let size = character.utf8.count
      guard byteCount + size <= maxUTF8Bytes else { break }
      kept.append(character)
      byteCount += size
    }
    return Self.trimmed(kept)
  }

  /// 파일 이름에 넣지 않는 스칼라.
  private static func isReplaced(_ scalar: Unicode.Scalar) -> Bool {
    if scalar == "/" || scalar == ":" {
      return true
    }
    switch scalar.properties.generalCategory {
    case .control, .lineSeparator, .paragraphSeparator:
      return true
    default:
      return self.bidiControls.contains(scalar.value)
    }
  }

  /// 글자 순서를 바꿔 보이게 하는 방향 제어 문자: ALM, LRM·RLM, LRE~RLO, LRI~PDI.
  private static let bidiControls = Set<UInt32>([0x061C, 0x200E, 0x200F])
    .union(0x202A ... 0x202E)
    .union(0x2066 ... 0x2069)

  /// 앞뒤의 공백 글자(`Character.isWhitespace`)를 뺀다.
  private static func trimmed(_ text: String) -> String {
    guard let first = text.firstIndex(where: { !$0.isWhitespace }),
          let last = text.lastIndex(where: { !$0.isWhitespace })
    else { return "" }
    return String(text[first ... last])
  }

  private static func padded(_ value: Int?, _ width: Int) -> String {
    let digits = String(value ?? 0)
    return String(repeating: "0", count: max(0, width - digits.count)) + digits
  }
}
