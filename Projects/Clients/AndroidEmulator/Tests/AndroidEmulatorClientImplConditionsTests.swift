import AndroidEmulatorInterface
import CommandInterface
import CommandTesting
import Core
import Foundation
import Testing
@testable import AndroidEmulatorImpl

/// 테스트 조건: 앱 작업과 같은 사전 확인 뒤에만 명령을 보낸다. adb 는 흉내(`FakeADB.onApp`).
struct AndroidEmulatorClientImplConditionsTests {
  private static let pixel = AndroidEmulatorClientImplAppTests.pixel
  private static let nightRead = ["-s", "emulator-5554", "shell", "cmd", "uimode", "night"]
  private static let locationRead = ["-s", "emulator-5554", "shell", "cmd", "location", "is-location-enabled"]

  private static func result(_ code: Int32, stdout: String = "", stderr: String = "") -> CommandResult {
    AndroidEmulatorClientImplAppTests.result(code, stdout: stdout, stderr: stderr)
  }

  private static func allErrors(_ client: AndroidEmulatorClientImpl, _ id: AndroidVirtualDevice.ID) async throws
    -> [AndroidEmulatorError?]
  {
    let coordinate = try #require(GeoCoordinate(latitude: 1, longitude: 2))
    return await [
      thrownError { _ = try await client.testConditions(on: id) },
      thrownError { _ = try await client.setNightMode(.dark, on: id) },
      thrownError { _ = try await client.setLocation(coordinate, on: id) },
    ]
  }

  @Test("사전 확인: 꺼짐·없는 기기·SDK 없음은 명령 없이 던진다")
  func precheck() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("Pixel")
    #expect(try await Self.allErrors(harness.client, Self.pixel) == Array(repeating: .deviceNotBooted, count: 3))
    #expect(
      try await Self.allErrors(harness.client, AndroidVirtualDevice.ID("Missing"))
        == Array(repeating: .deviceNotFound, count: 3)
    )
    #expect(AndroidEmulatorClientImplAppTests.appCalls(harness).isEmpty)

    let noSDK = try Harness(installSDK: false)
    defer { noSDK.cleanUp() }
    #expect(try await Self.allErrors(noSDK.client, Self.pixel) == Array(repeating: .sdkUnavailable, count: 3))
  }

  @Test("읽기: uimode → 위치 서비스, 같은 환경·10초 한도")
  func read() async throws {
    let harness = try AndroidEmulatorClientImplAppTests.booted()
    defer { harness.cleanUp() }
    harness.adb.onApp { arguments in
      switch arguments {
      case Self.nightRead: Self.result(0, stdout: "Night mode: custom_bedtime\n")
      case Self.locationRead: Self.result(0, stdout: "false\n")
      default: Self.result(1)
      }
    }

    let conditions = try await harness.client.testConditions(on: Self.pixel)

    #expect(conditions == AndroidTestConditions(nightMode: .other, locationEnabled: false))
    #expect(AndroidEmulatorClientImplAppTests.appCalls(harness) == [Self.nightRead, Self.locationRead])
    let invocation = try #require(harness.command.invocations.last)
    #expect(invocation.environment == ["HOME": FileFacts.path(harness.home), "ADB_MDNS": "0"])
    #expect(invocation.timeout == .seconds(10))
  }

  @Test("읽기: uimode 가 끊김이면 deviceNotBooted, 그 밖 실패는 unknown, 위치 서비스 실패는 nil")
  func readFailures() async throws {
    let harness = try AndroidEmulatorClientImplAppTests.booted()
    defer { harness.cleanUp() }
    harness.adb.onApp { _ in Self.result(255, stderr: "Unknown command\n") }
    #expect(
      try await harness.client.testConditions(on: Self.pixel)
        == AndroidTestConditions(nightMode: .unknown, locationEnabled: nil)
    )

    harness.adb.onApp { _ in Self.result(1, stderr: "adb: device offline\n") }
    #expect(await thrownError { _ = try await harness.client.testConditions(on: Self.pixel) } == .deviceNotBooted)

    harness.adb.onApp { arguments throws(CommandError) in
      guard arguments == Self.nightRead else { throw .timedOut }
      return Self.result(0, stdout: "Night mode: yes\n")
    }
    #expect(
      try await harness.client.testConditions(on: Self.pixel)
        == AndroidTestConditions(nightMode: .dark, locationEnabled: nil)
    )
  }

  @Test("외관: 쓰기 출력으로 판정하고 다시 읽지 않는다")
  func setNightMode() async throws {
    let harness = try AndroidEmulatorClientImplAppTests.booted()
    defer { harness.cleanUp() }
    harness.adb.onApp { arguments in
      Self.result(0, stdout: arguments.last == "yes" ? "Night mode: yes\n" : "Night mode: no\n")
    }

    #expect(try await harness.client.setNightMode(.dark, on: Self.pixel) == .applied)
    #expect(AndroidEmulatorClientImplAppTests.appCalls(harness) == [Self.nightRead + ["yes"]])
  }

  @Test("외관: 쓰기 출력이 요청과 다르거나 Error 면 notApplied")
  func setNightModeNotApplied() async throws {
    let harness = try AndroidEmulatorClientImplAppTests.booted()
    defer { harness.cleanUp() }
    harness.adb.onApp { _ in Self.result(0, stdout: "Night mode: no\n") }
    #expect(try await harness.client.setNightMode(.dark, on: Self.pixel) == .notApplied)

    harness.adb.onApp { _ in Self.result(255, stderr: "Error: mode must be 'yes', 'no', or 'auto'\n") }
    #expect(try await harness.client.setNightMode(.dark, on: Self.pixel) == .notApplied)

    harness.adb.onApp { _ in Self.result(1, stderr: "adb: device offline\n") }
    #expect(await thrownError { _ = try await harness.client.setNightMode(.dark, on: Self.pixel) } == .deviceNotBooted)
  }

  @Test("외관: 쓰기 출력에 Night mode 줄이 없으면 한 번 다시 읽어 판정한다")
  func setNightModeRereads() async throws {
    let harness = try AndroidEmulatorClientImplAppTests.booted()
    defer { harness.cleanUp() }
    harness.adb.onApp { arguments in
      arguments == Self.nightRead ? Self.result(0, stdout: "Night mode: yes\n") : Self.result(0)
    }
    #expect(try await harness.client.setNightMode(.dark, on: Self.pixel) == .applied)
    #expect(AndroidEmulatorClientImplAppTests.appCalls(harness) == [Self.nightRead + ["yes"], Self.nightRead])

    harness.adb.onApp { arguments in
      arguments == Self.nightRead ? Self.result(0, stdout: "Night mode: auto\n") : Self.result(0)
    }
    #expect(try await harness.client.setNightMode(.light, on: Self.pixel) == .notApplied)
  }

  @Test("위치: emu geo fix <경도> <위도>, OK → applied, KO → notApplied, 둘 다 없으면 notApplied")
  func setLocation() async throws {
    let harness = try AndroidEmulatorClientImplAppTests.booted()
    defer { harness.cleanUp() }
    let coordinate = try #require(GeoCoordinate(latitude: -33.8688, longitude: 151.2093))
    harness.adb.onApp { _ in Self.result(0, stdout: "OK\r\n") }

    #expect(try await harness.client.setLocation(coordinate, on: Self.pixel) == .applied)
    #expect(AndroidEmulatorClientImplAppTests.appCalls(harness) == [
      ["-s", "emulator-5554", "emu", "geo", "fix", "151.2093", "-33.8688"],
    ])

    harness.adb.onApp { _ in Self.result(0, stdout: "KO: invalid latitude value\r\n") }
    #expect(try await harness.client.setLocation(coordinate, on: Self.pixel) == .notApplied)

    harness.adb.onApp { _ in Self.result(0) }
    #expect(try await harness.client.setLocation(coordinate, on: Self.pixel) == .notApplied)

    harness.adb.onApp { _ in Self.result(1, stderr: "error: could not connect to TCP port 5554\n") }
    #expect(await thrownError { _ = try await harness.client.setLocation(coordinate, on: Self.pixel) } ==
      .adbUnavailable)
  }
}
