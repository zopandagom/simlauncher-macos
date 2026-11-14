import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Testing

/// Fake 의 테스트 조건: 설정한 결과·지금 값 바꾸기·호출 기록·멈춤.
struct AndroidEmulatorClientFakeConditionsTests {
  private static let pixel = AndroidVirtualDevice.ID("Pixel")

  @Test("기본 값은 라이트·위치 서비스 켜짐, 성공한 setNightMode 가 값을 바꾸고 호출을 기록한다")
  func readWrite() async throws {
    let fake = AndroidEmulatorClientFake()
    let coordinate = try #require(GeoCoordinate(latitude: 1, longitude: 2))

    #expect(try await fake.testConditions(on: Self.pixel) == AndroidEmulatorClientFake.defaultTestConditions)
    #expect(try await fake.setNightMode(.dark, on: Self.pixel) == .applied)
    #expect(fake.testConditions(for: Self.pixel).nightMode == .dark)
    #expect(try await fake.setLocation(coordinate, on: Self.pixel) == .applied)
    #expect(fake.calls == [
      .testCondition(.testConditions(Self.pixel)),
      .testCondition(.setNightMode(.dark, Self.pixel)),
      .testCondition(.setLocation(coordinate, Self.pixel)),
    ])
  }

  @Test("설정한 에러·결과: notApplied 는 값을 바꾸지 않는다")
  func configured() async throws {
    let fake = AndroidEmulatorClientFake()
    let coordinate = try #require(GeoCoordinate(latitude: 1, longitude: 2))
    fake.setTestConditions(AndroidTestConditions(nightMode: .other, locationEnabled: false), for: Self.pixel)

    fake.setNightModeResult(.success(.notApplied))
    #expect(try await fake.setNightMode(.dark, on: Self.pixel) == .notApplied)
    #expect(fake.testConditions(for: Self.pixel).nightMode == .other)

    fake.setNightModeResult(.failure(.deviceNotBooted))
    await #expect(throws: AndroidEmulatorError.deviceNotBooted) { try await fake.setNightMode(.dark, on: Self.pixel) }

    fake.setLocationResult(.success(.notApplied))
    #expect(try await fake.setLocation(coordinate, on: Self.pixel) == .notApplied)

    fake.setTestConditionsError(.adbUnavailable)
    await #expect(throws: AndroidEmulatorError.adbUnavailable) { try await fake.testConditions(on: Self.pixel) }
  }

  @Test("멈춘 호출은 기록만 하고 resumeConditions 까지 기다린다")
  func suspend() async throws {
    let fake = AndroidEmulatorClientFake()
    fake.suspendConditions()

    let task = Task { try await fake.testConditions(on: Self.pixel) }
    while fake.calls.isEmpty {
      await Task.yield()
    }
    #expect(fake.calls == [.testCondition(.testConditions(Self.pixel))])
    fake.resumeConditions()
    #expect(try await task.value == AndroidEmulatorClientFake.defaultTestConditions)
  }

  @Test("읽기만 멈추면 쓰기는 그대로 돌아오고, 읽기는 resumeConditionReads 뒤 쓴 값을 돌려준다")
  func suspendReadsOnly() async throws {
    let fake = AndroidEmulatorClientFake()
    fake.suspendConditionReads()

    let read = Task { try await fake.testConditions(on: Self.pixel) }
    while fake.calls.isEmpty {
      await Task.yield()
    }
    #expect(try await fake.setNightMode(.dark, on: Self.pixel) == .applied)
    fake.resumeConditionReads()
    #expect(try await read.value.nightMode == .dark)
  }
}
