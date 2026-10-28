import Foundation

/// AVD 의 `<이름>.ini`·`config.ini` 형식 (`key=value` 줄). Studio 는 `key=value`, emulator 는 처음 켤 때
/// config.ini 를 `key = value` 로 다시 쓴다 (실측) → 읽을 때 `=` 앞뒤 공백을 허용한다.
public enum AVDIniFile {
  /// 이보다 크면 읽지 않는다 (AVD 설정 파일은 수 KB).
  public static let maxByteCount = 64 * 1024

  /// 줄마다 `key=value` 를 읽는다. 키·값의 앞뒤 공백을 빼고, 빈 줄·`#`·`;` 주석·`=` 없는 줄·빈 키는 건너뛴다.
  /// 값은 첫 `=` 뒤 전부 (값 안의 `=` 는 그대로). CRLF 도 읽는다. 같은 키가 여러 번 나오면 모두 순서대로 남긴다 (조회는 `value(for:in:)`).
  /// UTF-8 이 아니거나 `maxByteCount` 를 넘으면 nil.
  public static func parse(_ data: Data) -> [(key: String, value: String)]? {
    guard data.count <= self.maxByteCount, let text = String(bytes: data, encoding: .utf8) else {
      return nil
    }
    var pairs: [(key: String, value: String)] = []
    for rawLine in text.split(omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";"), let equals = line.firstIndex(of: "=") else {
        continue
      }
      let key = line[..<equals].trimmingCharacters(in: .whitespaces)
      let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
      guard !key.isEmpty else {
        continue
      }
      pairs.append((key, value))
    }
    return pairs
  }

  /// 그 키의 처음 값. 없으면 nil.
  public static func value(for key: String, in pairs: [(key: String, value: String)]) -> String? {
    pairs.first { $0.key == key }?.value
  }

  /// 순서대로 `key=value\n`. 값에 줄 바꿈이 없는지는 부르는 쪽이 보장한다 (표시 이름은 `DeviceName.problem` 으로 제어 문자를 막는다).
  public static func render(_ pairs: [(key: String, value: String)]) -> Data {
    Data(pairs.map { "\($0.key)=\($0.value)\n" }.joined().utf8)
  }
}
