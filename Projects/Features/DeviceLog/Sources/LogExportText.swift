import AppLogInterface
import Foundation

/// 내보낼 글 ("복사"·"저장…"): 머리말(화면 언어) + 구분선 + 보이는 줄(번호 순). 모든 줄은 `\n` 하나로 끝난다 (마지막 줄 포함).
/// 로그 줄은 신뢰하지 않는 텍스트라 바꾸지 않는다 (제어 문자·ANSI 이스케이프 그대로). 머리말 한 줄 구조를 지키려고
/// 앱·기기 이름·앱 버전의 제어 문자(Cc)·U+2028·U+2029 는 공백으로, 필터 조건 글자의 `\n`·`\r` 은 두 글자로, 그 밖의 제어 문자는
/// `\u{…}` 로 적는다. Mac 사용자 이름·홈 경로·저장 경로·기기 UDID 는 넣지 않는다.
/// 시각은 언어와 관계없이 `yyyy-MM-dd HH:mm:ss xxx` (예 `2026-11-17 13:49:05 +09:00`).
enum LogExportText {
  /// 머리말과 줄 사이 구분선 (번역하지 않는다).
  static let separator = String(repeating: "-", count: 40)
  /// Android 기기 OS 앞에 붙이는 고유 명사 (번역하지 않는다).
  static let androidAPIPrefix = "Android API "

  /// 글 전체. 줄 이어 붙이기는 메인 밖에서 한다 (33.7 MB·5만 줄 12.4ms, `-O` 측정).
  @concurrent
  nonisolated static func make(
    _ snapshot: LogExportSnapshot,
    bundle: Bundle = .module,
    timeZone: TimeZone
  ) async -> String {
    let header = self.header(snapshot, bundle: bundle, timeZone: timeZone)
    var capacity = self.separator.utf8.count + 1
    for line in header {
      capacity += line.utf8.count + 1
    }
    for line in snapshot.lines {
      capacity += line.line.text.utf8.count + 1
    }
    var text = ""
    text.reserveCapacity(capacity)
    for line in header {
      text += line
      text += "\n"
    }
    text += self.separator
    text += "\n"
    for line in snapshot.lines {
      text += line.line.text
      text += "\n"
    }
    return text
  }

  /// 머리말 줄들 (줄 끝 `\n` 없음). 순서는 고정이고, 앱 버전 줄은 iOS 세션에만, 버린·지운·일시정지 줄은 해당할 때만 있다.
  nonisolated static func header(_ snapshot: LogExportSnapshot, bundle: Bundle, timeZone: TimeZone) -> [String] {
    let session = snapshot.session
    let unknown = self.unknown(bundle: bundle)
    let version = snapshot.simLauncherVersion.map(self.singleLine) ?? unknown
    let exportedAt = self.timestamp(snapshot.exportedAt, timeZone: timeZone)
    let appName = self.singleLine(session.appName)
    let appID = self.singleLine(session.appID)
    var lines = [
      self.title(bundle: bundle),
      String(localized: "SimLauncher 버전: \(version)", bundle: bundle),
      String(localized: "내보낸 시각: \(exportedAt)", bundle: bundle),
      String(localized: "앱: \(appName) (\(appID))", bundle: bundle),
    ]
    if session.target.platform == .iOS {
      let appVersion = session.appVersion.flatMap(self.appVersion) ?? unknown
      lines.append(String(localized: "앱 버전: \(appVersion)", bundle: bundle))
    }
    let device = self.device(session)
    let startedAt = self.timestamp(session.startedAt, timeZone: timeZone)
    let state = DeviceLogText.state(session.state, platform: session.target.platform, bundle: bundle)
    lines += [
      String(localized: "기기: \(device)", bundle: bundle),
      String(localized: "실행 시각: \(startedAt)", bundle: bundle),
      String(localized: "상태: \(state)", bundle: bundle),
    ]
    lines += self.filter(snapshot.filter, bundle: bundle)
    let counts = DeviceLogText.lineCounts(visible: snapshot.visibleCount, total: snapshot.totalCount, bundle: bundle)
    lines.append(String(localized: "줄: \(counts)", bundle: bundle))
    if let discarded = snapshot.discarded {
      lines.append(DeviceLogText.discarded(discarded, bundle: bundle))
    }
    if snapshot.hasCleared {
      lines.append(self.clearedNotice(bundle: bundle))
    }
    if snapshot.isPaused {
      lines.append(self.pausedNotice(newLines: snapshot.newWhilePaused, bundle: bundle))
    }
    return lines
  }

  nonisolated static func title(bundle: Bundle) -> String {
    String(localized: "SimLauncher 앱 로그", bundle: bundle)
  }

  nonisolated static func unknown(bundle: Bundle) -> String {
    String(localized: "알 수 없음", bundle: bundle)
  }

  nonisolated static func clearedNotice(bundle: Bundle) -> String {
    String(localized: "이 창에서 지운 줄은 빠졌습니다", bundle: bundle)
  }

  /// 일시정지 줄. 멈춘 뒤 받은 줄이 없으면 개수를 말하지 않는다.
  nonisolated static func pausedNotice(newLines: Int, bundle: Bundle) -> String {
    newLines == 0
      ? String(localized: "일시정지 중: 멈춘 지점까지의 줄입니다", bundle: bundle)
      : String(localized: "일시정지 중: 멈춘 지점까지의 줄입니다. 멈춘 뒤 받은 \(newLines)줄은 빠졌습니다", bundle: bundle)
  }

  /// 필터 줄: 글자가 있는 조건이 없으면 "없음" 한 줄, 있으면 대소문자 머리 줄과 조건 줄 (화면 순서, 빈 조건은 뺀다).
  nonisolated static func filter(_ filter: LogFilter, bundle: Bundle) -> [String] {
    let conditions = filter.conditions.filter { !$0.text.isEmpty }
    guard !conditions.isEmpty else {
      return [self.noFilter(bundle: bundle)]
    }
    var lines = [self.filterHeader(isCaseSensitive: filter.isCaseSensitive, bundle: bundle)]
    for condition in conditions {
      let kind = DeviceLogText.kind(condition.kind, bundle: bundle)
      let text = self.escapedCondition(condition.text)
      // 포함 조건은 맞추는 방법만 적는다 ("포함 · 포함" 처럼 같은 말이 겹치지 않게. 화면도 제외만 체크상자로 표시한다).
      lines.append(
        condition.isExcluded
          ? String(localized: "- 제외 · \(kind): \(text)", bundle: bundle)
          : "- \(kind): \(text)"
      )
    }
    return lines
  }

  nonisolated static func noFilter(bundle: Bundle) -> String {
    String(localized: "필터: 없음", bundle: bundle)
  }

  nonisolated static func filterHeader(isCaseSensitive: Bool, bundle: Bundle) -> String {
    isCaseSensitive
      ? String(localized: "필터 (대소문자 구분):", bundle: bundle)
      : String(localized: "필터 (대소문자 무시):", bundle: bundle)
  }

  /// "1.2 (34)" / "1.2" / "(34)". 둘 다 없으면 nil.
  nonisolated static func appVersion(_ version: AppLogAppVersion) -> String? {
    let short = version.version.map(self.singleLine).flatMap { $0.isEmpty ? nil : $0 }
    let build = version.build.map(self.singleLine).flatMap { $0.isEmpty ? nil : $0 }
    switch (short, build) {
    case let (short?, build?): return "\(short) (\(build))"
    case let (short?, nil): return short
    case let (nil, build?): return "(\(build))"
    case (nil, nil): return nil
    }
  }

  /// "iPhone 17 Pro · iOS 27.0" / "Pixel 9 · Android API 37.0". OS 를 모르면 기기 이름만.
  nonisolated static func device(_ session: AppLogSessionSummary) -> String {
    let name = self.singleLine(session.deviceName)
    switch session.deviceOS {
    case let .iOS(runtimeName): return "\(name) · \(self.singleLine(runtimeName))"
    case let .android(apiLabel): return "\(name) · \(self.androidAPIPrefix)\(self.singleLine(apiLabel))"
    case nil: return name
    }
  }

  nonisolated static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss xxx"
    return formatter.string(from: date)
  }

  /// 한 줄 값: 제어 문자(Cc, U+0085 포함)·U+2028·U+2029 를 공백 하나로.
  nonisolated static func singleLine(_ value: String) -> String {
    var result = String.UnicodeScalarView()
    for scalar in value.unicodeScalars {
      result.append(self.breaksLine(scalar) ? " " : scalar)
    }
    return String(result)
  }

  /// 조건 글자: `\n`·`\r` 은 두 글자로, 그 밖의 제어 문자·U+2028·U+2029 는 `\u{XXXX}` 로 적는다 (어떤 글자를 찾았는지 남긴다).
  nonisolated static func escapedCondition(_ value: String) -> String {
    var result = ""
    for scalar in value.unicodeScalars {
      switch scalar {
      case "\n": result += "\\n"
      case "\r": result += "\\r"
      case _ where self.breaksLine(scalar):
        result += "\\u{" + String(format: "%04X", scalar.value) + "}"
      default: result.unicodeScalars.append(scalar)
      }
    }
    return result
  }

  /// 머리말 한 줄 구조를 깨거나 보이지 않는 글자: 제어 문자(Cc)·줄 구분자 U+2028·문단 구분자 U+2029.
  nonisolated static func breaksLine(_ scalar: Unicode.Scalar) -> Bool {
    scalar.properties.generalCategory == .control || scalar.value == 0x2028 || scalar.value == 0x2029
  }
}
