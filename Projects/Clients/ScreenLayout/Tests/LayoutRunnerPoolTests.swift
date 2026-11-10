import CommandInterface
import Core
import DevEnvironmentTesting
import Foundation
import ScreenLayoutInterface
import SimulatorTesting
import Testing
@testable import ScreenLayoutImpl

/// 러너 수명: 감시·끄기 전후·켜짐 정리·취소·앱 종료.
@Suite(.timeLimit(.minutes(1)))
struct LayoutRunnerPoolTests {
  static let device = RunnerHarness.device

  // MARK: 감시

  @Test("감시: 러너 pid 가 죽으면 SIGTERM·uninstall, 다음 읽기는 다시 준비")
  func runnerDied() async throws {
    let harness = RunnerHarness()
    _ = try await harness.read().get()

    harness.killRunners()

    #expect(try await waitUntil { harness.uninstalls == [Self.device] })
    #expect(harness.command.terminates.count == 1)
    #expect(try await waitUntil { !harness.client.hasActiveIOSRunners })
    let phases = PhaseLog()
    _ = try await harness.read(phases: phases).get()
    #expect(phases.all == [.preparing, .reading])
  }

  @Test("감시: xcodebuild 가 스스로 끝나면(유휴) uninstall 만, quit·SIGTERM 없음")
  func xcodebuildExited() async throws {
    let harness = RunnerHarness()
    _ = try await harness.read().get()

    harness.exitAll()

    #expect(try await waitUntil { harness.uninstalls == [Self.device] })
    #expect(harness.command.terminates.isEmpty)
    #expect(harness.requests.map(\.command) == ["snapshot"])
    #expect(try await waitUntil { !harness.client.hasActiveIOSRunners })
  }

  @Test("읽은 응답 파일은 곧바로 지우고, 멈추면 요청·결과 번들도 지우되 ready.json 은 남긴다")
  func screenDataIsNotKept() async throws {
    let harness = RunnerHarness()
    _ = try await harness.read().get()
    let session = harness.root.appending(path: "sessions/\(Self.device.rawValue)", directoryHint: .isDirectory)
    let fileManager = FileManager.default
    func exists(_ name: String) -> Bool {
      fileManager.fileExists(atPath: session.appending(path: name).path(percentEncoded: false))
    }
    #expect(!exists(LayoutRunnerProtocol.responseFile))

    try Data("{}".utf8).write(to: session.appending(path: LayoutRunnerProtocol.requestFile))
    for folder in [LayoutRunnerProtocol.resultBundle, "DerivedData/Logs/Test"] {
      try fileManager.createDirectory(at: session.appending(path: folder), withIntermediateDirectories: true)
    }
    harness.exitAll()
    #expect(try await waitUntil { harness.uninstalls == [Self.device] })

    #expect(try fileManager.contentsOfDirectory(atPath: session.path(percentEncoded: false)) == [
      LayoutRunnerProtocol.readyFile,
    ])
  }

  @Test("감시가 알아채기 전에 xcodebuild 가 끝났으면 요청하지 않고 .preparing 뒤 새로 준비해 읽는다")
  func exitedBeforeMonitorNotices() async throws {
    var timing = RunnerHarness.timing
    timing.monitorInterval = .seconds(30)
    let harness = RunnerHarness(timing: timing)
    _ = try await harness.read().get()

    harness.exitAll()
    let phases = PhaseLog()
    _ = try await harness.read(phases: phases).get()

    #expect(phases.all == [.preparing, .reading])
    #expect(harness.uninstalls == [Self.device])
    #expect(harness.command.terminates.isEmpty)
  }

  // MARK: 끄기 전후

  @Test("끄기 직전: quit 로 멈추고 SIGTERM 없이 uninstall, 끄는 중 읽기는 기기 꺼짐, 끈 뒤 다시 준비")
  func willShutDownGraceful() async throws {
    let harness = RunnerHarness()
    _ = try await harness.read().get()

    await harness.client.iOSDeviceWillShutDown(Self.device)

    #expect(harness.requests.map(\.command) == ["snapshot", "quit"])
    #expect(harness.command.terminates.isEmpty)
    #expect(harness.uninstalls == [Self.device])
    #expect(!harness.client.hasActiveIOSRunners)
    #expect(await harness.read() == .failure(.deviceNotBooted))
    #expect(harness.launches.count == 1)

    await harness.client.iOSDeviceDidShutDown(Self.device)
    let phases = PhaseLog()
    _ = try await harness.read(phases: phases).get()
    #expect(phases.all == [.preparing, .reading])
  }

  @Test("SIGTERM 뒤에도 늦게 끝나는 xcodebuild 가 쓴 파일은 끝난 뒤 지운다 (ready.json 만 남는다)")
  func lateExitFilesAreRemoved() async throws {
    let harness = RunnerHarness()
    _ = try await harness.read().get()
    harness.update {
      $0.responder = { _ in .silent }
      $0.terminateExits = false
    }

    await harness.client.iOSDeviceWillShutDown(Self.device)
    #expect(harness.uninstalls == [Self.device])
    let session = harness.root.appending(path: "sessions/\(Self.device.rawValue)", directoryHint: .isDirectory)
    // 끝나며 결과 번들을 쓰는 xcodebuild 흉내.
    try FileManager.default.createDirectory(
      at: session.appending(path: LayoutRunnerProtocol.resultBundle), withIntermediateDirectories: true
    )
    harness.exitAll(status: 143)

    #expect(try await waitUntil {
      (try? FileManager.default.contentsOfDirectory(atPath: session.path(percentEncoded: false)))
        == [LayoutRunnerProtocol.readyFile]
    })
  }

  @Test("늦은 파일 정리는 그 뒤에 준비된 다른 세션의 폴더를 비우지 않고, 상태가 비면 비운다")
  func lateCleanupKeepsNewSession() async throws {
    let harness = RunnerHarness()
    _ = try await harness.read().get()
    let pool = harness.client.pool
    let session = harness.root.appending(path: "sessions/\(Self.device.rawValue)", directoryHint: .isDirectory)
    let marker = session.appending(path: LayoutRunnerProtocol.resultBundle)
    try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: true)

    await pool.removeScreenDataIfOwned(Self.device, owner: .stop(UUID()))
    await pool.removeScreenDataIfOwned(Self.device, owner: .attempt(UUID()))
    #expect(FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
    _ = try await harness.read().get()

    harness.exitAll()
    #expect(try await waitUntil { !harness.client.hasActiveIOSRunners })
    try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: true)
    await pool.removeScreenDataIfOwned(Self.device, owner: .stop(UUID()))
    #expect(!FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
  }

  @Test("끄기 직전: 러너가 quit 에 답하지 않으면 quitGrace 뒤 SIGTERM")
  func willShutDownIgnoresQuit() async throws {
    let harness = RunnerHarness()
    _ = try await harness.read().get()
    harness.update { $0.responder = { _ in .silent } }

    await harness.client.iOSDeviceWillShutDown(Self.device)

    #expect(harness.command.terminates.count == 1)
    #expect(harness.uninstalls == [Self.device])
  }

  @Test("준비 중(ready 대기) 끄기: SIGTERM, 기다리던 호출은 기기 꺼짐, 결과 번들을 지우고 uninstall")
  func willShutDownWhilePreparing() async throws {
    let harness = RunnerHarness(timing: Self.longReadyTiming)
    harness.update { $0.launch = .neverReady }
    let task = harness.readTask()
    #expect(try await waitUntil { harness.launches.count == 1 })
    let session = harness.root.appending(path: "sessions/\(Self.device.rawValue)", directoryHint: .isDirectory)
    let bundle = session.appending(path: LayoutRunnerProtocol.resultBundle)
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

    await harness.client.iOSDeviceWillShutDown(Self.device)

    #expect(harness.command.terminates.count == 1)
    #expect(await task.value == .failure(.deviceNotBooted))
    #expect(harness.uninstalls == [Self.device])
    #expect(!FileManager.default.fileExists(atPath: bundle.path(percentEncoded: false)))
  }

  static let longReadyTiming: IOSLayoutTiming = {
    var timing = RunnerHarness.timing
    timing.readyTimeout = .seconds(30)
    return timing
  }()

  @Test("빌드 대기 중 끄기: 빌드가 끝나기 전에 돌아오고, 빌드가 끝나도 launch 하지 않는다")
  func willShutDownWhileBuilding() async throws {
    let harness = RunnerHarness()
    let gate = Gate()
    harness.update { $0.buildGate = gate }
    let task = harness.readTask()
    #expect(try await waitUntil { harness.builds.count == 1 })

    await harness.client.iOSDeviceWillShutDown(Self.device)
    #expect(!gate.isOpen)
    gate.open()

    #expect(await task.value == .failure(.deviceNotBooted))
    #expect(harness.launches.isEmpty)
  }

  @Test("빌드 중 끄기 뒤 다시 켜고 읽으면 멈추기로 한 준비에 붙지 않고 끝나기를 기다려 새로 준비한다")
  func readAfterShutDownDuringBuildPreparesAgain() async throws {
    let harness = RunnerHarness()
    let gate = Gate()
    harness.update { $0.buildGate = gate }
    let first = harness.readTask()
    #expect(try await waitUntil { harness.builds.count == 1 })
    await harness.client.iOSDeviceWillShutDown(Self.device)
    await harness.client.iOSDeviceDidShutDown(Self.device)

    let phases = PhaseLog()
    let second = harness.readTask(phases: phases)
    try await Task.sleep(for: .milliseconds(50))
    gate.open()

    let firstResult = await first.value
    #expect((try? firstResult.get()) == nil)
    #expect(try await second.value.get().unit == .pt)
    #expect(phases.all == [.preparing, .reading])
    #expect(harness.launches.count == 1)
  }

  @Test("남은 러너 정리 중 끄기: 정리가 끝나도 launch 하지 않는다")
  func willShutDownWhileQuittingOrphan() async throws {
    let harness = RunnerHarness(timing: Self.slowOrphanTiming)
    try Self.writeOrphan(harness)
    let task = harness.readTask()
    #expect(try await waitUntil { harness.command.invocations.contains { $0.executable.path == "/bin/ps" } })

    await harness.client.iOSDeviceWillShutDown(Self.device)

    #expect(await task.value == .failure(.deviceNotBooted))
    #expect(harness.launches.isEmpty)
  }

  static let slowOrphanTiming: IOSLayoutTiming = {
    var timing = RunnerHarness.timing
    timing.orphanQuitWait = .milliseconds(500)
    return timing
  }()

  /// 세션 폴더에 살아 있는(quit 에 답하지 않는) 이전 러너의 ready.json 을 둔다.
  static func writeOrphan(_ harness: RunnerHarness) throws {
    let session = harness.root.appending(path: "sessions/\(Self.device.rawValue)")
    try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
    let ready = RunnerHarness.json(["protocol": 1, "session": "old", "pid": 4242, "scale": 3.0])
    try ready.write(to: session.appending(path: "ready.json"))
    harness.update { $0.alive[4242] = Self.device.rawValue }
  }

  @Test("launch 를 기다리는 사이 끄기: launch 가 돌아오자마자 SIGTERM, 호출 실패, uninstall")
  func willShutDownDuringLaunch() async {
    let harness = RunnerHarness(timing: Self.longReadyTiming)
    let client = harness.client
    harness.update { state in
      state.launch = .neverReady
      state.onLaunch = {
        let done = DispatchSemaphore(value: 0)
        Task.detached {
          await client.iOSDeviceWillShutDown(Self.device)
          done.signal()
        }
        done.wait()
      }
    }

    #expect(await harness.read() == .failure(.deviceNotBooted))
    #expect(harness.command.terminates.count == 1)
    #expect(harness.uninstalls == [Self.device])
  }

  @Test("준비 중 목록에서 기기가 꺼지면 SIGTERM·기기 꺼짐 (monitorInterval 안팎)")
  func deviceOffWhilePreparing() async throws {
    let harness = RunnerHarness(timing: Self.longReadyTiming)
    harness.update { $0.launch = .neverReady }
    let task = harness.readTask()
    #expect(try await waitUntil { harness.launches.count == 1 })
    let start = ContinuousClock.now

    harness.simulator.setInventory(RunnerHarness.inventory(state: .shutdown))

    #expect(await task.value == .failure(.deviceNotBooted))
    #expect(ContinuousClock.now - start < .seconds(2))
    #expect(harness.command.terminates.count == 1)
  }

  @Test("요청 중 기기가 꺼지고 러너가 죽으면 기기 꺼짐")
  func deviceOffWhileRequesting() async throws {
    let harness = RunnerHarness(timing: Self.longRequestTiming)
    _ = try await harness.read().get()
    harness.update { $0.responder = { _ in .silent } }
    let task = harness.readTask()
    #expect(try await waitUntil { harness.requests.count == 2 })

    harness.simulator.setInventory(RunnerHarness.inventory(state: .shutdown))
    harness.killRunners()

    #expect(await task.value == .failure(.deviceNotBooted))
  }

  static let longRequestTiming: IOSLayoutTiming = {
    var timing = RunnerHarness.timing
    timing.requestTimeout = .seconds(30)
    return timing
  }()
}

extension LayoutRunnerPoolTests {
  // MARK: 취소

  @Test("준비 중 호출 취소는 곧바로 cancelled, 준비는 계속해 다음 호출은 준비 없이 읽는다")
  func cancelWhilePreparing() async throws {
    let harness = RunnerHarness()
    let gate = Gate()
    harness.update { $0.buildGate = gate }
    let task = harness.readTask()
    #expect(try await waitUntil { harness.builds.count == 1 })

    task.cancel()
    #expect(await task.value == .failure(.cancelled))
    #expect(!gate.isOpen)

    gate.open()
    #expect(try await waitUntil { harness.launches.count == 1 })
    #expect(try await waitUntil { harness.hasLiveRunner })
    try await Task.sleep(for: .milliseconds(50))
    let phases = PhaseLog()
    _ = try await harness.read(phases: phases).get()
    #expect(phases.all == [.reading])
    #expect(harness.launches.count == 1)
  }

  @Test("준비 중 창을 닫고 다시 열면 둘째 호출이 .preparing 을 받고 같은 준비를 기다린다")
  func reopenWhilePreparing() async throws {
    let harness = RunnerHarness()
    let gate = Gate()
    harness.update { $0.buildGate = gate }
    let first = harness.readTask()
    #expect(try await waitUntil { harness.builds.count == 1 })
    first.cancel()
    #expect(await first.value == .failure(.cancelled))

    let phases = PhaseLog()
    let second = harness.readTask(phases: phases)
    #expect(try await waitUntil { phases.all == [.preparing] })
    gate.open()

    _ = try await second.value.get()
    #expect(phases.all == [.preparing, .reading])
    #expect(harness.builds.count == 1)
    #expect(harness.launches.count == 1)
  }

  // MARK: 켜짐 정리

  @Test("멈추는 중을 기다리는 호출 취소는 곧바로 cancelled, 멈춘 뒤에도 새 준비를 만들지 않는다")
  func cancelWhileWaitingForStop() async throws {
    let harness = RunnerHarness()
    _ = try await harness.read().get()
    harness.simulator.suspendUninstalls()
    let shutdown = Task { await harness.client.iOSDeviceWillShutDown(Self.device) }
    #expect(try await waitUntil { !harness.uninstalls.isEmpty })
    await harness.client.iOSDeviceDidShutDown(Self.device)
    let phases = PhaseLog()
    let task = harness.readTask(phases: phases)
    #expect(try await waitUntil { phases.all == [.preparing] })

    task.cancel()
    #expect(await task.value == .failure(.cancelled))
    harness.simulator.resumeUninstalls()
    await shutdown.value
    try await Task.sleep(for: .milliseconds(100))

    #expect(harness.launches.count == 1)
    #expect(!harness.client.hasActiveIOSRunners)
  }

  @Test("켜짐 정리: 처음 본 켜진 기기마다 한 번 uninstall, 꺼진 것으로 본 뒤 다시 켜지면 한 번 더")
  func cleaningOncePerBoot() async throws {
    let harness = RunnerHarness()
    let client = harness.client

    client.iOSDevicesListed(booted: [Self.device])
    #expect(try await waitUntil { harness.uninstalls.count == 1 })
    client.iOSDevicesListed(booted: [Self.device])
    try await Task.sleep(for: .milliseconds(100))
    #expect(harness.uninstalls.count == 1)

    client.iOSDevicesListed(booted: [])
    #expect(try await waitUntil { await harness.client.pool.cleanedThisBoot.isEmpty })
    client.iOSDevicesListed(booted: [Self.device])
    #expect(try await waitUntil { harness.uninstalls.count == 2 })
    #expect(!client.hasActiveIOSRunners)
  }

  @Test("켜짐 정리: 목록 알림은 정리를 기다리지 않는다, uninstall 실패는 조용히 끝난다")
  func cleaningDoesNotBlock() async throws {
    let harness = RunnerHarness()
    harness.simulator.suspendUninstalls()
    harness.simulator.setUninstallError(.deviceNotBooted)

    harness.client.iOSDevicesListed(booted: [Self.device])
    #expect(try await waitUntil { harness.uninstalls.count == 1 })
    harness.simulator.resumeUninstalls()

    try await Task.sleep(for: .milliseconds(50))
    harness.simulator.setUninstallError(nil)
    let phases = PhaseLog()
    _ = try await harness.read(phases: phases).get()
    #expect(phases.all == [.preparing, .reading])
  }

  @Test("밖에서 꺼져 uninstall 이 실패하면, 목록이 꺼짐을 보지 못하고 다시 켜진 것으로 읽어도 다시 정리한다")
  func failedUninstallCleansAgain() async throws {
    let harness = RunnerHarness()
    let client = harness.client
    _ = try await harness.read().get()
    client.iOSDevicesListed(booted: [Self.device])
    harness.simulator.setUninstallError(.deviceNotBooted)

    harness.killRunners()
    #expect(try await waitUntil { harness.uninstalls.count == 1 })
    #expect(try await waitUntil { !harness.client.hasActiveIOSRunners })

    harness.simulator.setUninstallError(nil)
    client.iOSDevicesListed(booted: [Self.device])
    #expect(try await waitUntil { harness.uninstalls.count == 2 })
  }

  @Test("켜짐 정리: 러너가 있는 기기·끄는 중인 기기·UDID 아닌 값은 정리하지 않는다")
  func cleaningSkips() async throws {
    let harness = RunnerHarness()
    _ = try await harness.read().get()
    harness.client.iOSDevicesListed(booted: [Self.device, VirtualDevice.ID("not-udid")])
    let other = SampleID.iPadOff
    await harness.client.iOSDeviceWillShutDown(other)
    harness.client.iOSDevicesListed(booted: [Self.device, other])
    try await Task.sleep(for: .milliseconds(100))

    #expect(harness.uninstalls.isEmpty)
  }

  @Test("정리 중 읽기: .preparing 을 알리고 정리(uninstall)가 끝난 뒤에야 launch 한다")
  func readWaitsForCleaning() async throws {
    let harness = RunnerHarness()
    harness.simulator.suspendUninstalls()
    harness.client.iOSDevicesListed(booted: [Self.device])
    #expect(try await waitUntil { harness.uninstalls.count == 1 })
    let phases = PhaseLog()
    let task = harness.readTask(phases: phases)
    #expect(try await waitUntil { phases.all == [.preparing] })
    try await Task.sleep(for: .milliseconds(50))
    #expect(harness.builds.isEmpty)

    harness.simulator.resumeUninstalls()

    _ = try await task.value.get()
    #expect(phases.all == [.preparing, .reading])
    #expect(harness.launches.count == 1)
  }

  @Test("목록 순번: 늦게 도착한 옛 목록은 버린다")
  func listedSequence() async throws {
    let harness = RunnerHarness()
    let pool = harness.client.pool

    await pool.devicesListed([], sequence: 2)
    await pool.devicesListed([Self.device], sequence: 1)
    try await Task.sleep(for: .milliseconds(50))
    #expect(harness.uninstalls.isEmpty)

    harness.client.iOSDevicesListed(booted: [Self.device])
    harness.client.iOSDevicesListed(booted: [])
    try await Task.sleep(for: .milliseconds(100))
    #expect(await pool.cleanedThisBoot.isEmpty)
  }

  // MARK: 남은 러너·앱 종료

  @Test("세션 폴더에 살아 있는 이전 러너가 있으면 launch 전에 quit 요청을 쓴다")
  func quitsOrphanBeforeLaunch() async throws {
    let harness = RunnerHarness()
    try Self.writeOrphan(harness)
    let session = harness.root.appending(path: "sessions/\(Self.device.rawValue)")
    let quitSeen = Gate()
    Task.detached {
      while !quitSeen.isOpen {
        if let data = try? Data(contentsOf: session.appending(path: "request.json")),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           object["command"] as? String == "quit"
        {
          harness.update { $0.alive[4242] = nil }
          quitSeen.open()
        }
        try? await Task.sleep(for: .milliseconds(5))
      }
    }

    _ = try await harness.read().get()

    #expect(quitSeen.isOpen)
    #expect(harness.launches.count == 1)
  }

  @Test("hasActiveIOSRunners: 준비 중·준비됨 true, 모두 멈춘 뒤 false. stopAll 은 상한 안에 돌아온다")
  func stopAll() async throws {
    let harness = RunnerHarness(timing: Self.longReadyTiming)
    #expect(!harness.client.hasActiveIOSRunners)
    _ = try await harness.read().get()
    #expect(harness.client.hasActiveIOSRunners)
    let other = VirtualDevice.ID("00000000-0000-0000-0000-000000000003")
    harness.simulator.setInventory(RunnerHarness.inventory(other, state: .booted))
    harness.update { $0.launch = .neverReady }
    let preparing = harness.readTask(other)
    #expect(try await waitUntil { harness.launches.count == 2 })
    let start = ContinuousClock.now

    await harness.client.stopAllIOSRunners()

    #expect(ContinuousClock.now - start < .seconds(2))
    #expect(await preparing.value == .failure(.inspectorSetupFailed))
    #expect(!harness.client.hasActiveIOSRunners)
    #expect(Set(harness.uninstalls) == [Self.device, other])
  }

  @Test("Xcode 를 바꾼 뒤 다른 기기가 새로 빌드해도, 옛 키로 준비 중인 기기의 빌드는 지우지 않는다")
  func preparingBuildIsKept() async throws {
    let harness = RunnerHarness(timing: Self.longReadyTiming)
    let other = VirtualDevice.ID("00000000-0000-0000-0000-000000000003")
    harness.simulator.setInventory(RunnerHarness.inventory(other, state: .booted))
    harness.update { $0.launch = .neverReady }
    let preparing = harness.readTask()
    #expect(try await waitUntil { harness.launches.count == 1 })
    let builds = harness.root.appending(path: "builds", directoryHint: .isDirectory)
    let oldBuilds = try FileManager.default.contentsOfDirectory(atPath: builds.path(percentEncoded: false))
    #expect(oldBuilds.count == 1)

    harness.devEnvironment.setStatus(.ready(.beta))
    harness.update { $0.launch = .serve }
    _ = try await harness.read(other).get()

    let after = try FileManager.default.contentsOfDirectory(atPath: builds.path(percentEncoded: false))
    #expect(Set(oldBuilds).isSubset(of: Set(after)))
    #expect(after.count == 2)
    await harness.client.stopAllIOSRunners()
    _ = await preparing.value
  }

  @Test("앱 종료로 모두 멈추기 시작한 뒤의 읽기는 준비하지 않는다 (xcodebuild 를 새로 띄우지 않는다)")
  func noPrepareAfterStopAll() async throws {
    let harness = RunnerHarness()
    _ = try await harness.read().get()
    await harness.client.stopAllIOSRunners()

    let phases = PhaseLog()
    #expect(await harness.read(phases: phases) == .failure(.inspectorSetupFailed))

    #expect(phases.all.isEmpty)
    #expect(harness.launches.count == 1)
    #expect(!harness.client.hasActiveIOSRunners)
  }
}
