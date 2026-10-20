import Foundation

/// 링크 검사에서 걸린 문제.
public enum DeepLinkProblem: Hashable, Sendable {
  /// 앞뒤 공백·개행을 빼면 비었다.
  case empty
  /// `URL(string:)` 이 읽지 못했다: 스킴·호스트에 공백, 숫자로 시작하는 스킴 등.
  /// 스킴이 없는 입력도 여기 들 수 있다 ("192.168.0.1:8080" 은 nil).
  case malformed
  /// URL 로는 읽히지만 스킴이 없다 ("hello", "example.com").
  case missingScheme
}

/// 기기에서 열 링크 (앱 스킴 딥링크·웹 주소 모두). 검사를 통과한 값만 만들어진다.
/// 앞뒤 공백·개행을 빼고 `URL(string:)`(기본값, 자동 인코딩)으로 읽는다. 스킴 종류는 보지 않는다.
/// - 경로·쿼리·조각의 공백·한글·단독 `%` 는 퍼센트 인코딩되고, 이미 인코딩된 `%XX` 는 그대로 둔다. 가운데 개행은 `%0A`.
/// - 호스트의 한글은 퓨니코드로 바뀌어 앱은 `xn--…` 를 받는다 ("myapp://경로" → "myapp://xn--289ak4t").
///   simctl 도 같은 값으로 바꾸므로 막지 않는다. 경로 형식("myapp:///경로")은 퍼센트 인코딩으로 전달된다.
/// - "localhost:8080" 은 스킴 "localhost" 로 통과하고, simctl 이 처리할 앱이 없다고 거절한다.
public struct DeepLink: Hashable, Sendable {
  /// simctl 에 넘길 값은 `url.absoluteString`.
  public let url: URL

  /// `problem(in:)` 이 nil 일 때만 만들어진다. 아니면 nil.
  public init?(_ raw: String) {
    guard case let .link(url) = Self.parse(raw) else { return nil }
    self.url = url
  }

  /// 첫 문제. 없으면 nil. 순서: empty → malformed → missingScheme.
  public static func problem(in raw: String) -> DeepLinkProblem? {
    guard case let .problem(problem) = parse(raw) else { return nil }
    return problem
  }

  private enum Parsed {
    case link(URL)
    case problem(DeepLinkProblem)
  }

  /// 두 API 가 같은 판정을 쓰게 한 곳에 둔다.
  private static func parse(_ raw: String) -> Parsed {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return .problem(.empty)
    }
    // `encodingInvalidCharacters: false` 는 경로의 공백·한글까지 거절하므로 쓰지 않는다.
    guard let url = URL(string: trimmed) else {
      return .problem(.malformed)
    }
    guard let scheme = url.scheme, !scheme.isEmpty else {
      return .problem(.missingScheme)
    }
    return .link(url)
  }
}
