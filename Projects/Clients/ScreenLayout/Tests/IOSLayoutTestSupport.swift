import AndroidEmulatorTesting
import CommandInterface
import CommandTesting
import Core
import DevEnvironmentTesting
import Foundation
import ScreenLayoutInterface
import SimulatorTesting
import Synchronization
@testable import ScreenLayoutImpl

/// `condition` 이 참이 될 때까지 5ms 마다 본다. `limit` 이 지나면 false.
func waitUntil(_ limit: Duration = .seconds(3), _ condition: () async -> Bool) async throws -> Bool {
  let deadline = ContinuousClock.now.advanced(by: limit)
  while await !condition() {
    guard ContinuousClock.now < deadline else {
      return false
    }
    try await Task.sleep(for: .milliseconds(5))
  }
  return true
}

/// 테스트가 여는 문. 열 때까지 기다린다.
final class Gate: Sendable {
  private let opened = Mutex(false)

  func open() {
    self.opened.withLock { $0 = true }
  }

  var isOpen: Bool {
    self.opened.withLock { $0 }
  }

  func wait() async {
    while !self.isOpen {
      try? await Task.sleep(for: .milliseconds(5))
    }
  }
}

/// 받은 단계, 순서대로.
final class PhaseLog: Sendable {
  private let phases = Mutex<[LayoutReadPhase]>([])

  func add(_ phase: LayoutReadPhase) {
    self.phases.withLock { $0.append(phase) }
  }

  var all: [LayoutReadPhase] {
    self.phases.withLock { $0 }
  }
}

/// iOS 레이아웃 흐름 테스트 도구: 임시 러너 폴더 + Fake Command·Simulator·DevEnvironment + 러너 흉내.
/// - 빌드(`runCancellable`): `-derivedDataPath` 아래 `Build/Products` 에 `.xctestrun` 을 만든다 (설정으로 실패·붙잡기).
/// - launch: 환경의 세션 폴더·토큰을 읽어 ready.json 을 쓰고 request.json 을 5ms 마다 읽어 `responder` 대로 답하는 Task 를 띄운다.
///   quit 이면 `{"id","ok":true}` 를 쓰고 종료 코드 0 으로 끝난다. SIGTERM(`terminate`)이면 143 으로 끝난다(설정으로 끄기).
/// - ps(`run`): 살아 있는 흉내 러너 pid 면 그 기기의 러너 경로, 아니면 종료 코드 1.
final class RunnerHarness: Sendable {
  enum BuildBehavior: Sendable {
    case succeed
    case fail
    case launchFailed
    /// `.xctestrun` 을 둘 만든다 (빌드 안 됨으로 보아야 한다).
    case twoRuns
  }

  enum LaunchBehavior: Sendable {
    case serve
    case launchFailed
    /// ready 전에 종료 코드 65 로 끝난다.
    case exitBeforeReady
    /// ready.json 을 쓰지 않는다.
    case neverReady
  }

  struct Request: Sendable {
    let id: String
    let command: String
    let bundleIDs: [String]
  }

  enum Reply: Sendable {
    case data(Data)
    /// 답하지 않는다.
    case silent
    /// quit 처럼 ok 를 쓰고 끝난다.
    case quitAndExit
  }

  typealias Responder = @Sendable (Request) -> Reply

  struct State {
    var build: BuildBehavior = .succeed
    var launch: LaunchBehavior = .serve
    var responder: Responder = RunnerHarness.defaultResponder
    var buildGate: Gate?
    /// launch 처리기 안에서 (돌아오기 전에) 부른다.
    var onLaunch: (@Sendable () -> Void)?
    var terminateExits = true
    var nextPID: Int32 = 5000
    var alive: [Int32: String] = [:]
    var exits: [UUID: @Sendable (Int32) -> Void] = [:]
    var exited: Set<UUID> = []
    var processPIDs: [UUID: Int32] = [:]
    var requests: [Request] = []
    var scale: Double = 3
  }

  static let device = SampleID.iPhoneOn
  static let deviceName = "iPhone 17 Pro"
  /// 1206×2622 PNG 머리 (IHDR 까지).
  static let png: Data = {
    var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52]
    bytes += [0, 0, 0x04, 0xB6, 0, 0, 0x0A, 0x3E, 8, 6, 0, 0, 0]
    return Data(bytes)
  }()

  let root: URL
  let simulator: SimulatorClientFake
  let devEnvironment: DevEnvironmentClientFake
  let command: CommandClientFake
  let client: ScreenLayoutClientImpl
  let state: HarnessState

  static let timing = IOSLayoutTiming(
    buildTimeout: .seconds(5),
    readyTimeout: .milliseconds(1500),
    readyPollInterval: .milliseconds(10),
    settleSeconds: 0.1,
    requestTimeout: .seconds(1),
    responsePollInterval: .milliseconds(10),
    quitGrace: .milliseconds(200),
    terminateGrace: .milliseconds(200),
    monitorInterval: .milliseconds(50),
    orphanQuitWait: .milliseconds(200),
    orphanPollInterval: .milliseconds(20),
    idleSeconds: 600,
    stopAllLimit: .seconds(2)
  )

  init(root: URL? = nil, timing: IOSLayoutTiming = RunnerHarness.timing, inventory: DeviceInventory = .sample) {
    let root = root ?? FileManager.default.temporaryDirectory
      .appending(path: "LayoutRunnerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let state = HarnessState()
    let simulator = SimulatorClientFake(inventory: inventory)
    simulator.setScreenshotPNG(Self.png)
    let command = CommandClientFake(
      handler: { invocation throws(CommandError) in
        Self.handleRun(invocation, state: state)
      },
      cancellableHandler: { invocation, _ throws(CommandError) in
        try await Self.handleBuild(invocation, state: state)
      },
      launchHandler: { invocation, process, exit throws(CommandError) in
        try Self.handleLaunch(invocation, process: process, exit: exit, state: state)
      },
      terminateHandler: { process in
        Self.handleTerminate(process, state: state)
      }
    )
    let devEnvironment = DevEnvironmentClientFake()
    self.root = root
    self.simulator = simulator
    self.devEnvironment = devEnvironment
    self.command = command
    self.state = state
    self.client = ScreenLayoutClientImpl(
      androidEmulator: AndroidEmulatorClientFake(),
      simulator: simulator,
      devEnvironment: devEnvironment,
      command: command,
      runnerDirectory: root,
      timing: timing,
      baseEnvironment: ["PATH": "/usr/bin:/bin"]
    )
  }

  deinit {
    try? FileManager.default.removeItem(at: self.root)
  }

  // MARK: 설정·조회

  func update(_ change: (inout State) -> Void) {
    self.state.withLock(change)
  }

  var builds: [CommandClientFake.Invocation] {
    self.command.invocations.filter(\.isCancellable)
  }

  var launches: [CommandClientFake.Invocation] {
    self.command.invocations.filter(\.isLaunch)
  }

  var requests: [Request] {
    self.state.withLock { $0.requests }
  }

  var uninstalls: [VirtualDevice.ID] {
    self.simulator.calls.compactMap { call in
      if case let .uninstall(bundleID, id) = call, bundleID.rawValue == IOSLayoutRunner.appBundleID {
        id
      } else {
        nil
      }
    }
  }

  var screenshotFiles: [URL] {
    self.simulator.calls.compactMap { call in
      if case let .screenshot(_, file) = call {
        file
      } else {
        nil
      }
    }
  }

  var hasLiveRunner: Bool {
    self.state.withLock { !$0.alive.isEmpty }
  }

  /// 흉내 러너를 (xcodebuild 는 둔 채) 죽인다.
  func killRunners() {
    self.state.withLock { $0.alive = [:] }
  }

  /// 띄운 xcodebuild 를 모두 끝낸다 (유휴 자체 종료 흉내).
  func exitAll(status: Int32 = 0) {
    let exits = self.state.withLock { state in
      state.alive = [:]
      return Array(state.exits.values)
    }
    for exit in exits {
      exit(status)
    }
  }

  /// 읽기 한 번. 단계와 결과.
  func read(
    _ id: VirtualDevice.ID = RunnerHarness.device,
    phases: PhaseLog = PhaseLog()
  ) async -> Result<LayoutSnapshot, ScreenLayoutError> {
    do throws(ScreenLayoutError) {
      return try await .success(self.client.snapshot(of: .iOS(id)) { phases.add($0) })
    } catch {
      return .failure(error)
    }
  }

  func readTask(
    _ id: VirtualDevice.ID = RunnerHarness.device,
    phases: PhaseLog = PhaseLog()
  ) -> Task<Result<LayoutSnapshot, ScreenLayoutError>, Never> {
    Task { await self.read(id, phases: phases) }
  }

  /// 그 기기의 상태만 바꾼 목록.
  static func inventory(_ id: VirtualDevice.ID = RunnerHarness.device, state: VirtualDevice.State) -> DeviceInventory {
    let base = DeviceInventory.sample
    return DeviceInventory(
      devices: base.devices.map { device in
        guard device.id == id else { return device }
        return VirtualDevice(
          id: device.id,
          name: device.name,
          family: device.family,
          state: state,
          availability: device.availability,
          runtime: device.runtime
        )
      },
      runtimes: base.runtimes,
      deviceTypes: base.deviceTypes
    )
  }
}

extension RunnerHarness {
  // MARK: 응답 만들기

  static func json(_ object: [String: Any]) -> Data {
    (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
  }

  /// 앱 하나, 루트(402×874 pt)와 버튼 하나.
  static func snapshotReply(_ request: Request, apps: [String] = ["com.example.app"], system: Bool = false) -> Reply {
    .data(self.json([
      "id": request.id,
      "apps": apps,
      "system": system,
      "truncated": false,
      "nodes": [
        ["d": 0, "t": 2, "x": 0, "y": 0, "w": 402, "h": 874, "l": "앱"],
        ["d": 1, "t": 9, "x": 10, "y": 20, "w": 100, "h": 44, "i": "ok", "l": "확인"],
      ],
    ]))
  }

  static let defaultResponder: Responder = { request in
    request.command == "quit" ? .quitAndExit : RunnerHarness.snapshotReply(request)
  }

  // MARK: 처리기

  private static func handleRun(_ invocation: CommandClientFake.Invocation, state: HarnessState) -> CommandResult {
    guard invocation.executable.path == "/bin/ps", let pid = invocation.arguments.dropFirst().first.flatMap(Int32.init),
          let udid = state.withLock({ $0.alive[pid] })
    else {
      return CommandResult(exitCode: 1, stdout: Data(), stderr: Data())
    }
    let path = "/Users/me/Library/Developer/CoreSimulator/Devices/\(udid)/data/Containers/Bundle/Application/X/"
      + "SimLauncherLayout-Runner.app/SimLauncherLayout-Runner\n"
    return CommandResult(exitCode: 0, stdout: Data(path.utf8), stderr: Data())
  }

  private static func handleBuild(
    _ invocation: CommandClientFake.Invocation,
    state: HarnessState
  ) async throws(CommandError) -> CommandResult {
    let (behavior, gate) = state.withLock { ($0.build, $0.buildGate) }
    await gate?.wait()
    switch behavior {
    case .launchFailed:
      throw .launchFailed
    case .fail:
      return CommandResult(exitCode: 65, stdout: Data(), stderr: Data())
    case .succeed, .twoRuns:
      guard let index = invocation.arguments.firstIndex(of: "-derivedDataPath") else {
        return CommandResult(exitCode: 1, stdout: Data(), stderr: Data())
      }
      let products = URL(filePath: invocation.arguments[index + 1]).appending(path: "Build/Products")
      try? FileManager.default.createDirectory(at: products, withIntermediateDirectories: true)
      let names = behavior == .twoRuns ? ["A.xctestrun", "B.xctestrun"] : ["LayoutRunner_iphonesimulator27.2.xctestrun"]
      for name in names {
        try? Data().write(to: products.appending(path: name))
      }
      return CommandResult(exitCode: 0, stdout: Data(), stderr: Data())
    }
  }

  private static func handleLaunch(
    _ invocation: CommandClientFake.Invocation,
    process: LaunchedProcess,
    exit: @escaping @Sendable (Int32) -> Void,
    state: HarnessState
  ) throws(CommandError) {
    let (behavior, onLaunch) = state.withLock { ($0.launch, $0.onLaunch) }
    onLaunch?()
    let markedExit: @Sendable (Int32) -> Void = { status in
      state.withLock { state in
        state.exited.insert(process.id)
        if let pid = state.processPIDs[process.id] {
          state.alive[pid] = nil
        }
      }
      exit(status)
    }
    state.withLock { $0.exits[process.id] = markedExit }
    switch behavior {
    case .launchFailed:
      throw .launchFailed
    case .exitBeforeReady:
      Task { markedExit(65) }
    case .neverReady:
      break
    case .serve:
      Task.detached { await Self.serve(invocation, process: process, exit: markedExit, state: state) }
    }
  }

  private static func handleTerminate(_ process: LaunchedProcess, state: HarnessState) {
    let exit = state.withLock { state -> (@Sendable (Int32) -> Void)? in
      state.terminateExits ? state.exits[process.id] : nil
    }
    exit?(143)
  }

  private static func serve(
    _ invocation: CommandClientFake.Invocation,
    process: LaunchedProcess,
    exit: @escaping @Sendable (Int32) -> Void,
    state: HarnessState
  ) async {
    let environment = invocation.environment
    guard let path = environment["TEST_RUNNER_SIMLAUNCHER_LAYOUT_DIR"],
          let token = environment["TEST_RUNNER_SIMLAUNCHER_LAYOUT_SESSION"],
          let destination = invocation.arguments.first(where: { $0.hasPrefix("id=") })
    else {
      return
    }
    let directory = URL(filePath: path, directoryHint: .isDirectory)
    let udid = String(destination.dropFirst(3))
    let (pid, scale) = state.withLock { state in
      state.nextPID += 1
      state.alive[state.nextPID] = udid
      state.processPIDs[process.id] = state.nextPID
      return (state.nextPID, state.scale)
    }
    self.write(
      self.json(["protocol": 1, "session": token, "pid": Int(pid), "scale": scale]),
      "ready.json",
      in: directory
    )
    let requestURL = directory.appending(path: "request.json")
    while !state.withLock({ $0.exited.contains(process.id) }) {
      try? await Task.sleep(for: .milliseconds(5))
      guard let data = try? Data(contentsOf: requestURL) else { continue }
      try? FileManager.default.removeItem(at: requestURL)
      guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
      let request = Request(
        id: object["id"] as? String ?? "",
        command: object["command"] as? String ?? "",
        bundleIDs: object["bundleIDs"] as? [String] ?? []
      )
      let responder = state.withLock { state in
        state.requests.append(request)
        return state.responder
      }
      switch responder(request) {
      case let .data(reply):
        self.write(reply, "response.json", in: directory)
      case .silent:
        continue
      case .quitAndExit:
        self.write(self.json(["id": request.id, "ok": true]), "response.json", in: directory)
        exit(0)
        return
      }
    }
  }

  private static func write(_ data: Data, _ name: String, in directory: URL) {
    let temporary = directory.appending(path: name + ".tmp")
    guard (try? data.write(to: temporary)) != nil else { return }
    _ = rename(temporary.path(percentEncoded: false), directory.appending(path: name).path(percentEncoded: false))
  }
}

/// 흉내 러너 상태 (탈출 클로저가 잡을 수 있게 클래스로 감싼 `Mutex`).
final class HarnessState: Sendable {
  private let mutex = Mutex(RunnerHarness.State())

  func withLock<R: Sendable>(_ body: (inout RunnerHarness.State) -> R) -> R {
    self.mutex.withLock { state in body(&state) }
  }
}
