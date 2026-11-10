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
  }
}
