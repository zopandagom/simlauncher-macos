import Foundation
import Testing
@testable import Core

struct GeoCoordinateTests {
  struct Parsed: Sendable, CustomTestStringConvertible {
    let text: String
    let latitude: Double
    let longitude: Double

    var testDescription: String {
      self.text.debugDescription
    }
  }

  @Test(
    "위도, 경도를 쉼표·쉼표+공백·공백으로 나눠 받고 앞뒤 공백을 자른다",
    arguments: [
      Parsed(text: "37.5665, 126.9780", latitude: 37.5665, longitude: 126.978),
      Parsed(text: "37.5665,126.9780", latitude: 37.5665, longitude: 126.978),
      Parsed(text: "37.5665 126.9780", latitude: 37.5665, longitude: 126.978),
      Parsed(text: "  37.5665 ,\t126.9780 \n", latitude: 37.5665, longitude: 126.978),
      Parsed(text: "-33.8688,151.2093", latitude: -33.8688, longitude: 151.2093),
      Parsed(text: "90,180", latitude: 90, longitude: 180),
      Parsed(text: "-90,-180", latitude: -90, longitude: -180),
      Parsed(text: "-0,-0.0", latitude: 0, longitude: 0),
      Parsed(
        text: "37.123456789012345,-122.000000000000001",
        latitude: 37.123456789012345,
        longitude: -122.000000000000001
      ),
    ]
  )
  func parses(parsed: Parsed) throws {
    let coordinate = try GeoCoordinate.parse(parsed.text).get()
    #expect(coordinate.latitude == parsed.latitude)
    #expect(coordinate.longitude == parsed.longitude)
  }

  @Test("15자리 소수는 받고, 명령 문자열은 6자리로 반올림한다")
  func longFraction() throws {
    let coordinate = try GeoCoordinate.parse("37.566512345678901, 126.978012345678901").get()
    #expect(GeoCoordinate.decimalString(coordinate.latitude) == "37.566512")
    #expect(GeoCoordinate.decimalString(coordinate.longitude) == "126.978012")
  }

  @Test("-0 은 부호 없는 0 으로 맞춘다")
  func negativeZero() throws {
    let coordinate = try #require(GeoCoordinate(latitude: -0.0, longitude: -0.0))
    #expect(coordinate.latitude.sign == .plus)
    #expect(coordinate.longitude.sign == .plus)
  }

  @Test(
    "형식 문제",
    arguments: [
      "abc,def", "37,5665, 126,9780", "1e1,2e1", "+1,2", "nan,1", "inf,1", "37.5665", "1,2,3",
      "37.5665;126.9780", "1234,5", "1.,2", ".5,2", "１,２", "٣,٤", "1.123456789012345678,2",
      String(repeating: "1", count: 30) + "," + String(repeating: "2", count: 35),
    ]
  )
  func format(text: String) {
    #expect(GeoCoordinate.parse(text) == .failure(.format))
  }

  @Test("앞뒤 공백을 자른 뒤 64자는 형식대로 보고 65자는 형식 문제")
  func lengthLimit() {
    let sixtyFour = "1" + String(repeating: " ", count: 61) + ",2"
    #expect(sixtyFour.count == GeoCoordinate.maximumTextLength)
    #expect(GeoCoordinate.parse("  " + sixtyFour + "  ").map(\.latitude) == .success(1))
    let sixtyFive = "1" + String(repeating: " ", count: 62) + ",2"
    #expect(GeoCoordinate.parse(sixtyFive) == .failure(.format))
  }

  @Test("빈 값·공백뿐이면 empty", arguments: ["", "   ", "\n\t"])
  func empty(text: String) {
    #expect(GeoCoordinate.parse(text) == .failure(.empty))
  }

  @Test("범위 밖: 위도를 먼저 본다")
  func outOfRange() {
    #expect(GeoCoordinate.parse("90.0001,0") == .failure(.latitudeOutOfRange))
    #expect(GeoCoordinate.parse("-91,0") == .failure(.latitudeOutOfRange))
    #expect(GeoCoordinate.parse("0,180.5") == .failure(.longitudeOutOfRange))
    #expect(GeoCoordinate.parse("0,-181") == .failure(.longitudeOutOfRange))
    #expect(GeoCoordinate.parse("95,200") == .failure(.latitudeOutOfRange))
  }

  @Test("init 은 범위 밖·무한·NaN 이면 nil")
  func initRejects() {
    #expect(GeoCoordinate(latitude: 90.1, longitude: 0) == nil)
    #expect(GeoCoordinate(latitude: 0, longitude: -180.1) == nil)
    #expect(GeoCoordinate(latitude: .infinity, longitude: 0) == nil)
    #expect(GeoCoordinate(latitude: 0, longitude: .nan) == nil)
  }

  @Test(
    "decimalString: 6자리 반올림·끝 0 제거·지수 표기 없음",
    arguments: [
      (37.5665, "37.5665"),
      (-122.0312186, "-122.031219"),
      (-122.031219, "-122.031219"),
      (-0.0, "0"),
      (0, "0"),
      (90, "90"),
      (-180, "-180"),
      (0.00001, "0.00001"),
      (0.000001, "0.000001"),
      (-0.000004, "-0.000004"),
      (-0.0000004, "0"),
      (1.4, "1.4"),
      (28, "28"),
    ] as [(Double, String)]
  )
  func decimalString(value: Double, expected: String) {
    #expect(GeoCoordinate.decimalString(value) == expected)
  }

  @Test("decimalString 은 로캘을 받지 않는다 (de_DE 처럼 쉼표 소수점 로캘과 무관하게 `.`)")
  func decimalStringIgnoresLocale() {
    let german = Locale(identifier: "de_DE")
    #expect(german.decimalSeparator == ",")
    #expect(GeoCoordinate.decimalString(37.5665) == "37.5665")
  }

  @Test("decimalString: 유한하지 않으면 0")
  func decimalStringNonFinite() {
    #expect(GeoCoordinate.decimalString(.nan) == "0")
    #expect(GeoCoordinate.decimalString(.infinity) == "0")
  }

  @Test("프리셋은 모두 범위 안이고, 음수 위도·음수 경도가 들어 있다")
  func presets() {
    for preset in LocationPreset.allCases {
      let coordinate = preset.coordinate
      #expect(GeoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude) == coordinate, "\(preset)")
    }
    #expect(LocationPreset.allCases.contains { $0.coordinate.latitude < 0 })
    #expect(LocationPreset.allCases.contains { $0.coordinate.longitude < 0 })
    #expect(LocationPreset.seoul.coordinate == GeoCoordinate(latitude: 37.5665, longitude: 126.978))
  }
}
