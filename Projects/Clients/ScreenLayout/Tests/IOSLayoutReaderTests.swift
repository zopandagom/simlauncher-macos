import CommandInterface
import Core
import DevEnvironmentTesting
import Foundation
import ScreenLayoutInterface
import SimulatorTesting
import Testing
@testable import ScreenLayoutImpl

/// iOS 한 번 읽기 흐름 (Fake Command·Simulator·DevEnvironment + 흉내 러너). 시간 값은 `RunnerHarness.timing` 으로 줄였다.
@Suite(.timeLimit(.minutes(1)))
struct IOSLayoutReaderTests {
  @Test("첫 읽기: .preparing 뒤 .reading, 빌드·launch 한 번, 노드는 px·단위 pt·배율 3, 임시 PNG 는 지운다")
  func firstRead() async throws {
    let harness = RunnerHarness()
    harness.simulator.setRunningApplications(
      [AppBundleID("com.example.app"), AppBundleID(IOSLayoutRunner.appBundleID)].compactMap(\.self),
      for: RunnerHarness.device
    )
    let phases = PhaseLog()

    let snapshot = try await harness.read(phases: phases).get()

    #expect(phases.all == [.preparing, .reading])
    #expect(harness.builds.count == 1)
    #expect(harness.launches.count == 1)
    #expect(snapshot.deviceName == RunnerHarness.deviceName)
    #expect(snapshot.unit == .pt)
    #expect(snapshot.pixelsPerUnit == 3)
    #expect(snapshot.pixelSize == LayoutSize(width: 1206, height: 2622))
    #expect(snapshot.screenshotPNG == RunnerHarness.png)
    #expect(snapshot.appIdentifier == "com.example.app")
    #expect(!snapshot.isSystemScreen)
    #expect(snapshot.nodes.map(\.frame) == [
      LayoutRect(x: 0, y: 0, width: 1206, height: 2622),
      LayoutRect(x: 30, y: 60, width: 300, height: 132),
    ])
    #expect(snapshot.nodes.map(\.type) == ["Application", "Button"])
    // 러너 앱은 후보에서 뺀다.
    #expect(harness.requests.map(\.bundleIDs) == [["com.example.app"]])
    let file = try #require(harness.screenshotFiles.first)
    #expect(!FileManager.default.fileExists(atPath: file.path))
    #expect(harness.client.hasActiveIOSRunners)
  }

  @Test("빌드·launch 인자: 선택한 Xcode·세션 폴더·토큰·유휴 600초")
  func launchArguments() async throws {
    let harness = RunnerHarness()

    _ = try await harness.read().get()

    let build = try #require(harness.builds.first)
    #expect(build.executable.path == "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild")
    #expect(build.arguments.first == "build-for-testing")
    #expect(build.timeout == .seconds(5))
    let launch = try #require(harness.launches.first)
    let session = harness.root.appending(path: "sessions/\(RunnerHarness.device.rawValue)/")
    #expect(launch.arguments.first == "test-without-building")
    #expect(launch.arguments.contains("id=\(RunnerHarness.device.rawValue)"))
    #expect(launch.environment["TEST_RUNNER_SIMLAUNCHER_LAYOUT_DIR"] == session.path(percentEncoded: false))
    #expect(launch.environment["TEST_RUNNER_SIMLAUNCHER_LAYOUT_IDLE"] == "600")
    #expect(launch.environment["PATH"] == "/usr/bin:/bin")
    #expect(launch.environment["DEVELOPER_DIR"] == "/Applications/Xcode.app/Contents/Developer/")
  }

  @Test("두 번째 읽기: .reading 만, 빌드·launch 없음")
  func secondRead() async throws {
    let harness = RunnerHarness()
    _ = try await harness.read().get()
    let phases = PhaseLog()

    _ = try await harness.read(phases: phases).get()

    #expect(phases.all == [.reading])
    #expect(harness.builds.count == 1)
    #expect(harness.launches.count == 1)
    #expect(harness.requests.count == 2)
  }

  @Test("디스크에 빌드가 있으면 새 Client 도 빌드하지 않는다. xctestrun 이 둘이면 다시 빌드한다")
  func buildOnDisk() async throws {
    let first = RunnerHarness()
    _ = try await first.read().get()
    await first.client.stopAllIOSRunners()

    let second = RunnerHarness(root: first.root)
    _ = try await second.read().get()
    #expect(second.builds.isEmpty)
    await second.client.stopAllIOSRunners()

    let builds = first.root.appending(path: "builds")
    let key = try #require(try FileManager.default.contentsOfDirectory(atPath: builds.path).first)
    try Data().write(to: builds.appending(path: "\(key)/Products/Extra.xctestrun"))
    let third = RunnerHarness(root: first.root)
    _ = try await third.read().get()
    #expect(third.builds.count == 1)
    await third.client.stopAllIOSRunners()
  }

  @Test("빌드 결과가 xctestrun 둘이면 준비 실패, 빌드 폴더를 남기지 않는다")
  func buildTwoRuns() async throws {
    let harness = RunnerHarness()
    harness.update { $0.build = .twoRuns }

    #expect(await harness.read() == .failure(.inspectorSetupFailed))
    #expect(try FileManager.default.contentsOfDirectory(atPath: harness.root.appending(path: "builds").path).isEmpty)
  }

  @Test("빌드 실패 → 준비 실패, partial 폴더 없음, launch 없음")
  func buildFailure() async throws {
    let harness = RunnerHarness()
    harness.update { $0.build = .fail }

    #expect(await harness.read() == .failure(.inspectorSetupFailed))
    #expect(harness.launches.isEmpty)
    let entries = try FileManager.default.contentsOfDirectory(atPath: harness.root.appending(path: "builds").path)
    #expect(entries.isEmpty)
    #expect(!harness.client.hasActiveIOSRunners)
  }

  @Test("xcodebuild 를 시작하지 못하면 Xcode 문제 (빌드·launch 모두)")
  func launchFailed() async {
    let harness = RunnerHarness()
    harness.update { $0.build = .launchFailed }
    #expect(await harness.read() == .failure(.xcodeUnavailable))

    harness.update {
      $0.build = .succeed
      $0.launch = .launchFailed
    }
    #expect(await harness.read() == .failure(.xcodeUnavailable))
    #expect(harness.uninstalls.isEmpty)
  }

  @Test("ready 전에 xcodebuild 가 끝나면 준비 실패, uninstall")
  func exitBeforeReady() async {
    let harness = RunnerHarness()
    harness.update { $0.launch = .exitBeforeReady }

    #expect(await harness.read() == .failure(.inspectorSetupFailed))
    #expect(harness.uninstalls == [RunnerHarness.device])
    #expect(!harness.client.hasActiveIOSRunners)
  }

  @Test("ready 시간 초과 → SIGTERM·uninstall·준비 실패")
  func readyTimeout() async {
    let harness = RunnerHarness()
    harness.update { $0.launch = .neverReady }

    #expect(await harness.read() == .failure(.inspectorSetupFailed))
    #expect(harness.command.terminates.count == 1)
    #expect(harness.uninstalls == [RunnerHarness.device])
  }

  @Test("쓸 Xcode 가 없으면 아무것도 실행하지 않고 Xcode 문제")
  func noXcode() async {
    let harness = RunnerHarness()
    harness.devEnvironment.setStatus(.xcodeNotInstalled)

    #expect(await harness.read() == .failure(.xcodeUnavailable))
    #expect(harness.command.invocations.isEmpty)
    #expect(!harness.simulator.calls.contains(.fetchInventory))
  }

  @Test("기기 꺼짐·없음·쓸 수 없음·UDID 아님은 빌드·launch 없이 실패")
  func deviceStates() async {
    let harness = RunnerHarness()
    #expect(await harness.read(SampleID.iPhoneOff) == .failure(.deviceNotBooted))
    #expect(await harness.read(SampleID.unavailableIPhone) == .failure(.deviceUnavailable))
    #expect(await harness.read(VirtualDevice.ID("11111111-2222-3333-4444-555555555555")) == .failure(.deviceNotFound))
    #expect(await harness.read(VirtualDevice.ID("--help")) == .failure(.deviceNotFound))
    harness.simulator.setFetchError(.developerToolsUnavailable)
    #expect(await harness.read() == .failure(.xcodeUnavailable))
    #expect(harness.command.invocations.isEmpty)
  }

  @Test("러너 응답 실패: notForeground → 앞 앱 사라짐, snapshotFailed → unreadable")
  func runnerFailures() async {
    let harness = RunnerHarness()
    harness.update { $0.responder = { .data(RunnerHarness.json(["id": $0.id, "error": "notForeground"])) } }
    #expect(await harness.read() == .failure(.appNotInForeground))

    harness.update { $0.responder = { .data(RunnerHarness.json(["id": $0.id, "error": "snapshotFailed"])) } }
    #expect(await harness.read() == .failure(.unreadable))
    #expect(harness.launches.count == 1)
  }

  @Test("시스템 화면: SpringBoard 식별자와 isSystemScreen")
  func systemScreen() async throws {
    let harness = RunnerHarness()
    harness.update { state in
      state.responder = { RunnerHarness.snapshotReply($0, apps: ["com.apple.springboard"], system: true) }
    }

    let snapshot = try await harness.read().get()

    #expect(snapshot.isSystemScreen)
    #expect(snapshot.appIdentifier == "com.apple.springboard")
  }

  @Test("다른 id 의 응답은 무시하고 맞는 응답을 기다린다")
  func ignoresOtherID() async throws {
    let harness = RunnerHarness(timing: Self.longRequestTiming)
    harness.update { $0.responder = { _ in .data(RunnerHarness.json(["id": "other", "ok": true])) } }
    let task = harness.readTask()
    #expect(try await waitUntil { !harness.requests.isEmpty })
    try await Task.sleep(for: .milliseconds(50))
    // 늦게 맞는 id 의 응답이 오면 받아들인다.
    let request = try #require(harness.requests.first)
    let session = harness.root.appending(path: "sessions/\(RunnerHarness.device.rawValue)")
    guard case let .data(data) = RunnerHarness.snapshotReply(request) else { return }
    try data.write(to: session.appending(path: "response.json"))

    let snapshot = try await task.value.get()
    #expect(snapshot.appIdentifier == "com.example.app")
  }

  @Test("id 가 빈 응답(badRequest)은 요청 시간 제한을 기다리지 않고 곧바로 unreadable")
  func emptyID() async {
    let harness = RunnerHarness(timing: Self.longRequestTiming)
    harness.update { $0.responder = { _ in .data(RunnerHarness.json(["id": "", "error": "badRequest"])) } }
    let start = ContinuousClock.now

    #expect(await harness.read() == .failure(.unreadable))
    #expect(ContinuousClock.now - start < .seconds(5))
    let response = harness.root.appending(path: "sessions/\(RunnerHarness.device.rawValue)/response.json")
    #expect(!FileManager.default.fileExists(atPath: response.path(percentEncoded: false)))
  }

  static let longRequestTiming: IOSLayoutTiming = {
    var timing = RunnerHarness.timing
    timing.requestTimeout = .seconds(30)
    return timing
  }()

  @Test("요청 시간 초과 → timedOut, SIGTERM·uninstall, 다음 읽기는 다시 준비")
  func requestTimeout() async throws {
    let harness = RunnerHarness()
    harness.update { $0.responder = { _ in .silent } }

    #expect(await harness.read() == .failure(.timedOut))
    #expect(harness.command.terminates.count == 1)
    #expect(harness.uninstalls == [RunnerHarness.device])

    harness.update { $0.responder = RunnerHarness.defaultResponder }
    let phases = PhaseLog()
    _ = try await harness.read(phases: phases).get()
    #expect(phases.all == [.preparing, .reading])
    #expect(harness.launches.count == 2)
  }

  @Test("요청 중 취소 → 곧바로 cancelled, 러너는 남는다")
  func cancelDuringRequest() async throws {
    let harness = RunnerHarness(timing: Self.longRequestTiming)
    harness.update { $0.responder = { _ in .silent } }
    let task = harness.readTask()
    #expect(try await waitUntil { !harness.requests.isEmpty })

    task.cancel()

    #expect(await task.value == .failure(.cancelled))
    #expect(harness.command.terminates.isEmpty)
    #expect(harness.client.hasActiveIOSRunners)

    // 다른 id 의 응답(새 요청의 것)은 건드리지 않고, 러너가 취소된 요청의 응답을 늦게 쓰면 남기지 않는다.
    let request = try #require(harness.requests.first)
    let response = harness.root.appending(path: "sessions/\(RunnerHarness.device.rawValue)/response.json")
    try RunnerHarness.json(["id": "other", "ok": true]).write(to: response)
    try await Task.sleep(for: .milliseconds(100))
    #expect(FileManager.default.fileExists(atPath: response.path(percentEncoded: false)))
    guard case let .data(data) = RunnerHarness.snapshotReply(request) else { return }
    try data.write(to: response)
    #expect(try await waitUntil { !FileManager.default.fileExists(atPath: response.path(percentEncoded: false)) })
  }

  @Test("같은 기기 두 호출은 빌드·launch 한 번, 다른 기기는 빌드 한 번·launch 두 번")
  func concurrentReads() async throws {
    let second = VirtualDevice.ID("00000000-0000-0000-0000-000000000003")
    let inventory = RunnerHarness.inventory(second, state: .booted)
    let harness = RunnerHarness(inventory: inventory)
    let first = harness.readTask()
    let again = harness.readTask()
    _ = try await first.value.get()
    _ = try await again.value.get()
    #expect(harness.builds.count == 1)
    #expect(harness.launches.count == 1)

    _ = try await harness.read(second).get()
    #expect(harness.builds.count == 1)
    #expect(harness.launches.count == 2)
  }

  @Test("Xcode 가 바뀌면 옛 러너를 quit 로 멈추고 새로 빌드·launch")
  func xcodeChanged() async throws {
    let harness = RunnerHarness()
    _ = try await harness.read().get()
    harness.devEnvironment.setStatus(.ready(.beta))
    let phases = PhaseLog()

    _ = try await harness.read(phases: phases).get()

    #expect(phases.all == [.preparing, .reading])
    #expect(harness.requests.map(\.command) == ["snapshot", "quit", "snapshot"])
    #expect(harness.command.terminates.isEmpty)
    #expect(harness.builds.count == 2)
    #expect(harness.launches.count == 2)
    #expect(harness.launches.last?.executable.path.hasPrefix("/Applications/Xcode-beta.app") == true)
    // 쓰는 러너가 없는 옛 키 빌드는 지운다 (사용 중 키만 지킨다).
    let builds = harness.root.appending(path: "builds", directoryHint: .isDirectory)
    #expect(try FileManager.default.contentsOfDirectory(atPath: builds.path(percentEncoded: false)).count == 1)
  }
}

// MARK: - 응답 전 세션 끝남 → 한 번 다시 읽기

extension IOSLayoutReaderTests {
  /// 감시가 끼지 않게(요청 폴링만 xcodebuild 종료를 보게) 감시 간격을 늘린 값.
  static let exitTiming: IOSLayoutTiming = {
    var timing = RunnerHarness.timing
    timing.monitorInterval = .seconds(30)
    return timing
  }()

  /// ready 를 오래 기다리는 값 (`LayoutRunnerPoolTests.longReadyTiming` 과 같은 값, 그 파일은 건드리지 않는다).
  static let longReadyTiming: IOSLayoutTiming = {
    var timing = RunnerHarness.timing
    timing.readyTimeout = .seconds(30)
    return timing
  }()

  /// 첫 snapshot 요청에만 응답 없이 끝나고(유휴 종료 틈 흉내), 그 뒤로는 기본대로 답한다.
  static func exitOnceResponder() -> RunnerHarness.Responder {
    let once = Gate()
    return { request in
      if request.command == "snapshot", !once.isOpen {
        once.open()
        return .exitWithoutReply
      }
      return RunnerHarness.defaultResponder(request)
    }
  }

  /// snapshot 에는 답하지 않고 quit 에는 답하고 끝난다.
  static let silentSnapshotResponder: RunnerHarness.Responder = { request in
    request.command == "quit" ? .quitAndExit : .silent
  }

  @Test("응답 전에 xcodebuild 가 끝나면(유휴 종료 순간) 러너를 정리하고 새 러너로 한 번 다시 읽는다")
  func retryAfterRunnerExited() async throws {
    let harness = RunnerHarness(timing: Self.exitTiming)
    _ = try await harness.read().get()
    harness.update { $0.responder = Self.exitOnceResponder() }
    let phases = PhaseLog()

    _ = try await harness.read(phases: phases).get()

    #expect(phases.all == [.reading, .preparing, .reading])
    #expect(harness.launches.count == 2)
    #expect(harness.uninstalls == [RunnerHarness.device])
    #expect(harness.command.terminates.isEmpty)
    #expect(harness.requests.map(\.command) == ["snapshot", "snapshot", "snapshot"])
  }

  @Test("응답을 기다리는 중 감시가 러너 죽음으로 멈춰도 한 번 다시 읽는다")
  func retryAfterMonitorStopsDeadRunner() async throws {
    let harness = RunnerHarness(timing: Self.longRequestTiming)
    _ = try await harness.read().get()
    harness.update { $0.responder = { _ in .silent } }
    let phases = PhaseLog()
    let task = harness.readTask(phases: phases)
    #expect(try await waitUntil { harness.requests.count == 2 })

    harness.update { $0.responder = RunnerHarness.defaultResponder }
    // xcodebuild 는 SIGTERM 전까지 살아 있어 요청 폴링이 종료를 먼저 볼 수 없다 → 감시 길.
    harness.killRunners()

    _ = try await task.value.get()
    #expect(phases.all == [.reading, .preparing, .reading])
    #expect(harness.command.terminates.count == 1)
    #expect(harness.launches.count == 2)
  }

  @Test("다시 읽은 러너도 응답 전에 끝나면 더 다시 읽지 않고 준비 실패")
  func noSecondRetry() async throws {
    let harness = RunnerHarness(timing: Self.exitTiming)
    harness.update { state in
      state.responder = { request in request.command == "snapshot" ? .exitWithoutReply : .quitAndExit }
    }
    let phases = PhaseLog()

    #expect(await harness.read(phases: phases) == .failure(.inspectorSetupFailed))

    #expect(harness.launches.count == 2)
    #expect(phases.all == [.preparing, .reading, .preparing, .reading])
    #expect(try await waitUntil { !harness.client.hasActiveIOSRunners })
    #expect(try await waitUntil { harness.uninstalls.count == 2 })
  }

  @Test("끄는 중 세션을 잃으면 다시 준비하지 않고 기기 꺼짐")
  func noRetryWhileShuttingDown() async throws {
    let harness = RunnerHarness(timing: Self.longRequestTiming)
    _ = try await harness.read().get()
    harness.update { $0.responder = Self.silentSnapshotResponder }
    let phases = PhaseLog()
    let task = harness.readTask(phases: phases)
    #expect(try await waitUntil { harness.requests.count == 2 })

    await harness.client.iOSDeviceWillShutDown(RunnerHarness.device)

    #expect(await task.value == .failure(.deviceNotBooted))
    #expect(phases.all == [.reading])
    #expect(harness.launches.count == 1)
  }

  @Test("앱 종료로 세션을 잃으면 다시 준비하지 않는다")
  func noRetryAfterStopAll() async throws {
    let harness = RunnerHarness(timing: Self.longRequestTiming)
    _ = try await harness.read().get()
    harness.update { $0.responder = Self.silentSnapshotResponder }
    let phases = PhaseLog()
    let task = harness.readTask(phases: phases)
    #expect(try await waitUntil { harness.requests.count == 2 })

    await harness.client.stopAllIOSRunners()

    #expect(await task.value == .failure(.inspectorSetupFailed))
    #expect(phases.all == [.reading])
    #expect(harness.launches.count == 1)
  }

  @Test("응답을 쓰고 곧바로 끝나도 그 응답을 쓰고 다시 읽지 않는다")
  func responseWrittenBeforeExitIsUsed() async throws {
    let harness = RunnerHarness(timing: Self.exitTiming)
    _ = try await harness.read().get()
    harness.update { state in
      state.responder = { request in
        guard request.command == "snapshot", case let .data(data) = RunnerHarness.snapshotReply(request) else {
          return RunnerHarness.defaultResponder(request)
        }
        return .dataAndExit(data)
      }
    }
    let phases = PhaseLog()

    let snapshot = try await harness.read(phases: phases).get()

    #expect(snapshot.appIdentifier == "com.example.app")
    #expect(phases.all == [.reading])
    #expect(harness.launches.count == 1)
  }

  @Test("다시 준비를 기다리는 중 취소하면 곧바로 cancelled, 준비는 계속")
  func cancelWhileRetryPreparing() async throws {
    let harness = RunnerHarness(timing: Self.longReadyTiming)
    _ = try await harness.read().get()
    harness.update { state in
      state.responder = Self.exitOnceResponder()
      state.launch = .neverReady
    }
    let task = harness.readTask()
    #expect(try await waitUntil { harness.launches.count == 2 })

    task.cancel()

    #expect(await task.value == .failure(.cancelled))
    #expect(harness.client.hasActiveIOSRunners)
    await harness.client.stopAllIOSRunners()
  }

  @Test("같은 기기 다른 창이 Xcode 를 바꿔 러너를 멈추면, 응답을 기다리던 창은 새 Xcode 로 한 번 다시 읽는다")
  func retryAfterOtherWindowChangedXcode() async throws {
    let harness = RunnerHarness(timing: Self.longRequestTiming)
    _ = try await harness.read().get()
    harness.update { $0.responder = Self.silentSnapshotResponder }
    let phasesA = PhaseLog()
    let taskA = harness.readTask(phases: phasesA)
    #expect(try await waitUntil { harness.requests.count == 2 })

    // 새 빌드를 게이트로 막아, A 가 다시 읽기에서 B 의 준비에 합류(.preparing)한 뒤에야 끝나게 한다.
    let gate = Gate()
    harness.update { state in
      state.responder = RunnerHarness.defaultResponder
      state.buildGate = gate
    }
    harness.devEnvironment.setStatus(.ready(.beta))
    let taskB = harness.readTask()
    #expect(try await waitUntil { gate.isWaiting && phasesA.all.count == 2 })
    gate.open()

    _ = try await taskA.value.get()
    _ = try await taskB.value.get()
    #expect(phasesA.all == [.reading, .preparing, .reading])
    #expect(harness.launches.count == 2)
    // 빌드 호출 기록 수 (첫 읽기 1 + beta 1).
    #expect(harness.builds.count == 2)
    #expect(harness.command.terminates.isEmpty)
    #expect(harness.launches.last?.executable.path.hasPrefix("/Applications/Xcode-beta.app") == true)
  }

  @Test("같은 기기 두 창이 함께 응답 전 종료에 걸려도 새 러너 하나로 둘 다 읽는다")
  func twoWindowsCaughtInGapShareOneRunner() async throws {
    let harness = RunnerHarness(timing: Self.longRequestTiming)
    _ = try await harness.read().get()
    harness.update { $0.responder = { _ in .silent } }
    let taskA = harness.readTask()
    #expect(try await waitUntil { harness.requests.count == 2 })
    let taskB = harness.readTask()
    // 첫 읽기 1 + A + B: B 가 큐 차례에 들어 A 뒤에서 기다린다.
    #expect(try await waitUntil { await harness.client.iOSReader.queue.runCount == 3 })

    harness.update { $0.responder = RunnerHarness.defaultResponder }
    harness.exitAll()

    _ = try await taskA.value.get()
    _ = try await taskB.value.get()
    #expect(harness.launches.count == 2)
    #expect(harness.requests.filter { $0.command == "snapshot" }.count >= 4)
  }
}
