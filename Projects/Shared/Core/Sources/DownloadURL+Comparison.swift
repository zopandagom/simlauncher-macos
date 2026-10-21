import Foundation

public extension DownloadURL {
  /// 같은 자원을 가리키는 주소면 같은 값 (카탈로그 중복 등록 판정용). 화면에 보이지 않는다.
  /// RFC 3986 6.2.2(대소문자·퍼센트 인코딩·점 세그먼트)와 6.2.3(https 기본 포트·빈 경로) 정규화 뒤 조각(#…)을 뺀다.
  /// - 같게 본다: 스킴·호스트 대소문자, `:443` 유무, 빈 경로와 `/`, `%7E`↔`~`(예약되지 않은 문자), `%2f`↔`%2F`, `/./`·`/x/../`,
  ///   조각 유무, 한글 경로↔퍼센트 인코딩, 한글 호스트↔퓨니코드.
  /// - 다르게 본다(서버가 구분할 수 있다): 경로 대소문자, 끝 슬래시, `//`, 다른 포트, 쿼리 값·순서, `?` 유무, `%2F`↔`/`.
  var comparisonKey: String {
    var key = "https://"
    key += Self.asciiLowercased(self.url.host(percentEncoded: false) ?? "")
      .bracketedIfIPv6()
    if let port = self.url.port, port != 443 {
      key += ":\(port)"
    }
    let path = self.url.path(percentEncoded: true)
    key += Self.removingDotSegments(Self.normalizingPercentEncoding(path.isEmpty ? "/" : path))
    if let query = self.url.query(percentEncoded: true) {
      key += "?"
      key += Self.normalizingPercentEncoding(query)
    }
    return key
  }
}

extension DownloadURL {
  /// ASCII 영문만 소문자로 바꾼다 (퓨니코드 호스트 포함). 그 밖의 글자는 그대로.
  static func asciiLowercased(_ text: String) -> String {
    var bytes: [UInt8] = []
    bytes.reserveCapacity(text.utf8.count)
    for byte in text.utf8 {
      if byte >= UInt8(ascii: "A"), byte <= UInt8(ascii: "Z") {
        bytes.append(byte + 32)
      } else {
        bytes.append(byte)
      }
    }
    // ASCII 대문자만 바꾸므로 UTF-8 은 그대로 올바르다 (nil 이 되지 않는다).
    return String(validating: bytes, as: UTF8.self) ?? text
  }

  /// `%xx` 의 hex 를 대문자로 바꾸고, 예약되지 않은 문자(ASCII 영문·숫자·`-` `.` `_` `~`)를 가리키는 `%xx` 는 풀어 쓴다.
  /// 그 밖의 바이트는 그대로 둔다 (RFC 3986 6.2.2.1·6.2.2.2).
  static func normalizingPercentEncoding(_ text: String) -> String {
    let input = Array(text.utf8)
    var output: [UInt8] = []
    output.reserveCapacity(input.count)
    var index = 0
    while index < input.count {
      let byte = input[index]
      if byte == UInt8(ascii: "%"),
         index + 2 < input.count,
         let high = Self.hexValue(input[index + 1]),
         let low = Self.hexValue(input[index + 2])
      {
        let value = high * 16 + low
        if Self.isUnreserved(value) {
          output.append(value)
        } else {
          output.append(UInt8(ascii: "%"))
          output.append(Self.upperHexDigit(high))
          output.append(Self.upperHexDigit(low))
        }
        index += 3
      } else {
        output.append(byte)
        index += 1
      }
    }
    // 예약되지 않은 ASCII 문자만 풀므로 UTF-8 은 그대로 올바르다 (nil 이 되지 않는다).
    return String(validating: output, as: UTF8.self) ?? text
  }

  /// RFC 3986 5.2.4 `remove_dot_segments`.
  static func removingDotSegments(_ path: String) -> String {
    var input = Substring(path)
    var output = ""
    while !input.isEmpty {
      if input.hasPrefix("../") {
        input = input.dropFirst(3)
      } else if input.hasPrefix("./") {
        input = input.dropFirst(2)
      } else if input.hasPrefix("/./") {
        input = input.dropFirst(2)
      } else if input == "/." {
        input = "/"
      } else if input.hasPrefix("/../") {
        input = input.dropFirst(3)
        Self.removeLastSegment(from: &output)
      } else if input == "/.." {
        input = "/"
        Self.removeLastSegment(from: &output)
      } else if input == "." || input == ".." {
        input = ""
      } else {
        // 첫 세그먼트(앞의 "/" 포함, 다음 "/" 전까지)를 옮긴다.
        let searchStart = input.hasPrefix("/") ? input.index(after: input.startIndex) : input.startIndex
        let end = input[searchStart...].firstIndex(of: "/") ?? input.endIndex
        output += input[input.startIndex ..< end]
        input = input[end...]
      }
    }
    return output
  }

  /// 마지막 "/" 와 그 뒤를 지운다. "/" 가 없으면 모두 지운다.
  private static func removeLastSegment(from output: inout String) {
    if let slash = output.lastIndex(of: "/") {
      output.removeSubrange(slash...)
    } else {
      output = ""
    }
  }

  private static func hexValue(_ byte: UInt8) -> UInt8? {
    switch byte {
    case UInt8(ascii: "0") ... UInt8(ascii: "9"): byte - UInt8(ascii: "0")
    case UInt8(ascii: "a") ... UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
    case UInt8(ascii: "A") ... UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
    default: nil
    }
  }

  private static func upperHexDigit(_ value: UInt8) -> UInt8 {
    value < 10 ? UInt8(ascii: "0") + value : UInt8(ascii: "A") + value - 10
  }

  private static func isUnreserved(_ byte: UInt8) -> Bool {
    switch byte {
    case UInt8(ascii: "A") ... UInt8(ascii: "Z"),
         UInt8(ascii: "a") ... UInt8(ascii: "z"),
         UInt8(ascii: "0") ... UInt8(ascii: "9"),
         UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "~"):
      true
    default:
      false
    }
  }
}

private extension String {
  /// IPv6 리터럴(":" 가 든 호스트)이면 `[` `]` 로 감싼다.
  func bracketedIfIPv6() -> String {
    self.contains(":") ? "[\(self)]" : self
  }
}
