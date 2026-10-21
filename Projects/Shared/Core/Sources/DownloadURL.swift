import Foundation

/// 내려받을 주소 검사에서 걸린 문제.
public enum DownloadURLProblem: Hashable, Sendable {
  /// 앞뒤 공백·개행을 빼면 비었다.
  case empty
  /// `URL(string:)` 이 읽지 못했다 (호스트에 공백, 가운데 개행 등).
  case malformed
  /// 스킴이 https 가 아니다 (대소문자 무시). 스킴이 없거나("example.com/a.zip", "//example.com/a.zip") http·ftp·file 이 여기 든다.
  case notHTTPS
  /// https 지만 호스트가 없다 ("https://", "https:///a.zip").
  case missingHost
  /// 사용자 이름·비밀번호가 들어 있다 ("https://user:pw@host/", "https://@host/"). 인증은 지원하지 않는다.
  case hasCredentials
}

/// 내려받을 HTTPS 주소. 검사를 통과한 값만 만들어진다. 빌드 zip·카탈로그 주소에 함께 쓴다.
/// 앞뒤 공백·개행을 빼고 `URL(string:)`(기본값, 자동 인코딩)으로 읽는다. 경로의 공백·한글은 퍼센트 인코딩되고,
/// 호스트의 한글은 퓨니코드로 바뀐다. 포트·쿼리·조각은 그대로 둔다.
public struct DownloadURL: Hashable, Sendable {
  public let url: URL

  /// `problem(in:)` 이 nil 일 때만 만들어진다. 아니면 nil.
  public init?(_ raw: String) {
    guard case let .link(url) = Self.parse(raw) else { return nil }
    self.url = url
  }

  /// 첫 문제. 없으면 nil. 순서: empty → malformed → notHTTPS → missingHost → hasCredentials.
  public static func problem(in raw: String) -> DownloadURLProblem? {
    guard case let .problem(problem) = parse(raw) else { return nil }
    return problem
  }

  private enum Parsed {
    case link(URL)
    case problem(DownloadURLProblem)
  }

  /// 두 API 가 같은 판정을 쓰게 한 곳에 둔다.
  private static func parse(_ raw: String) -> Parsed {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return .problem(.empty)
    }
    guard let url = URL(string: trimmed) else {
      return .problem(.malformed)
    }
    guard url.scheme?.lowercased() == "https" else {
      return .problem(.notHTTPS)
    }
    guard let host = url.host(percentEncoded: false), !host.isEmpty else {
      return .problem(.missingHost)
    }
    // "https://@host" 는 user 가 빈 문자열이라 nil 인지로 본다.
    if url.user != nil || url.password != nil {
      return .problem(.hasCredentials)
    }
    return .link(url)
  }
}
