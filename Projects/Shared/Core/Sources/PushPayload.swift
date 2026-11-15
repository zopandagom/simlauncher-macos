import Foundation

/// `simctl push` 로 보낼 payload. `data` 는 보낼 바이트 그대로다 (simctl 은 입력 바이트를 공백·이스케이프 포함 그대로 UTF-8 로 세어
/// 4096 을 넘으면 exit 28 로 거절한다, 실측 Xcode 27.2). 만들 때 simctl 이 거절하는 형식(TC-B 실측의 22·14·28)을 먼저 막는다.
/// 번들 인자가 payload 의 `Simulator Target Bundle` 키보다 우선하므로(실측) 그 키는 검사하지 않는다.
public struct PushPayload: Hashable, Sendable {
  /// simctl 이 받는 가장 큰 payload 바이트 수 (help 원문 "Be 4096 bytes or less", 실측 4096 통과·4097 거절).
  public static let maxByteCount = 4096

  /// 보낼 바이트 그대로.
  public let data: Data

  public var byteCount: Int {
    self.data.count
  }

  private init(data: Data) {
    self.data = data
  }

  /// 폼 입력: 본문은 앞뒤 공백·줄바꿈을 뺀 값이 비면 `.emptyBody`. 제목은 앞뒤 공백·줄바꿈을 뺀 값이 비면 넣지 않는다
  /// (넣는 값 자체는 입력 그대로). `{"aps":{"alert":{"body":…,"title":…}}}` 를 키 정렬로 만들고(`/` 는 이스케이프하지 않는다)
  /// sound·badge 는 넣지 않는다. 만든 바이트가 `maxByteCount` 를 넘으면 `.tooLarge`.
  public static func alert(title: String, body: String) -> Result<PushPayload, PushPayloadProblem> {
    guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .failure(.emptyBody)
    }
    var alert = ["body": body]
    if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      alert["title"] = title
    }
    let object: [String: Any] = ["aps": ["alert": alert]]
    // 문자열 사전이라 직렬화는 실패하지 않는다. 실패하면 형식 문제로 본다.
    guard let data = try? JSONSerialization
      .data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    else {
      return .failure(.notJSON)
    }
    return self.checkedSize(data)
  }

  /// JSON 직접 입력: 입력 문자열의 UTF-8 바이트를 그대로 보낸다 (다시 직렬화하지 않는다). 검사 순서:
  /// 공백뿐 → `.empty`, 파싱 실패 → 입력에 `“ ” ‘ ’` 가 있으면 `.smartQuotes` 아니면 `.notJSON`, 루트가 사전이 아님 → `.rootNotObject`,
  /// `aps` 없음 → `.missingAPS`, 사전이 아님 → `.apsNotObject`, 빈 사전 → `.apsEmpty`, `aps.alert` 가 있는데 문자열·사전이 아님 →
  /// `.alertInvalid`, 마지막에 바이트 수 > `maxByteCount` → `.tooLarge` (형식 문제를 먼저 고치게 크기는 마지막에 본다).
  public static func json(_ text: String) -> Result<PushPayload, PushPayloadProblem> {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .failure(.empty)
    }
    let data = Data(text.utf8)
    guard let root = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else {
      let smartQuotes: Set<Character> = ["\u{201C}", "\u{201D}", "\u{2018}", "\u{2019}"]
      return .failure(text.contains(where: smartQuotes.contains) ? .smartQuotes : .notJSON)
    }
    guard let object = root as? [String: Any] else {
      return .failure(.rootNotObject)
    }
    guard let aps = object["aps"] else {
      return .failure(.missingAPS)
    }
    guard let apsObject = aps as? [String: Any] else {
      return .failure(.apsNotObject)
    }
    guard !apsObject.isEmpty else {
      return .failure(.apsEmpty)
    }
    if let alert = apsObject["alert"], !(alert is String), !(alert is [String: Any]) {
      return .failure(.alertInvalid)
    }
    return self.checkedSize(data)
  }

  private static func checkedSize(_ data: Data) -> Result<PushPayload, PushPayloadProblem> {
    guard data.count <= self.maxByteCount else {
      return .failure(.tooLarge(byteCount: data.count))
    }
    return .success(PushPayload(data: data))
  }
}

/// `PushPayload` 를 만들지 못한 이유. 각 케이스 옆은 막지 않고 보냈을 때 simctl 의 결과다 (TC-B 실측, iOS 26.5·27.0 같음).
public enum PushPayloadProblem: Error, Hashable, Sendable {
  /// 폼의 본문이 비었다 (27.0 은 보일 내용이 없는 알림을 UNErrorDomain 2002·1401 로 거절한다).
  case emptyBody
  /// JSON 이 공백뿐이다 (빈 입력은 NSCocoaErrorDomain 3840 인데 exit 0 이다).
  case empty
  /// JSON 이 아니다 (3840, exit 0).
  case notJSON
  /// JSON 이 아니고 입력에 둥근 따옴표(`“ ” ‘ ’`)가 있다 (macOS 자동 따옴표 바꾸기 안내용).
  case smartQuotes
  /// 루트가 사전이 아니다 (NSPOSIXErrorDomain 22 "JSON root is not an object").
  case rootNotObject
  /// `aps` 키가 없다 (22 "Notification payload is missing the aps key").
  case missingAPS
  /// `aps` 가 사전이 아니다 (NSPOSIXErrorDomain 14 "Failed to allocate UNNotificationRequest").
  case apsNotObject
  /// `aps` 가 빈 사전이다 (14).
  case apsEmpty
  /// `aps.alert` 가 있는데 문자열·사전이 아니다 (14).
  case alertInvalid
  /// 바이트 수가 `PushPayload.maxByteCount` 를 넘는다 (NSPOSIXErrorDomain 28 "Payload too large"). 폼에도 적용한다.
  case tooLarge(byteCount: Int)
}
