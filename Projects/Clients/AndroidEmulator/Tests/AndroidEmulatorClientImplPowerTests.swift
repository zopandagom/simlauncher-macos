import AndroidEmulatorInterface
import CommandTesting
import Core
import Foundation
import Testing
@testable import AndroidEmulatorImpl

/// `boot(_:)`: emulator 는 `CommandClientFake.launch`, 잠금은 테스트의 `flock`, adb 는 흉내. 간격·제한은 짧게 줄였다.
struct AndroidEmulatorClientImplPowerTests {
  static let pixel = AndroidVirtualDevice.ID("Pixel")

  // MARK: - 켜기

  @Test("꺼진 기기: emulator 를 정해진 인자·환경으로 띄우고 sys.boot_completed=1 까지 기다린다")
  func bootLaunchesAndWaits() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("Pixel")
    let adb = harness.adb
    harness.processes.onLaunch { _, _ in adb.set("emulator-5554", FakeADB.Emulator(name: "Pixel")) }

    try await harness.client.boot(Self.pixel)

    let launches = harness.launches
    #expect(launches.count == 1)
    #expect(launches.first?.executable.path(percentEncoded: false) == FileFacts
      .path(harness.sdk) + "/emulator/emulator")
    #expect(launches.first?.arguments == ["-avd", "Pixel", "-no-metrics", "-crash-report-mode", "disabled"])
    #expect(launches.first?.environment == [
      "HOME": FileFacts.path(harness.home),
      "ANDROID_EMULATOR_WAIT_TIME_BEFORE_KILL": "120",
    ])
  }

  @Test("띄우기 전에 emulator 와 같은 HOME 으로 adb devices 를 한 번 부른다 (adb 가 먼저 adbkey 를 만들게)")
  func bootCallsADBBeforeLaunch() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("Pixel")
    let adb = harness.adb
    harness.processes.onLaunch { _, _ in adb.set("emulator-5554", FakeADB.Emulator(name: "Pixel")) }

    try await harness.client.boot(Self.pixel)

    let invocations = harness.command.invocations
    let devicesIndex = invocations.firstIndex { !$0.isLaunch && $0.arguments == ["devices"] }
    let launchIndex = invocations.firstIndex(where: \.isLaunch)
    let devices = try #require(devicesIndex)
    let launch = try #require(launchIndex)
    #expect(devices < launch)
    #expect(invocations[devices].executable.path(percentEncoded: false) == FileFacts
      .path(harness.sdk) + "/platform-tools/adb")
    #expect(invocations[devices].environment == ["HOME": FileFacts.path(harness.home), "ADB_MDNS": "0"])
  }

  @Test("띄우기 전 adb devices 가 실패해도 켜기는 이어진다")
  func bootContinuesWhenADBFailsBeforeLaunch() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("Pixel")
    let adb = harness.adb
    adb.setDevicesFail(true)
    // 처리기는 실패 여부를 읽은 뒤 불리므로 첫 호출만 실패한다.
    adb.onDevices { adb.setDevicesFail(false) }
    harness.processes.onLaunch { _, _ in adb.set("emulator-5554", FakeADB.Emulator(name: "Pixel")) }

    try await harness.client.boot(Self.pixel)

    let invocations = harness.command.invocations
    let launchIndex = invocations.firstIndex(where: \.isLaunch)
    let launch = try #require(launchIndex)
    #expect(harness.launches.count == 1)
    #expect(invocations[..<launch].count { $0.arguments == ["devices"] } == 1)
  }

  @Test("띄우기 전 adb devices 중에 취소되면 띄우지 않고 cancelled")
  func bootCancelledDuringADBBeforeLaunch() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("Pixel")
    let client = harness.client
    // 처리기는 boot 를 부른 Task 안에서 동기로 불린다.
    harness.adb.onDevices { withUnsafeCurrentTask { $0?.cancel() } }

    let task = Task { await thrownError { try await client.boot(Self.pixel) } }
    #expect(try await waitUntil { harness.devicesCallCount >= 1 })
    #expect(await task.value == .cancelled)
    #expect(harness.launches.isEmpty)
  }

  @Test("이미 잠금이 있으면 띄우지 않고 완료를 기다린다")
  func bootWaitsForRunningLock() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.locks.hold(harness.addDevice("Pixel"))
    harness.adb.set("emulator-5554", FakeADB.Emulator(name: "Pixel"))

    try await harness.client.boot(Self.pixel)
    #expect(harness.launches.isEmpty)
  }

  @Test("쓸 수 없는 기기·없는 기기는 띄우지 않는다")
  func bootRejectsUnavailable() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("My Phone")

    let unsupported = await thrownError { try await harness.client.boot(AndroidVirtualDevice.ID("My Phone")) }
    #expect(unsupported == .deviceUnavailable(.unsupportedName))
    #expect(await thrownError { try await harness.client.boot(Self.pixel) } == .deviceNotFound)
    #expect(harness.launches.isEmpty)
  }

  @Test("띄우지 못하면 emulatorLaunchFailed")
  func bootLaunchFails() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("Pixel")
    harness.processes.setLaunchFails(true)

    #expect(await thrownError { try await harness.client.boot(Self.pixel) } == .emulatorLaunchFailed)
  }

  @Test("완료 전에 프로세스가 끝나고 잠금도 없으면 emulatorExited(종료 상태)")
  func bootProcessExits() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("Pixel")
    harness.processes.onLaunch { _, exit in exit(1) }

    #expect(await thrownError { try await harness.client.boot(Self.pixel) } == .emulatorExited(1))
  }

  @Test("앱 프로세스가 끝났어도 다른 프로세스가 잠금을 잡고 있으면 그 완료를 기다린다")
  func bootProcessExitsButOtherHoldsLock() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let folder = try harness.addDevice("Pixel")
    let (adb, locks) = (harness.adb, harness.locks)
    harness.processes.onLaunch { _, exit in
      locks.hold(folder)
      exit(1)
      adb.set("emulator-5554", FakeADB.Emulator(name: "Pixel"))
    }

    try await harness.client.boot(Self.pixel)
  }

  @Test("띄우지 않고 기다리는 중 잠금이 풀리고 앱 프로세스도 없으면 emulatorExited(nil)")
  func bootWaitingLockReleased() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let folder = try harness.addDevice("Pixel")
    harness.locks.hold(folder)
    let locks = harness.locks
    harness.adb.onDevices { locks.release(folder) }

    #expect(await thrownError { try await harness.client.boot(Self.pixel) } == .emulatorExited(nil))
    #expect(harness.launches.isEmpty)
  }

  @Test("제한 시간이 지나면 bootTimedOut 이고 에뮬레이터를 끄지 않는다")
  func bootTimesOut() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("Pixel")
    harness.adb.set("emulator-5554", FakeADB.Emulator(name: "Pixel", bootCompleted: false))

    #expect(await thrownError { try await harness.client.boot(Self.pixel) } == .bootTimedOut)
    #expect(harness.command.interrupts.isEmpty)
    #expect(harness.adbCalls.allSatisfy { $0 != ["-s", "emulator-5554", "emu", "kill"] })
  }

  @Test("Task 취소는 기다림만 멈추고 cancelled (에뮬레이터를 끄지 않는다)")
  func bootCancelled() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("Pixel")
    let client = harness.client

    let task = Task { await thrownError { try await client.boot(Self.pixel) } }
    // 띄운 뒤(기다림 중) 취소한다.
    #expect(try await waitUntil { harness.launches.count == 1 })
    task.cancel()
    #expect(await task.value == .cancelled)
    #expect(harness.launches.count == 1)
    #expect(harness.command.interrupts.isEmpty)
  }
}
