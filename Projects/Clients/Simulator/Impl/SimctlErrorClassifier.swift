import SimulatorInterface

/// 실패한 명령의 종료 코드·stderr 를 `SimulatorError` 로 바꾼다 (순수). 원문은 담지 않는다.
/// install·launch·openurl·screenshot 은 stderr 에 앱이 정한 글자(표시 이름)나 사용자가 넣은 URL 이 섞이므로
/// "(domain=…, code=…)" 줄의 domain·code 로만 분류한다 (screenshot 은 경로의 기기 이름도 섞인다).
enum SimctlErrorClassifier {
  private static let domainLinePrefix = "An error was encountered processing the command (domain="
  private static let denialLinePrefix = "The request was denied by service delegate ("

  static func error(exitCode: Int32, stderr: String) -> SimulatorError {
    // xcrun 자신의 오류(simctl 없음, DEVELOPER_DIR 경로 없음 등). 종료 코드는 72·1 등 여러 가지라 보지 않는다.
    // simctl 자체 오류("Invalid device…", "An error was encountered…")는 이 접두어로 시작하지 않는다.
    if stderr.drop(while: \.isWhitespace).hasPrefix("xcrun: error:") {
      return .developerToolsUnavailable
    }
    // 만들 수 없는 조합: "Invalid device type: …"(146)·"Invalid runtime: …"(145)·"… Incompatible device"(147).
    // "Invalid device type" 은 "Invalid device" 를 포함하므로 반드시 아래 검사보다 먼저 본다.
    if ["Invalid device type", "Invalid runtime", "Incompatible device"].contains(where: stderr.contains) {
      return .creationOptionUnavailable
    }
    // 없는 기기: boot 는 "Invalid device or device pair: …", shutdown·erase·delete 는 "Invalid device: …" (종료 코드 148).
    if stderr.contains("Invalid device") {
      return .deviceNotFound
    }
    // "Unable to … in current state" (149) 도 여기 든다. boot·shutdown 은 그 전에 재조회로 성공 여부를 판정하고,
    // erase 는 사전 확인 뒤 상태가 바뀐 드문 경우에만 이 실패를 받는다. usage 출력(117)도 여기 든다.
    return .commandFailed
  }

  /// stderr 를 줄로 나눠 "An error was encountered processing the command (domain=D, code=N):" 로 **시작하는 첫 줄**의 D·N.
  /// 없으면 nil. 앞에 경고 줄이 붙어도 찾고, 앱이 정한 글자(표시 이름)는 이 줄 뒤에만 나오므로 그 글자로 만든 가짜 줄보다 먼저 찾는다.
  static func domainAndCode(_ stderr: String) -> (domain: String, code: Int)? {
    for line in stderr.split(whereSeparator: \.isNewline) {
      guard line.hasPrefix(self.domainLinePrefix) else { continue }
      let rest = line.dropFirst(Self.domainLinePrefix.count)
      guard
        let separator = rest.range(of: ", code="),
        case let afterCode = rest[separator.upperBound...],
        let close = afterCode.range(of: "):"),
        let code = Int(afterCode[..<close.lowerBound])
      else { return nil }
      return (String(rest[..<separator.lowerBound]), code)
    }
    return nil
  }

  /// FBS 거절 이유. domain 줄 **다음 줄부터** 앞 공백 없이 "The request was denied by service delegate (" 로 시작하는 첫 줄에서
  /// ") for reason: " 뒤부터 다음 " (" 또는 줄 끝 앞까지. 없으면 nil. (순수)
  /// reason 토큰은 거절 줄의 정해진 자리에서만 읽는다: 앱 글자가 들어갈 수 있는 뒤의 괄호 설명보다 앞이고,
  /// 앞 줄의 앱 제공 값은 형식 검사한 번들 ID 뿐이라 이 접두어로 시작하는 줄을 만들 수 없다.
  static func denialReason(_ stderr: String) -> Substring? {
    let lines = stderr.split(whereSeparator: \.isNewline)
    guard let domainLine = lines.firstIndex(where: { $0.hasPrefix(Self.domainLinePrefix) }) else { return nil }
    guard
      let line = lines[(domainLine + 1)...].first(where: { $0.hasPrefix(Self.denialLinePrefix) }),
      let marker = line.range(of: ") for reason: ")
    else { return nil }
    let rest = line[marker.upperBound...]
    return rest.range(of: " (").map { rest[..<$0.lowerBound] } ?? rest
  }

  /// install 실패. domain 줄이 있으면 그것만 보고, 없으면 `error(exitCode:stderr:)` (xcrun 오류·"Invalid device").
  static func installError(exitCode: Int32, stderr: String) -> SimulatorError {
    guard let (domain, code) = domainAndCode(stderr) else {
      return self.error(exitCode: exitCode, stderr: stderr)
    }
    switch (domain, code) {
    // 꺼진 기기: "Unable to lookup in current state: Shutdown" (149).
    case ("com.apple.CoreSimulator.SimError", 405): return .deviceNotBooted
    // 실행 파일의 플랫폼·아키텍처가 맞지 않음(4), 기기 종류 미지원(6).
    case ("IXUserPresentableErrorDomain", 4), ("IXUserPresentableErrorDomain", 6): return .appIncompatible
    // "Have 27.0; need 27.1".
    case ("IXUserPresentableErrorDomain", 16): return .appRequiresNewerOS
    // "lstat of … failed".
    case ("NSPOSIXErrorDomain", 2): return .appNotFound
    // "Missing bundle ID."(13), "Failed to extract IPA."(42, 폴더가 아닌 파일).
    case ("IXErrorDomain", 13), ("IXErrorDomain", 42): return .appInvalid
    default: return .commandFailed
    }
  }

  /// launch 실패. 같은 방식.
  static func launchError(exitCode: Int32, stderr: String) -> SimulatorError {
    guard let (domain, code) = domainAndCode(stderr) else {
      return self.error(exitCode: exitCode, stderr: stderr)
    }
    switch (domain, code) {
    // 꺼진 기기·켜는 중 기기: "Unable to lookup in current state: Shutdown|Booting" (149).
    case ("com.apple.CoreSimulator.SimError", 405): return .deviceNotBooted
    // 설치되지 않은 번들 ID: "The request to open "…" failed."
    case ("FBSOpenApplicationServiceErrorDomain", 4): return .appNotInstalled
    // 설치에 실패한 번들 ID: "The request was denied by service delegate (…) for reason: NotFound (…unknown to FrontBoard)".
    // reason 토큰은 거절 줄의 정해진 자리에서만 읽는다 (앱 글자가 들어갈 수 있는 괄호 설명보다 앞, `denialReason`).
    case ("FBSOpenApplicationServiceErrorDomain", 1)
      where Self.denialReason(stderr) == "NotFound": return .appNotInstalled
    case ("FBSOpenApplicationServiceErrorDomain", _): return .appLaunchFailed
    // "did not return a process handle nor launch error" (시작하자마자 종료한 앱).
    case ("NSPOSIXErrorDomain", 3): return .appLaunchFailed
    default: return .commandFailed
    }
  }

  /// openurl 실패. 같은 방식. 둘째 줄("Simulator device failed to open <URL>.")에 사용자가 넣은 URL 이 나오므로
  /// 첫 domain 줄로만 분류한다.
  static func openURLError(exitCode: Int32, stderr: String) -> SimulatorError {
    guard let (domain, code) = domainAndCode(stderr) else {
      return self.error(exitCode: exitCode, stderr: stderr)
    }
    switch (domain, code) {
    // 꺼진 기기: "Unable to lookup in current state: Shutdown" (149).
    case ("com.apple.CoreSimulator.SimError", 405): return .deviceNotBooted
    // 처리할 앱이 없는 스킴 (115).
    case ("LSApplicationWorkspaceErrorDomain", 115): return .urlNotHandled
    // 호스트·앞뒤 공백 "Invalid URL."(22), 스킴 없음 OSStatus -50(206).
    case ("NSPOSIXErrorDomain", 22), ("NSOSStatusErrorDomain", -50): return .invalidURL
    default: return .commandFailed
    }
  }

  /// screenshot 실패. stderr 의 "Wrote screenshot to:"·오류 설명 줄에 경로(기기 이름이 든 파일 이름)가 나오므로
  /// 줄 머리의 domain 줄로만 분류한다 (파일 이름에는 Core 규칙으로 개행이 없다). domain 줄이 없을 때도
  /// `error(exitCode:stderr:)` 를 쓰지 않는다: 그 함수는 "Invalid device" 를 줄 어디서든 찾아 경로의 글자에 걸린다.
  static func screenshotError(exitCode: Int32, stderr: String) -> SimulatorError {
    guard let (domain, code) = domainAndCode(stderr) else {
      if stderr.drop(while: \.isWhitespace).hasPrefix("xcrun: error:") {
        return .developerToolsUnavailable
      }
      // 없는 기기: "Invalid device: <UDID>" (148).
      if stderr.split(whereSeparator: \.isNewline).contains(where: { $0.hasPrefix("Invalid device:") }) {
        return .deviceNotFound
      }
      return .commandFailed
    }
    switch (domain, code) {
    // 꺼진 기기: 약 60초 뒤 "Timeout waiting for screen surfaces" (60).
    case ("NSPOSIXErrorDomain", 60): return .deviceNotBooted
    // 저장 실패(NSCocoaErrorDomain 4·513)는 Workspace 가 방금 만든 폴더·파일이라 드물어 따로 나누지 않는다.
    default: return .commandFailed
    }
  }
}
