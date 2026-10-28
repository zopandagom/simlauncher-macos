import AndroidEmulatorInterface
import CommandTesting
import Core
import Foundation
import Synchronization
import Testing
@testable import AndroidEmulatorImpl

/// `shutdown(_:)`: emu kill·SIGINT·잠금 풀림 기다리기. 켜기는 `AndroidEmulatorClientImplPowerTests`.
struct AndroidEmulatorClientImplShutdownTests {
  static let pixel = AndroidVirtualDevice.ID("Pixel")

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

  @Test("serial 도 앱 프로세스도 없고 adb 는 답하면 잠시 다시 찾은 뒤 잠금 풀림을 기다린다 (안 풀리면 shutdownTimedOut)")
  func shutdownWithoutSerial() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.locks.hold(harness.addDevice("Pixel"))

    #expect(await thrownError { try await harness.client.shutdown(Self.pixel) } == .shutdownTimedOut)
    #expect(harness.devicesCallCount > 2)
    #expect(harness.adbCalls.allSatisfy { !$0.contains("kill") })
    #expect(harness.command.interrupts.isEmpty)
  }

  @Test("다시 찾기 한도가 지난 뒤 잠금이 풀리면 성공 (앱 밖에서 끄는 중이라 이름에 답하지 않음)")
  func shutdownWaitsAfterSearchLimit() async throws {
    let harness = try Harness(timing: Harness.longShutdownTiming)
    defer { harness.cleanUp() }
    let folder = try harness.addDevice("Pixel")
    harness.locks.hold(folder)
    // adb 목록 1번째는 다시 읽기, 2번째는 다시 찾기의 첫 호출이다 (마감은 그 직전에 정해진다).
    // 2번째 호출을 그 시작 + 다시 찾기 한도 + 20ms 까지 붙잡으면, 끝날 때 마감이 지나 있어 그 호출이 다시 찾기의 마지막이 된다
    // (Impl 이 얼마나 느리든 같다. 시간 창에 기대지 않는다).
    let limit = Harness.longShutdownTiming.serialSearchLimit
    let calls = Mutex(0)
    let lastSearchCall = Mutex(false)
    harness.adb.onDevices {
      let index = calls.withLock { count in
        count += 1
        return count
      }
      guard index == 2 else {
        return
      }
      let wake = ContinuousClock.now.advanced(by: limit + .milliseconds(20))
      while ContinuousClock.now < wake {
        Thread.sleep(forTimeInterval: 0.005)
      }
      lastSearchCall.withLock { $0 = true }
    }
    let client = harness.client
    let start = ContinuousClock.now

    let task = Task { await thrownError { try await client.shutdown(Self.pixel) } }
    #expect(try await waitUntil(.seconds(5)) { lastSearchCall.withLock { $0 } })
    // 붙잡은 호출이 끝난 뒤 Impl 이 잠금을 확인하기 전에 풀면 `.released` 로도 성공해 규칙 A 를 거치지 않는다.
    // 그래서 조금 늦게 푼다. 이 대기는 성공·실패를 바꾸지 않고(언제 풀어도 성공) 규칙 A 를 거치게 할 뿐이다.
    try await Task.sleep(for: .milliseconds(50))
    harness.locks.release(folder)

    #expect(await task.value == nil)
    #expect(ContinuousClock.now - start < .seconds(5))
    #expect(harness.devicesCallCount == 2)
    #expect(harness.adbCalls.allSatisfy { !$0.contains("kill") })
    #expect(harness.command.interrupts.isEmpty)
  }

  @Test("adb 목록이 실패하면 다시 찾은 뒤 adbUnavailable (기다리지 않는다)")
  func shutdownSearchADBFails() async throws {
    let harness = try Harness(timing: Harness.longShutdownTiming)
    defer { harness.cleanUp() }
    try harness.locks.hold(harness.addDevice("Pixel"))
    harness.adb.setDevicesFail(true)
    let start = ContinuousClock.now

    #expect(await thrownError { try await harness.client.shutdown(Self.pixel) } == .adbUnavailable)
    #expect(ContinuousClock.now - start < .seconds(5))
    #expect(harness.devicesCallCount > 2)
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

  // MARK: - 끄기: emu kill 실패, 앱 프로세스 없음

  static let kill = ["-s", "emulator-5554", "emu", "kill"]

  /// `emu kill` 뒤에 `adb devices` 를 받았는지.
  static func devicesAfterKill(_ harness: Harness) -> Bool {
    harness.adbCalls.drop(while: { $0 != Self.kill }).contains(["devices"])
  }

  @Test("emu kill 이 실패해도 그 기기가 이름에 답하지 않으면 잠금 풀림을 기다리고, 풀리면 성공")
  func shutdownKillFailsWhileShuttingDownOutside() async throws {
    let harness = try Harness(timing: Harness.longShutdownTiming)
    defer { harness.cleanUp() }
    let folder = try harness.addDevice("Pixel")
    harness.locks.hold(folder)
    let adb = harness.adb
    adb.set("emulator-5554", FakeADB.Emulator(name: "Pixel"))
    adb.setKillFails(true)
    adb.onKill { serial in adb.set(serial, nil) }
    let client = harness.client
    let start = ContinuousClock.now

    let task = Task { await thrownError { try await client.shutdown(Self.pixel) } }
    // kill 뒤 adb 목록을 한 번 받은 뒤(기다림 단계) 푼다.
    #expect(try await waitUntil { Self.devicesAfterKill(harness) })
    try await Task.sleep(for: .milliseconds(50))
    harness.locks.release(folder)

    #expect(await task.value == nil)
    #expect(ContinuousClock.now - start < .seconds(5))
    #expect(harness.command.interrupts.isEmpty)
  }

  @Test("emu kill 이 실패하고 그 기기가 여전히 이름에 답하면 adbUnavailable")
  func shutdownKillFailsWhileAnswering() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let folder = try harness.addDevice("Pixel")
    harness.locks.hold(folder)
    harness.adb.set("emulator-5554", FakeADB.Emulator(name: "Pixel"))
    harness.adb.setKillFails(true)

    #expect(await thrownError { try await harness.client.shutdown(Self.pixel) } == .adbUnavailable)
    #expect(Self.devicesAfterKill(harness))
    #expect(AVDLock.isHeld(folder: folder) == true)
    #expect(harness.command.interrupts.isEmpty)
  }

  @Test("emu kill 이 실패하고 adb 목록도 실패하면 adbUnavailable")
  func shutdownKillFailsADBFails() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.locks.hold(harness.addDevice("Pixel"))
    let adb = harness.adb
    adb.set("emulator-5554", FakeADB.Emulator(name: "Pixel"))
    adb.setKillFails(true)
    adb.onKill { serial in
      adb.set(serial, nil)
      adb.setDevicesFail(true)
    }

    #expect(await thrownError { try await harness.client.shutdown(Self.pixel) } == .adbUnavailable)
    #expect(Self.devicesAfterKill(harness))
  }

  @Test("emu kill 이 실패했지만 잠금이 풀렸으면 성공")
  func shutdownKillFailsLockReleased() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let folder = try harness.addDevice("Pixel")
    harness.locks.hold(folder)
    harness.adb.set("emulator-5554", FakeADB.Emulator(name: "Pixel"))
    harness.adb.setKillFails(true)
    let locks = harness.locks
    harness.adb.onKill { _ in locks.release(folder) }

    try await harness.client.shutdown(Self.pixel)
    #expect(harness.adbCalls.last == Self.kill)
  }

  @Test("emu kill 이 실패하고 기기 폴더가 없어 잠금을 모르면, 이름에 답하는 기기는 adbUnavailable (성공으로 보지 않는다)")
  func shutdownKillFailsFolderMissing() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let gone = harness.directory.url.appending(path: "Gone.avd", directoryHint: .isDirectory)
    try harness.addDevice("Pixel", pointer: "path=\(FileFacts.path(gone))\n")
    // 잠금 있는 기기가 하나라도 있어야 목록 읽기가 adb 를 불러 대상의 serial 을 얻는다.
    try harness.locks.hold(harness.addDevice("Other"))
    harness.adb.set("emulator-5554", FakeADB.Emulator(name: "Pixel"))
    harness.adb.setKillFails(true)

    #expect(await thrownError { try await harness.client.shutdown(Self.pixel) } == .adbUnavailable)
    #expect(harness.adbCalls.contains(Self.kill))
  }

  @Test("emu kill 이 실패하고 기기 폴더가 없어 잠금을 모르면, 이름에 답하지 않아도 adbUnavailable (확인 없이 성공으로 보지 않는다)")
  func shutdownKillFailsFolderMissingUnanswered() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let gone = harness.directory.url.appending(path: "Gone.avd", directoryHint: .isDirectory)
    try harness.addDevice("Pixel", pointer: "path=\(FileFacts.path(gone))\n")
    // 잠금 있는 기기가 하나라도 있어야 목록 읽기가 adb 를 불러 대상의 serial 을 얻는다.
    try harness.locks.hold(harness.addDevice("Other"))
    let adb = harness.adb
    adb.set("emulator-5554", FakeADB.Emulator(name: "Pixel"))
    adb.setKillFails(true)
    adb.onKill { serial in adb.set(serial, nil) }

    #expect(await thrownError { try await harness.client.shutdown(Self.pixel) } == .adbUnavailable)
    #expect(harness.adbCalls.contains(Self.kill))
  }
}
