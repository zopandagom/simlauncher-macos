import Core

public extension SavedLogFilter {
  /// "오류만": `error` 포함, 대소문자 무시.
  static let sampleErrors = SavedLogFilter(
    name: "오류만",
    conditions: [Condition(kind: .contains, text: "error", isExcluded: false)],
    isCaseSensitive: false
  )!

  /// "HTTP 4xx·5xx": 정규식 `status=[45]\d\d`, `health` 포함 제외, 대소문자 구분.
  static let sampleHTTP = SavedLogFilter(
    name: "HTTP 4xx·5xx",
    conditions: [
      Condition(kind: .regex, text: #"status=[45]\d\d"#, isExcluded: false),
      Condition(kind: .contains, text: "health", isExcluded: true),
    ],
    isCaseSensitive: true
  )!

  /// "깨진 정규식": 읽을 수 없는 정규식 `(unclosed` (관리자가 넣은 값을 불러올 때의 안내를 흉내 낸다).
  static let sampleInvalidRegex = SavedLogFilter(
    name: "깨진 정규식",
    conditions: [Condition(kind: .regex, text: "(unclosed", isExcluded: false)],
    isCaseSensitive: false
  )!
}
