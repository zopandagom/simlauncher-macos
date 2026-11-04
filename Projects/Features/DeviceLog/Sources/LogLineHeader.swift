import Foundation

/// 로그 줄 앞의 머리말(시각·프로세스 이름·[pid:스레드]) 뒤 메시지가 시작하는 곳. 필터의 "시작" 조건이 이 뒤와 비교한다.
/// 머리말 형식 (Xcode 27·iOS 27 시뮬레이터 실측, 2026-11-03):
/// - `OS_ACTIVITY_DT_MODE` 켬 (Logger·NSLog):
///   `2026-11-03 15:58:29.655736+0900 LogProbe[82561:42341349] [probe] logger default hello`
/// - DT_MODE 없는 NSLog: `2026-11-03 15:58:08.123 LogProbe[82449:42340721] nslog hello 1`
/// 프로세스 이름에는 공백이 들 수 있다. Logger 의 카테고리(`[probe] `)는 메시지에 남긴다. print 줄에는 머리말이 없다.
enum LogLineHeader {
  /// 머리말이 없으면 줄 처음.
  static func messageStart(in text: String) -> String.Index {
    String.Index(utf16Offset: self.messageOffset(in: text), in: text)
  }

  /// 머리말 뒤 메시지 시작의 UTF-16 위치 (`NSRegularExpression` 이 쓰는 단위). 머리말이 없으면 0.
  static func messageOffset(in text: String) -> Int {
    // 머리말은 숫자로 시작한다. 대부분인 print 줄을 정규식 없이 거른다 (5만 줄 거르기).
    guard let first = text.utf8.first, (0x30 ... 0x39).contains(first) else { return 0 }
    let length = (text as NSString).length
    let range = NSRange(location: 0, length: min(length, Self.maxHeaderLength))
    guard let match = Self.pattern?.firstMatch(in: text, options: .anchored, range: range) else { return 0 }
    return match.range.upperBound
  }

  /// 머리말을 이 길이 안에서만 찾는다 (프로세스 이름이 길어도 이보다 짧다. 긴 줄 전체를 훑지 않게).
  private static let maxHeaderLength = 512

  /// 고정 패턴이라 만들기에 실패하지 않는다 (테스트가 머리말을 찾는 것으로 확인한다). 실패하면 머리말 없음으로 본다.
  private static let pattern = try? NSRegularExpression(
    pattern: #"\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+(?:[+-]\d{4})? .+?\[\d+:[0-9A-Fa-f]+\] "#
  )
}
