import AndroidEmulatorInterface
import CommandTesting
import Core
import Foundation
import Testing
@testable import AndroidEmulatorImpl

/// `boot(_:)`·`shutdown(_:)`: emulator 는 `CommandClientFake.launch`, 잠금은 테스트의 `flock`, adb 는 흉내. 간격·제한은 짧게 줄였다.
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
    try await Task.sleep(for: .milliseconds(50))
    task.cancel()
    #expect(await task.value == .cancelled)
    #expect(harness.launches.count == 1)
    #expect(harness.command.interrupts.isEmpty)
  }

  // MARK: - 끄기

  @Test("꺼진 기기는 명령 없이 성공")
  func shutdownAlreadyOff() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("Pixel")

    try await harness.client.shutdown(Self.pixel)
    #expect(harness.command.invocations.isEmpty)
  }

  @Test("serial 이 있으면 emu kill 뒤 잠금이 풀릴 때까지 기다린다")
  func shutdownKillsBySerial() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let folder = try harness.addDevice("Pixel")
    harness.locks.hold(folder)
    harness.adb.set("emulator-5554", FakeADB.Emulator(name: "Pixel"))
    let locks = harness.locks
    harness.adb.onKill { _ in locks.release(folder) }

    try await harness.client.shutdown(Self.pixel)
    #expect(harness.adbCalls.last == ["-s", "emulator-5554", "emu", "kill"])
    #expect(harness.command.interrupts.isEmpty)
  }

  @Test("serial 이 없고 이 앱이 띄운 프로세스면 SIGINT 를 보낸다")
  func shutdownInterruptsOwnProcess() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let folder = try harness.addDevice("Pixel")
    let (adb, locks, command) = (harness.adb, harness.locks, harness.command)
    harness.processes.onLaunch { _, _ in
      locks.hold(folder)
      adb.set("emulator-5554", FakeADB.Emulator(name: "Pixel"))
    }
    try await harness.client.boot(Self.pixel)
    adb.set("emulator-5554", nil)
    harness.processes.onInterrupt { process in
      locks.release(folder)
      command.exit(process, status: 0)
    }

    try await harness.client.shutdown(Self.pixel)
    #expect(harness.command.interrupts.count == 1)
    #expect(harness.adbCalls.allSatisfy { !$0.contains("kill") })
  }

  @Test("serial 도 앱 프로세스도 없으면 잠시 다시 찾은 뒤 adbUnavailable")
  func shutdownWithoutSerial() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.locks.hold(harness.addDevice("Pixel"))

    #expect(await thrownError { try await harness.client.shutdown(Self.pixel) } == .adbUnavailable)
    #expect(harness.adbCalls.count(where: { $0 == ["devices"] }) > 2)
  }

  @Test("serial 을 다시 찾는 중 잠금이 풀리면 성공")
  func shutdownLockReleasedWhileSearching() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let folder = try harness.addDevice("Pixel")
    harness.locks.hold(folder)
    let locks = harness.locks
    harness.adb.onDevices { locks.release(folder) }

    try await harness.client.shutdown(Self.pixel)
  }

  @Test("잠금이 풀리지 않으면 shutdownTimedOut")
  func shutdownTimesOut() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.locks.hold(harness.addDevice("Pixel"))
    harness.adb.set("emulator-5554", FakeADB.Emulator(name: "Pixel"))

    #expect(await thrownError { try await harness.client.shutdown(Self.pixel) } == .shutdownTimedOut)
  }
}
