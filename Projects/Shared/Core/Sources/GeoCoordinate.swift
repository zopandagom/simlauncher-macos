import Foundation

/// 위도·경도 한 점 (테스트 조건의 위치). 유한값, 위도 −90…90, 경도 −180…180 (양끝 포함). `-0.0` 은 `0` 으로 맞춘다.
/// simctl `location set` 은 범위 밖·문자 좌표를 exit 0 으로 받고 무시하므로(실측) 명령 인자는 이 타입을 거친 값만 만든다.
public struct GeoCoordinate: Hashable, Sendable {
  public let latitude: Double
  public let longitude: Double

  /// 범위 밖·무한·NaN 이면 nil.
  public init?(latitude: Double, longitude: Double) {
    guard
      latitude.isFinite, longitude.isFinite,
      (-90.0 ... 90.0).contains(latitude), (-180.0 ... 180.0).contains(longitude)
    else {
      return nil
    }
    // `-0.0 + 0` 은 `0.0` 이다 (IEEE 754 기본 반올림).
    self.latitude = latitude + 0
    self.longitude = longitude + 0
  }

  /// Core 안에서 범위가 확실한 상수(`LocationPreset`)용. 범위 밖이면 멈춘다.
  init(validLatitude latitude: Double, longitude: Double) {
    guard let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude) else {
      preconditionFailure("범위 밖 좌표 상수: \(latitude), \(longitude)")
    }
    self = coordinate
  }
}

/// `GeoCoordinate.parse` 가 거절한 이유 (처음 하나).
public enum GeoCoordinateProblem: Error, Hashable, Sendable {
  /// 비었거나 공백뿐이다.
  case empty
  /// "위도, 경도" 형식이 아니다 (쉼표 소수점·지수·`+`·`nan`·ASCII 밖 숫자·64자 초과 포함).
  case format
  case latitudeOutOfRange
  case longitudeOutOfRange
}

public extension GeoCoordinate {
  /// 입력 길이 상한 (앞뒤 공백을 자른 뒤).
  static let maximumTextLength = 64

  /// "위도, 경도" 한 줄. 앞뒤 공백을 자르고, 두 수는 쉼표(뒤 공백 허용) 또는 공백으로 나눈다 (지도 앱에서 복사한 "37.5665, 126.9780").
  /// 수는 `-?[0-9]{1,3}(\.[0-9]{1,17})?` 만 받는다: 소수점은 `.` 만(Mac 로캘과 무관), 지수·`+`·`nan`·`inf`·ASCII 밖 숫자 거절.
  /// 소수 17자리까지 받고, 명령에 넘길 때 `decimalString` 이 6자리로 반올림한다. 위도를 먼저 검사한다.
  static func parse(_ text: String) -> Result<GeoCoordinate, GeoCoordinateProblem> {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return .failure(.empty)
    }
    guard trimmed.count <= Self.maximumTextLength else {
      return .failure(.format)
    }
    let pattern = /(-?[0-9]{1,3}(?:\.[0-9]{1,17})?)[ \t]*(?:,[ \t]*|[ \t]+)(-?[0-9]{1,3}(?:\.[0-9]{1,17})?)/
    guard
      let match = trimmed.wholeMatch(of: pattern),
      let latitude = Double(String(match.output.1)),
      let longitude = Double(String(match.output.2))
    else {
      return .failure(.format)
    }
    guard (-90.0 ... 90.0).contains(latitude) else {
      return .failure(.latitudeOutOfRange)
    }
    guard let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude) else {
      return .failure(.longitudeOutOfRange)
    }
    return .success(coordinate)
  }

  /// 로캘과 무관한 `.` 소수점 문자열: 소수 6자리(약 0.1 m)로 반올림하고 끝 0 을 뺀다 (`37.5665`, `-122.031219`, `0`, `90`).
  /// 지수 표기를 쓰지 않는다 (`Double.description`·`String(format:)`·`formatted()` 를 쓰지 않고 정수 백만분의 일 단위로 조립한다).
  /// 반올림해 0 이면 부호 없이 `0`. 유한하지 않거나 ±9.2e12 를 넘으면 `0` (좌표·속도에는 생기지 않는다).
  static func decimalString(_ value: Double) -> String {
    let scaled = (value * 1_000_000).rounded(.toNearestOrAwayFromZero)
    guard let micro = Int64(exactly: scaled), micro != 0 else {
      return "0"
    }
    let sign = micro < 0 ? "-" : ""
    let magnitude = micro.magnitude
    let whole = magnitude / 1_000_000
    let fraction = magnitude % 1_000_000
    guard fraction != 0 else {
      return "\(sign)\(whole)"
    }
    var digits = String(fraction)
    digits = String(repeating: "0", count: 6 - digits.count) + digits
    while digits.hasSuffix("0") {
      digits.removeLast()
    }
    return "\(sign)\(whole).\(digits)"
  }
}
