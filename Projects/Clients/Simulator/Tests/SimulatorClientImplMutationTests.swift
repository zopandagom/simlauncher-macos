import Core
import Foundation
import SimulatorInterface
import Testing
@testable import SimulatorImpl

/// create·delete·erase 의 사전 확인과 실행. 목록은 `simctl-list` 픽스처다.
struct SimulatorClientImplMutationTests {
  enum Mutation: String, CaseIterable, Sendable {
    case delete, erase
  }

  struct Failure: Sendable, CustomTestStringConvertible {
    let exitCode: Int32
    let stderr: String
    let expected: SimulatorError

    var testDescription: String {
      "\(self.exitCode)"
    }
  }

  private static let list = ["simctl", "list", "-j"]
  private static let iOS27 = DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.iOS-27-0")
  private static let iOS25Unavailable = DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.iOS-25-0")
  private static let iPhone17 = DeviceType.ID("com.apple.CoreSimulator.SimDeviceType.iPhone-17")
  private static let watch = DeviceType.ID("com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-11-46mm")
  private static let createdUDID = "B66201ED-154C-4F97-A6C7-C88F42E8D3A7"
  private static let developer = URL(filePath: "/X/Xcode.app/Contents/Developer", directoryHint: .isDirectory)
  /// P8c 실측 stderr.
  private static let incompatible =
    "An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=403):\n"
      + "Incompatible device\n"

  // MARK: - create

  @Test("create 는 목록을 읽은 뒤 -- 뒤에 정리한 이름을 넘기고 UDID 를 돌려준다")
  func createSuccess() async throws {
    let runner = try Self.runner(command: .success(Data("\(Self.createdUDID)\n".utf8)))

    let id = try await Self.client(runner).create(
      name: "  테스트 iPhone \n",
      deviceType: Self.iPhone17,
      runtime: Self.iOS27
    )

    #expect(id == VirtualDevice.ID(Self.createdUDID))
    #expect(runner.invocations.map(\.arguments) == [
      Self.list,
      ["simctl", "create", "--", "테스트 iPhone", Self.iPhone17.rawValue, Self.iOS27.rawValue],
    ])
  }

  @Test("옵션처럼 보이는 이름도 -- 뒤에 그대로 넘긴다")
  func createDashName() async throws {
    let runner = try Self.runner(command: .success(Data("\(Self.createdUDID)\n".utf8)))

    _ = try await Self.client(runner).create(name: "-h", deviceType: Self.iPhone17, runtime: Self.iOS27)

    #expect(runner.invocations.last?.arguments == [
      "simctl", "create", "--", "-h", Self.iPhone17.rawValue, Self.iOS27.rawValue,
    ])
  }

  @Test(
    "이름에 문제가 있으면 provider·프로세스 없이 invalidDeviceName",
    arguments: ["", "  ", "a\nb", String(repeating: "a", count: 101)]
  )
  func createInvalidName(name: String) async throws {
    let runner = try Self.runner(command: .success())
    let counter = ProviderCounter(returning: Self.developer)
    let client = Self.client(runner, provider: counter)

    await #expect(throws: SimulatorError.invalidDeviceName) {
      try await client.create(name: name, deviceType: Self.iPhone17, runtime: Self.iOS27)
    }
    #expect(runner.invocations.isEmpty)
    #expect(counter.calls == 0)
  }

  @Test(
    "만들 수 없는 조합이면 목록만 읽고 creationOptionUnavailable",
    arguments: [
      (Self.iOS27, DeviceType.ID("com.apple.CoreSimulator.SimDeviceType.NoSuch")),
      (DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.iOS-99-0"), Self.iPhone17),
      (Self.iOS27, Self.watch),
      (Self.iOS25Unavailable, Self.iPhone17),
    ]
  )
  func createUnavailableOption(runtime: DeviceRuntime.ID, deviceType: DeviceType.ID) async throws {
    let runner = try Self.runner(command: .success())

    await #expect(throws: SimulatorError.creationOptionUnavailable) {
      try await Self.client(runner).create(name: "A", deviceType: deviceType, runtime: runtime)
    }
    #expect(runner.invocations.map(\.arguments) == [Self.list])
  }

  @Test("create 가 147 Incompatible device 로 실패하면 creationOptionUnavailable 이고 재조회하지 않는다")
  func createIncompatible() async throws {
    let runner = try Self.runner(command: .failure(147, Self.incompatible))

    await #expect(throws: SimulatorError.creationOptionUnavailable) {
      try await Self.client(runner).create(name: "A", deviceType: Self.iPhone17, runtime: Self.iOS27)
    }
    #expect(runner.invocations.count == 2)
  }

  @Test("create 가 성공했지만 stdout 이 UDID 가 아니면 creationResultUnknown", arguments: ["", "garbage\n"])
  func createResultUnknown(stdout: String) async throws {
    let runner = try Self.runner(command: .success(Data(stdout.utf8)))

    await #expect(throws: SimulatorError.creationResultUnknown) {
      try await Self.client(runner).create(name: "A", deviceType: Self.iPhone17, runtime: Self.iOS27)
    }
  }

  @Test("사전 목록의 JSON 을 해석하지 못하면 unexpectedOutput 이고 create 는 실행하지 않는다")
  func createListBrokenJSON() async {
    let runner = StubCommandRunner { _ in .success(Data("oops".utf8)) }

    await #expect(throws: SimulatorError.unexpectedOutput) {
      try await Self.client(runner).create(name: "A", deviceType: Self.iPhone17, runtime: Self.iOS27)
    }
    #expect(runner.invocations.map(\.arguments) == [Self.list])
  }

  @Test("목록 읽기가 실패하면 분류한 에러이고 create 는 실행하지 않는다")
  func createListFailure() async {
    let runner = StubCommandRunner { _ in .failure(72, "xcrun: error: unable to find utility \"simctl\"") }

    await #expect(throws: SimulatorError.developerToolsUnavailable) {
      try await Self.client(runner).create(name: "A", deviceType: Self.iPhone17, runtime: Self.iOS27)
    }
    #expect(runner.invocations.map(\.arguments) == [Self.list])
  }

  @Test("create 는 provider 를 한 번 부르고 목록·실행이 같은 DEVELOPER_DIR 를 쓴다")
  func createUsesOneDirectory() async throws {
    let runner = try Self.runner(command: .success(Data("\(Self.createdUDID)\n".utf8)))
    let counter = ProviderCounter(returning: Self.developer)

    _ = try await Self.client(runner, provider: counter).create(
      name: "A",
      deviceType: Self.iPhone17,
      runtime: Self.iOS27
    )

    #expect(counter.calls == 1)
    #expect(runner.invocations.count == 2)
    #expect(runner.invocations.allSatisfy { $0.environment == ["DEVELOPER_DIR": "/X/Xcode.app/Contents/Developer/"] })
  }

  // MARK: - delete·erase

  @Test(
    "UDID 형식이 아니면 provider·프로세스 없이 deviceNotFound",
    arguments: Mutation.allCases,
    ["-h", "all", "unavailable", ""]
  )
  func invalidUDID(mutation: Mutation, raw: String) async throws {
    let runner = try Self.runner(command: .success())
    let counter = ProviderCounter(returning: Self.developer)

    await #expect(throws: SimulatorError.deviceNotFound) {
      try await Self.perform(mutation, VirtualDevice.ID(raw), on: Self.client(runner, provider: counter))
    }
    #expect(runner.invocations.isEmpty)
    #expect(counter.calls == 0)
  }

  @Test("꺼진 기기는 목록을 읽은 뒤 대문자 UDID 로 실행하고, provider 는 한 번이다", arguments: Mutation.allCases)
  func shutdownDevice(mutation: Mutation) async throws {
    let runner = try Self.runner(command: .success())
    let counter = ProviderCounter(returning: Self.developer)

    try await Self.perform(
      mutation,
      VirtualDevice.ID("00000000-0000-0000-0000-000000000002"),
      on: Self.client(runner, provider: counter)
    )

    #expect(runner.invocations.map(\.arguments) == [
      Self.list,
      ["simctl", mutation.rawValue, "00000000-0000-0000-0000-000000000002"],
    ])
    #expect(counter.calls == 1)
    #expect(runner.invocations.allSatisfy { $0.environment == ["DEVELOPER_DIR": "/X/Xcode.app/Contents/Developer/"] })
  }

  @Test("목록에 없는 기기는 목록만 읽고 deviceNotFound", arguments: Mutation.allCases)
  func missingDevice(mutation: Mutation) async throws {
    let runner = try Self.runner(command: .success())

    await #expect(throws: SimulatorError.deviceNotFound) {
      try await Self.perform(
        mutation,
        VirtualDevice.ID("00000000-0000-4000-8000-0000000000FF"),
        on: Self.client(runner)
      )
    }
    #expect(runner.invocations.map(\.arguments) == [Self.list])
  }

  @Test(
    "켜짐·끄는 중·모르는 상태의 기기는 실행하지 않고 deviceNotShutdown",
    arguments: Mutation.allCases,
    [
      "00000000-0000-0000-0000-000000000001",
      "00000000-0000-0000-0000-000000000003",
      "00000000-0000-0000-0000-000000000004",
    ]
  )
  func notShutdown(mutation: Mutation, udid: String) async throws {
    let runner = try Self.runner(command: .success())

    await #expect(throws: SimulatorError.deviceNotShutdown) {
      try await Self.perform(mutation, VirtualDevice.ID(udid), on: Self.client(runner))
    }
    #expect(runner.invocations.map(\.arguments) == [Self.list])
  }

  @Test(
    "실행이 실패하면 분류한 에러이고 재조회하지 않는다",
    arguments: Mutation.allCases,
    [
      Failure(
        exitCode: 148,
        stderr: "Invalid device: 00000000-0000-0000-0000-000000000002\n",
        expected: .deviceNotFound
      ),
      Failure(
        exitCode: 149,
        stderr: "An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=405):\n"
          + "Unable to erase contents and settings in current state: Booted\n",
        expected: .commandFailed
      ),
    ]
  )
  func commandFailure(mutation: Mutation, failure: Failure) async throws {
    let runner = try Self.runner(command: .failure(failure.exitCode, failure.stderr))

    await #expect(throws: failure.expected) {
      try await Self.perform(
        mutation,
        VirtualDevice.ID("00000000-0000-0000-0000-000000000002"),
        on: Self.client(runner)
      )
    }
    #expect(runner.invocations.count == 2)
  }

  @Test(
    "쓸 수 없는 꺼진 기기도 delete 는 사전 확인을 통과해 실행한다",
    arguments: ["00000000-0000-0000-0000-000000000005", "00000000-0000-0000-0000-000000000009"]
  )
  func deleteUnavailableShutdown(udid: String) async throws {
    let runner = try Self.runner(command: .success())

    try await Self.client(runner).delete(VirtualDevice.ID(udid))

    #expect(runner.invocations.map(\.arguments) == [Self.list, ["simctl", "delete", udid]])
  }

  // MARK: - 도움 함수

  /// `list` 는 픽스처, 그 밖의 명령은 `command` 결과를 돌려준다.
  private static func runner(command: CommandResult) throws -> StubCommandRunner {
    let fixture = try Fixture.data("simctl-list")
    return StubCommandRunner { invocation in
      invocation.arguments == Self.list ? .success(fixture) : command
    }
  }

  private static func client(_ runner: StubCommandRunner, provider: ProviderCounter? = nil) -> SimulatorClientImpl {
    SimulatorClientImpl(
      developerDirectory: provider.map { counter in { @Sendable in counter.provide() } },
      runner: runner,
      fileExists: { _ in false },
      baseEnvironment: [:]
    )
  }

  private static func perform(
    _ mutation: Mutation,
    _ id: VirtualDevice.ID,
    on client: SimulatorClientImpl
  ) async throws(SimulatorError) {
    switch mutation {
    case .delete: try await client.delete(id)
    case .erase: try await client.erase(id)
    }
  }
}
