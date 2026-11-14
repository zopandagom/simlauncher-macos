import Core
import Foundation
import SimulatorInterface
import Testing
@testable import SimulatorImpl

/// 테스트 조건 인자(정확한 배열)와 `simctl ui` 읽기 해석. 기대 배열은 실제 기기로 확인한 명령이다 (Xcode 27.2, iOS 27.0).
struct SimctlConditionCommandTests {
  private static let udid = "B66201ED-154C-4F97-A6C7-C88F42E8D3A7"

  @Test("ui 읽기 세 항목")
  func uiRead() {
    #expect(SimctlCommand.uiRead(udid: Self.udid, option: .appearance) == ["simctl", "ui", Self.udid, "appearance"])
    #expect(SimctlCommand.uiRead(udid: Self.udid, option: .contentSize) == ["simctl", "ui", Self.udid, "content_size"])
    #expect(
      SimctlCommand.uiRead(udid: Self.udid, option: .increaseContrast) == [
        "simctl",
        "ui",
        Self.udid,
        "increase_contrast",
      ]
    )
  }

  @Test("ui 쓰기 세 종류: 고정 토큰")
  func uiWrite() {
    func arguments(_ setting: IOSDisplaySetting) -> [String] {
      let (option, value) = SimctlUIParser.write(setting)
      return SimctlCommand.uiWrite(udid: Self.udid, option: option, value: value)
    }
    #expect(arguments(.appearance(.dark)) == ["simctl", "ui", Self.udid, "appearance", "dark"])
    #expect(arguments(.appearance(.light)) == ["simctl", "ui", Self.udid, "appearance", "light"])
    #expect(arguments(.contentSize(.extraSmall)) == ["simctl", "ui", Self.udid, "content_size", "extra-small"])
    #expect(
      arguments(.contentSize(.accessibilityExtraExtraExtraLarge))
        == ["simctl", "ui", Self.udid, "content_size", "accessibility-extra-extra-extra-large"]
    )
    #expect(arguments(.increaseContrast(true)) == ["simctl", "ui", Self.udid, "increase_contrast", "enabled"])
    #expect(arguments(.increaseContrast(false)) == ["simctl", "ui", Self.udid, "increase_contrast", "disabled"])
  }

  @Test("location set 은 -- 없이 위도,경도 (음수 위도로 시작)")
  func locationSet() throws {
    let coordinate = try #require(GeoCoordinate(latitude: -33.8688, longitude: 151.2093))
    #expect(
      SimctlCommand.locationSet(udid: Self.udid, coordinate: coordinate)
        == ["simctl", "location", Self.udid, "set", "-33.8688,151.2093"]
    )
  }

  @Test("location start 는 --speed 뒤 -- 다음에 경유지 (좌표 6자리 반올림)")
  func locationStart() throws {
    let waypoints = try LocationRoute.parseWaypoints("-33.8688,151.2093\n-33.8700,151.21000049").get()
    let route = LocationRoute(waypoints: waypoints, speed: .walking)
    #expect(
      SimctlCommand.locationStart(udid: Self.udid, route: route)
        == ["simctl", "location", Self.udid, "start", "--speed=1.4", "--", "-33.8688,151.2093", "-33.87,151.21"]
    )
    let fast = LocationRoute(waypoints: waypoints, speed: .highway)
    #expect(SimctlCommand.locationStart(udid: Self.udid, route: fast)[4] == "--speed=28")
  }

  @Test("location run 은 공백 든 이름을 한 인자로, clear 는 인자 없이")
  func locationRunClear() {
    #expect(
      SimctlCommand.locationRun(udid: Self.udid, scenario: IOSLocationScenario.cityBicycleRide.rawValue)
        == ["simctl", "location", Self.udid, "run", "City Bicycle Ride"]
    )
    #expect(SimctlCommand.locationClear(udid: Self.udid) == ["simctl", "location", Self.udid, "clear"])
  }

  @Test("시나리오 없음: exit 1 이고 줄 머리가 Could not find scenario")
  func scenarioNotFound() {
    #expect(SimctlCommand.scenarioNotFound(exitCode: 1, output: "\nCould not find scenario 'Nope'\n"))
    #expect(SimctlCommand.scenarioNotFound(exitCode: 1, output: "  Could not find scenario 'City Run'"))
    #expect(!SimctlCommand.scenarioNotFound(exitCode: 149, output: "Could not find scenario 'Nope'"))
    #expect(!SimctlCommand.scenarioNotFound(exitCode: 1, output: "x Could not find scenario 'Nope'"))
    #expect(!SimctlCommand.scenarioNotFound(exitCode: 1, output: "Invalid latitude,longitude pair: 1"))
  }

  @Test(
    "외관 읽기",
    arguments: [
      ("light\n", IOSSettingReading<DeviceAppearance>.value(.light)),
      ("dark", .value(.dark)),
      ("  Dark \r\n", .value(.dark)),
      ("unsupported\n", .unsupported),
      ("unknown\n", .unknown),
      ("", .unknown),
      ("blue", .unknown),
    ]
  )
  func appearance(stdout: String, expected: IOSSettingReading<DeviceAppearance>) {
    #expect(SimctlUIParser.appearance(Data(stdout.utf8)) == expected)
  }

  @Test(
    "글씨 크기 읽기는 대소문자를 무시한다 (extra-Small·Small, 실측)",
    arguments: [
      ("extra-Small\n", IOSSettingReading<IOSContentSize>.value(.extraSmall)),
      ("Small", .value(.small)),
      ("large\n", .value(.large)),
      ("accessibility-extra-extra-extra-large\n", .value(.accessibilityExtraExtraExtraLarge)),
      ("unsupported", .unsupported),
      ("unknown", .unknown),
      ("", .unknown),
      ("huge", .unknown),
    ]
  )
  func contentSize(stdout: String, expected: IOSSettingReading<IOSContentSize>) {
    #expect(SimctlUIParser.contentSize(Data(stdout.utf8)) == expected)
  }

  @Test("글씨 크기 12단계 모두 쓰기 토큰 그대로 읽힌다")
  func contentSizeRoundTrip() {
    #expect(IOSContentSize.allCases.count == 12)
    for size in IOSContentSize.allCases {
      #expect(SimctlUIParser.contentSize(Data((size.rawValue + "\n").utf8)) == .value(size))
    }
  }

  @Test(
    "고대비 읽기",
    arguments: [
      ("enabled\n", IOSSettingReading<Bool>.value(true)),
      ("disabled", .value(false)),
      ("unsupported\n", .unsupported),
      ("unknown", .unknown),
      ("", .unknown),
      ("yes", .unknown),
    ]
  )
  func increaseContrast(stdout: String, expected: IOSSettingReading<Bool>) {
    #expect(SimctlUIParser.increaseContrast(Data(stdout.utf8)) == expected)
  }

  @Test("읽기가 UTF-8 이 아니면 unknown")
  func notUTF8() {
    #expect(SimctlUIParser.appearance(Data([0xFF, 0xFE])) == .unknown)
  }
}
