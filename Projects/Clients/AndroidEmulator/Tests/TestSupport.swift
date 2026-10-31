import AndroidEmulatorInterface
import CommandInterface
import CommandTesting
import Core
import Foundation
import Synchronization
import Testing
@testable import AndroidEmulatorImpl

/// 테스트마다 만드는 임시 폴더. 끝나면 `remove()` 로 지운다.
struct TemporaryDirectory {
  /// 심볼릭 링크를 푼 경로 (`/var` → `/private/var`).
  let url: URL

  init() throws {
    let base = FileManager.default.temporaryDirectory.appending(path: "AndroidEmulatorTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    self.url = base.resolvingSymlinksInPath()
  }

  /// 권한을 뺀 폴더가 있어도 지우도록 u+rwx 를 되돌린 뒤 지운다.
  func remove() {
    let path = self.url.path(percentEncoded: false)
    if let enumerator = FileManager.default.enumerator(atPath: path) {
      for case let relative as String in enumerator {
        chmod(path + "/" + relative, 0o755)
      }
    }
    try? FileManager.default.removeItem(atPath: path)
  }
}

/// 테스트가 만드는 파일 트리. 경로는 `base` 기준 상대 경로이고 중간 폴더를 만든다.
enum FileTree {
  static func directory(_ base: URL, _ path: String) throws {
    try FileManager.default.createDirectory(
      at: base.appending(path: path, directoryHint: .isDirectory),
      withIntermediateDirectories: true
    )
  }

  static func file(_ base: URL, _ path: String, contents: String = "x", mode: Int16? = nil) throws {
    let url = base.appending(path: path, directoryHint: .notDirectory)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(contents.utf8).write(to: url)
    if let mode {
      try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path(percentEncoded: false))
    }
  }

  /// `target` 문자열을 그대로 담은 심볼릭 링크.
  static func link(_ base: URL, _ path: String, to target: String) throws {
    let url = base.appending(path: path, directoryHint: .notDirectory)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(atPath: url.path(percentEncoded: false), withDestinationPath: target)
  }

  /// 링크를 따라가지 않고 무엇이든 있는지.
  static func exists(_ base: URL, _ path: String = "") -> Bool {
    let url = path.isEmpty ? base : base.appending(path: path)
    return FileFacts.kindWithoutFollowing(url) != .absent
  }

  static func read(_ base: URL, _ path: String) -> String? {
    try? String(contentsOf: base.appending(path: path, directoryHint: .notDirectory), encoding: .utf8)
  }

  static func names(_ url: URL) -> [String] {
    FileFacts.childNames(url)
  }
}

/// 테스트 프로세스가 `multiinstance.lock` 에 잡는 잠금 (qemu 처럼 `flock(LOCK_EX)`). 다른 fd 의 `F_GETLK` 에 WRLCK 로 보인다.
final class LockHolder: Sendable {
  private let descriptors = Mutex<[String: Int32]>([:])

  func hold(_ folder: URL) {
    let path = folder.appending(path: AVDLock.fileName).path(percentEncoded: false)
    let descriptor = open(path, O_RDWR | O_CREAT, 0o644)
    #expect(descriptor >= 0)
    #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
    self.descriptors.withLock { $0[path] = descriptor }
  }

  func release(_ folder: URL) {
    let path = folder.appending(path: AVDLock.fileName).path(percentEncoded: false)
    if let descriptor = self.descriptors.withLock({ $0.removeValue(forKey: path) }) {
      flock(descriptor, LOCK_UN)
      close(descriptor)
    }
  }

  func releaseAll() {
    let all = self.descriptors.withLock { descriptors in
      defer { descriptors = [:] }
      return Array(descriptors.values)
    }
    for descriptor in all {
      flock(descriptor, LOCK_UN)
      close(descriptor)
    }
  }
}

/// adb 흉내. serial 마다 AVD 이름·online·부팅 완료를 두고, 받은 인자대로 답한다.
final class FakeADB: Sendable {
  struct Emulator: Sendable {
    var name: String
    var isOnline = true
    var bootCompleted = true
  }

  private struct State {
    var emulators: [String: Emulator] = [:]
    var devicesFail = false
    var killFails = false
    var onDevices: (@Sendable () -> Void)?
    var onKill: (@Sendable (String) -> Void)?
    var onApp: (@Sendable ([String]) throws(CommandError) -> CommandResult)?
  }

  private let state = Mutex(State())

  func set(_ serial: String, _ emulator: Emulator?) {
    self.state.withLock { $0.emulators[serial] = emulator }
  }

  func setDevicesFail(_ fail: Bool) {
    self.state.withLock { $0.devicesFail = fail }
  }

  /// true 면 `emu kill` 은 handler 를 부른 뒤 종료 코드 1 (앱 밖에서 끄는 중이라 막혔다가 시간 초과된 흉내).
  func setKillFails(_ fails: Bool) {
    self.state.withLock { $0.killFails = fails }
  }

  /// `adb devices` 를 받을 때마다 (답하기 전에) 부른다.
  func onDevices(_ handler: (@Sendable () -> Void)?) {
    self.state.withLock { $0.onDevices = handler }
  }

  /// `emu kill` 을 받으면 serial 로 부른다 (잠금 풀기 흉내).
  func onKill(_ handler: (@Sendable (String) -> Void)?) {
    self.state.withLock { $0.onKill = handler }
  }

  /// 위 목록에 없는 `-s <serial> …` 명령(앱 작업)을 받으면 전체 인자로 부른다. nil 이면 종료 코드 1.
  func onApp(_ handler: (@Sendable ([String]) throws(CommandError) -> CommandResult)?) {
    self.state.withLock { $0.onApp = handler }
  }

  func respond(_ arguments: [String]) throws(CommandError) -> CommandResult {
    if arguments == ["devices"] {
      let (fail, handler) = self.state.withLock { ($0.devicesFail, $0.onDevices) }
      handler?()
      guard !fail else {
        return Self.result(1, "")
      }
      let lines = self.state.withLock { state in
        state.emulators.keys.sorted().map { "\($0)\t\(state.emulators[$0]?.isOnline == true ? "device" : "offline")" }
      }
      return Self.result(0, (["List of devices attached"] + lines).joined(separator: "\n") + "\n\n")
    }
    guard arguments.count >= 3, arguments[0] == "-s" else {
      return Self.result(1, "")
    }
    let serial = arguments[1]
    let emulator = self.state.withLock { $0.emulators[serial] }
    switch Array(arguments.dropFirst(2)) {
    case ["emu", "avd", "name"]:
      return emulator.map { Self.result(0, "\($0.name)\r\nOK\r\n") } ?? Self.result(1, "")
    case ["shell", "getprop", "sys.boot_completed"]:
      return Self.result(0, emulator?.bootCompleted == true ? "1\r\n" : "\r\n")
    case ["emu", "kill"]:
      let (handler, fails) = self.state.withLock { ($0.onKill, $0.killFails) }
      handler?(serial)
      return Self.result(fails || emulator == nil ? 1 : 0, "OK: killing emulator, bye bye\r\nOK\r\n")
    default:
      guard let handler = self.state.withLock({ $0.onApp }) else {
        return Self.result(1, "")
      }
      return try handler(arguments)
    }
  }

  private static func result(_ code: Int32, _ stdout: String) -> CommandResult {
    CommandResult(exitCode: code, stdout: Data(stdout.utf8), stderr: Data())
  }
}

/// emulator 프로세스 흉내의 훅.
final class ProcessHooks: Sendable {
  typealias Exit = @Sendable (Int32) -> Void

  private struct State {
    var onLaunch: (@Sendable (LaunchedProcess, @escaping Exit) -> Void)?
    var launchFails = false
    var onInterrupt: (@Sendable (LaunchedProcess) -> Void)?
  }

  private let state = Mutex(State())

  /// `launch` 를 받으면 부른다 (프로세스, 끝내기). nil 이면 계속 돈다.
  func onLaunch(_ handler: (@Sendable (LaunchedProcess, @escaping Exit) -> Void)?) {
    self.state.withLock { $0.onLaunch = handler }
  }

  /// true 면 `launch` 가 `.launchFailed` 를 던진다.
  func setLaunchFails(_ fails: Bool) {
    self.state.withLock { $0.launchFails = fails }
  }

  /// 아직 도는 프로세스에 SIGINT 가 오면 부른다. nil 이면 무시한다.
  func onInterrupt(_ handler: (@Sendable (LaunchedProcess) -> Void)?) {
    self.state.withLock { $0.onInterrupt = handler }
  }

  func launched(_ process: LaunchedProcess, exit: @escaping Exit) throws(CommandError) {
    let (fails, handler) = self.state.withLock { ($0.launchFails, $0.onLaunch) }
    if fails {
      throw .launchFailed
    }
    handler?(process, exit)
  }

  func interrupted(_ process: LaunchedProcess) {
    self.state.withLock { $0.onInterrupt }?(process)
  }
}

/// 임시 홈(`home/.android/avd`)·SDK(emulator·adb·기본 이미지)와 adb·emulator 흉내를 묶은 Impl.
struct Harness {
  static let timing = AndroidEmulatorClientImpl.Timing(
    pollInterval: .milliseconds(10),
    bootLimit: .milliseconds(400),
    shutdownPollInterval: .milliseconds(10),
    shutdownLimit: .milliseconds(400),
    serialSearchLimit: .milliseconds(150),
    adbTimeout: .seconds(10),
    installTimeout: .seconds(600)
  )
  /// 기다림 단계에서 잠금을 푸는 테스트용: 끄기 기다림만 넉넉히 둔다.
  static let longShutdownTiming = AndroidEmulatorClientImpl.Timing(
    pollInterval: .milliseconds(10),
    bootLimit: .milliseconds(400),
    shutdownPollInterval: .milliseconds(10),
    shutdownLimit: .seconds(10),
    serialSearchLimit: .milliseconds(150),
    adbTimeout: .seconds(10),
    installTimeout: .seconds(600)
  )
  static let image = AndroidSystemImageRef(apiFolder: "android-37.0", tag: "google_apis", abi: "arm64-v8a")!

  let directory: TemporaryDirectory
  let home: URL
  let sdk: URL
  let adb: FakeADB
  let locks = LockHolder()
  let command: CommandClientFake
  let client: AndroidEmulatorClientImpl
  let processes = ProcessHooks()

  /// - Parameters:
  ///   - sdkChoice: nil 이면 `sdk` 폴더. emulator·adb·기본 이미지(`image`)를 설치해 둔다.
  ///   - timing: 기본은 `Harness.timing`.
  ///   - adb: `cancellableHandler` 가 함께 쓰는 adb 흉내.
  ///   - cancellableHandler: `runCancellable` 처리기 (녹화처럼 오래 도는 명령). nil 이면 `adb` 의 답을 한 조각씩 넘긴다.
  init(
    sdkChoice: AndroidSDKRootChoice? = nil,
    installSDK: Bool = true,
    timing: AndroidEmulatorClientImpl.Timing = Harness.timing,
    adb: FakeADB = FakeADB(),
    cancellableHandler: CommandClientFake.CancellableHandler? = nil
  ) throws {
    self.adb = adb
    let directory = try TemporaryDirectory()
    self.directory = directory
    self.home = directory.url.appending(path: "home", directoryHint: .isDirectory)
    self.sdk = directory.url.appending(path: "sdk", directoryHint: .isDirectory)
    try FileTree.directory(self.home, "")
    if installSDK {
      try FileTree.file(self.sdk, "emulator/emulator", mode: 0o755)
      try FileTree.file(self.sdk, "platform-tools/adb", mode: 0o755)
      try Self.installImage(Self.image, in: self.sdk)
    }
    let choice = sdkChoice ?? .root(AndroidSDKRoot(url: self.sdk, isDefault: false))
    let adb = self.adb
    let processes = self.processes
    self.command = CommandClientFake(
      handler: { invocation throws(CommandError) in try adb.respond(invocation.arguments) },
      cancellableHandler: cancellableHandler,
      launchHandler: { _, process, exit throws(CommandError) in
        try processes.launched(process, exit: exit)
      },
      interruptHandler: { process in processes.interrupted(process) }
    )
    self.client = AndroidEmulatorClientImpl(
      command: self.command,
      sdkRoot: { choice },
      home: self.home,
      host: .aarch64,
      timing: timing
    )
  }

  func cleanUp() {
    self.locks.releaseAll()
    self.directory.remove()
  }

  var avdFolder: URL {
    self.home.appending(path: ".android/avd", directoryHint: .isDirectory)
  }

  func deviceFolder(_ name: String) -> URL {
    self.avdFolder.appending(path: "\(name).avd", directoryHint: .isDirectory)
  }

  /// ini 의 `path` 에 이 폴더를 적었을 때 Impl 이 만드는 기기 폴더 URL.
  static func pointed(_ folder: URL) -> URL {
    URL(filePath: FileFacts.path(folder), directoryHint: .isDirectory)
  }

  static func installImage(_ image: AndroidSystemImageRef, in sdk: URL) throws {
    try FileTree.file(sdk, "system-images/\(image.apiFolder)/\(image.tag)/\(image.abi)/system.img")
  }

  /// 이미지 폴더에 폴더블 접기 설정 파일(`Fold.requiredImageFiles`)을 둔다.
  static func installFoldFiles(_ image: AndroidSystemImageRef, in sdk: URL) throws {
    let fold = try #require(AndroidDeviceProfile.profile(.foldable)?.fold)
    for file in fold.requiredImageFiles {
      try FileTree.file(sdk, "system-images/\(image.apiFolder)/\(image.tag)/\(image.abi)/\(file)")
    }
  }

  /// Studio 형식 `<이름>.ini`(path·path.rel·target)와 `<이름>.avd/config.ini` (기본: 앱이 쓰는 내용, 휴대전화, 기본 이미지).
  /// `pointer`·`config` 를 주면 그 내용을 그대로 쓴다 (`config` 가 빈 문자열이면 config.ini 를 쓰지 않는다).
  @discardableResult
  func addDevice(
    _ name: String,
    displayName: String? = nil,
    pointer: String? = nil,
    config: String? = nil
  ) throws -> URL {
    let folder = self.deviceFolder(name)
    let pointerText = pointer ?? """
    avd.ini.encoding=UTF-8
    path=\(folder.path(percentEncoded: false))
    path.rel=avd/\(name).avd
    target=android-37.0

    """
    try FileTree.file(self.avdFolder, "\(name).ini", contents: pointerText)
    try FileTree.directory(folder, "")
    let configText = config ?? String(bytes: AndroidAVDConfig.configFile(
      displayName: displayName ?? name,
      image: Self.image,
      profile: AndroidDeviceProfile.all[0],
      host: .aarch64
    ), encoding: .utf8) ?? ""
    if !configText.isEmpty {
      try FileTree.file(folder, "config.ini", contents: configText)
    }
    return folder
  }

  /// 앱 기본 config 에서 `image.sysdir.1`·`abi.type`·`hw.cpu.arch` 만 바꾼 내용.
  static func config(sysdir: String, cpuArch: String = "arm64") -> String {
    """
    avd.ini.encoding=UTF-8
    image.sysdir.1=\(sysdir)
    abi.type=arm64-v8a
    hw.cpu.arch=\(cpuArch)
    hw.lcd.width=1080
    hw.lcd.height=2400
    hw.lcd.density=420

    """
  }

  /// `fetchDevices()` 의 기기 하나.
  func device(_ name: String) async throws -> AndroidVirtualDevice? {
    try await self.client.fetchDevices().devices.first { $0.id.rawValue == name }
  }

  /// adb 로 보낸 인자 목록, 순서대로.
  var adbCalls: [[String]] {
    self.command.invocations.filter { !$0.isLaunch }.map(\.arguments)
  }

  /// `adb devices` 를 받은 횟수.
  var devicesCallCount: Int {
    self.adbCalls.count(where: { $0 == ["devices"] })
  }

  var launches: [CommandClientFake.Invocation] {
    self.command.invocations.filter(\.isLaunch)
  }
}

/// `condition` 이 참이 될 때까지 10ms 마다 본다. `limit` 이 지나면 false.
func waitUntil(_ limit: Duration = .seconds(2), _ condition: () -> Bool) async throws -> Bool {
  let deadline = ContinuousClock.now.advanced(by: limit)
  while !condition() {
    guard ContinuousClock.now < deadline else {
      return false
    }
    try await Task.sleep(for: .milliseconds(10))
  }
  return true
}

/// 던진 `AndroidEmulatorError` 를 돌려준다. 던지지 않으면 nil. 값을 돌려주는 호출은 `_ = try await …` 로 감싼다.
func thrownError(_ body: () async throws -> Void) async -> AndroidEmulatorError? {
  do {
    try await body()
    return nil
  } catch let error as AndroidEmulatorError {
    return error
  } catch {
    Issue.record("AndroidEmulatorError 가 아닌 에러: \(error)")
    return nil
  }
}
