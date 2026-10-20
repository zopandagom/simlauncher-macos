import Core
import Foundation
import SimulatorInterface
import Testing
@testable import SimulatorImpl

struct SimctlRuntimeListDecoderTests {
  @Test("실측 형태의 출력에서 iOS 2개·watchOS 1개 이미지의 필드를 읽는다")
  func decodesFixture() throws {
    let images = try SimctlRuntimeListDecoder.images(from: Fixture.data("simctl-runtime-list"))

    #expect(images == [
      RuntimeImage(
        id: RuntimeImage.ID("00000000-0000-0000-0002-000000000001"),
        runtimeID: DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.iOS-27-0"),
        platform: .iOS,
        version: OSVersion(major: 27, minor: 0),
        build: "24A434",
        state: .ready,
        sizeBytes: 8_067_000_161
      ),
      RuntimeImage(
        id: RuntimeImage.ID("00000000-0000-0000-0002-000000000002"),
        runtimeID: DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.iOS-27-1"),
        platform: .iOS,
        version: OSVersion(major: 27, minor: 1),
        build: "24A94425",
        state: .ready,
        sizeBytes: 7_874_743_137
      ),
      RuntimeImage(
        id: RuntimeImage.ID("00000000-0000-0000-0002-000000000003"),
        runtimeID: DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.watchOS-27-0"),
        platform: .watchOS,
        version: OSVersion(major: 27, minor: 0),
        build: "24R362",
        state: .ready,
        sizeBytes: 3_814_435_665
      ),
    ])
  }

  @Test(
    "state 문자열을 묶는다",
    arguments: [
      ("Ready", RuntimeImage.State.ready),
      ("Copying", .preparing),
      ("Verifying", .preparing),
      ("Reading", .preparing),
      ("Expanding", .preparing),
      ("Mounting", .preparing),
      ("Unusable", .unusable),
      ("Deleting", .removing),
      ("Unmounting", .removing),
      ("ready", .unknown),
      ("Something New", .unknown),
    ] as [(String, RuntimeImage.State)]
  )
  func states(raw: String, expected: RuntimeImage.State) {
    #expect(SimctlRuntimeListDecoder.state(raw) == expected)
  }

  @Test(
    "platformIdentifier 로 플랫폼을 정한다",
    arguments: [
      ("com.apple.platform.iphonesimulator", DevicePlatform.iOS),
      ("com.apple.platform.watchsimulator", .watchOS),
      ("com.apple.platform.appletvsimulator", .tvOS),
      ("com.apple.platform.xrsimulator", .visionOS),
      ("com.apple.platform.iphoneos", .other),
      ("", .other),
    ] as [(String, DevicePlatform)]
  )
  func platforms(raw: String, expected: DevicePlatform) {
    #expect(SimctlRuntimeListDecoder.platform(raw) == expected)
  }

  @Test("필수 키가 없거나 version 을 읽지 못한 항목·사전이 아닌 항목은 빼고 나머지를 돌려준다")
  func skipsBrokenEntries() throws {
    let json = """
    {
      "A" : { "identifier" : "A", "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-27-1",
              "platformIdentifier" : "com.apple.platform.iphonesimulator", "version" : "27.1",
              "build" : "24A94425", "state" : "Ready", "sizeBytes" : 1 },
      "B" : { "identifier" : "B", "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
              "platformIdentifier" : "com.apple.platform.iphonesimulator", "version" : "beta",
              "build" : "24A434", "state" : "Ready" },
      "C" : { "identifier" : "C", "platformIdentifier" : "com.apple.platform.iphonesimulator",
              "version" : "27.0", "build" : "24A434", "state" : "Ready" },
      "D" : { "identifier" : "D", "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
              "platformIdentifier" : "com.apple.platform.iphonesimulator", "version" : "27.0",
              "build" : "24A434" },
      "E" : "not an object",
      "F" : { "identifier" : 7, "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
              "platformIdentifier" : "com.apple.platform.iphonesimulator", "version" : "27.0",
              "build" : "24A434", "state" : "Ready" }
    }
    """

    let images = try SimctlRuntimeListDecoder.images(from: Data(json.utf8))

    #expect(images.map(\.id.rawValue) == ["A"])
  }

  @Test("sizeBytes·lastUsedAt 이 없거나 sizeBytes 형식이 달라도 항목을 읽는다 (크기만 nil)")
  func optionalFields() throws {
    let json = """
    {
      "A" : { "identifier" : "A", "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-27-1",
              "platformIdentifier" : "com.apple.platform.iphonesimulator", "version" : "27.1",
              "build" : "24A94425", "state" : "Copying" },
      "B" : { "identifier" : "B", "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-27-1",
              "platformIdentifier" : "com.apple.platform.iphonesimulator", "version" : "27.1",
              "build" : "24A94425", "state" : "Ready", "sizeBytes" : "big" }
    }
    """

    let images = try SimctlRuntimeListDecoder.images(from: Data(json.utf8))

    #expect(images.map(\.id.rawValue) == ["A", "B"])
    #expect(images.map(\.sizeBytes) == [nil, nil])
    #expect(images.first?.state == .preparing)
  }

  @Test("빈 사전이면 빈 목록")
  func emptyDictionary() throws {
    #expect(try SimctlRuntimeListDecoder.images(from: Data("{}".utf8)).isEmpty)
  }

  @Test("최상위가 사전이 아니거나 JSON 이 아니면 unexpectedOutput", arguments: ["[]", "[{}]", "\"Ready\"", "oops", ""])
  func notDictionary(output: String) {
    #expect(throws: SimulatorError.unexpectedOutput) {
      try SimctlRuntimeListDecoder.images(from: Data(output.utf8))
    }
  }

  @Test("결과는 런타임 식별자 → 버전 → 이미지 UUID 순으로 늘 같다")
  func sortedDeterministically() throws {
    let json = """
    {
      "Z" : { "identifier" : "Z", "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-27-1",
              "platformIdentifier" : "com.apple.platform.iphonesimulator", "version" : "27.1",
              "build" : "b1", "state" : "Ready" },
      "Y" : { "identifier" : "Y", "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-27-1",
              "platformIdentifier" : "com.apple.platform.iphonesimulator", "version" : "27.1.1",
              "build" : "b2", "state" : "Ready" },
      "X" : { "identifier" : "X", "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-27-1",
              "platformIdentifier" : "com.apple.platform.iphonesimulator", "version" : "27.1",
              "build" : "b3", "state" : "Ready" },
      "W" : { "identifier" : "W", "runtimeIdentifier" : "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
              "platformIdentifier" : "com.apple.platform.iphonesimulator", "version" : "27.0",
              "build" : "b4", "state" : "Ready" }
    }
    """
    let data = Data(json.utf8)

    let first = try SimctlRuntimeListDecoder.images(from: data)
    let second = try SimctlRuntimeListDecoder.images(from: data)

    #expect(first.map(\.id.rawValue) == ["W", "X", "Z", "Y"])
    #expect(first == second)
  }
}
