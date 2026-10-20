import CommandInterface
import Core
import Foundation
import SimulatorInterface

/// 개발자 디렉터리(`DEVELOPER_DIR`)를 알려 주는 provider. nil 을 돌려주면 쓸 Xcode 가 없다는 뜻이고 명령을 실행하지 않는다.
public typealias DeveloperDirectoryProvider = @Sendable () async -> URL?

/// `xcrun simctl` 로 시뮬레이터를 다루는 `SimulatorClient`.
/// provider 는 공개 메서드 한 번에 한 번만 부르고, 그 호출 안의 사전 확인·재조회·앱 열기도 같은 디렉터리를 쓴다.
public struct SimulatorClientImpl: SimulatorClient {
  private let developerDirectory: DeveloperDirectoryProvider?
  private let command: any CommandClient
  private let fileExists: @Sendable (URL) -> Bool
  private let baseEnvironment: [String: String]

  /// - Parameters:
  ///   - developerDirectory: 쓸 개발자 디렉터리. provider 가 nil 을 돌려주면 어떤 명령도 실행하지 않고
  ///     `.developerToolsUnavailable` (shim 이 Command Line Tools 설치 대화상자를 띄우지 않게).
  ///     provider 자체가 없으면(nil, 테스트용) 물려받은 `DEVELOPER_DIR` 를 지우고 `xcode-select` 기본값을 쓴다.
  ///   - command: 명령 실행. App 이 `CommandClientImpl` 을 넘긴다.
  public init(developerDirectory: DeveloperDirectoryProvider?, command: any CommandClient) {
    self.init(
      developerDirectory: developerDirectory,
      command: command,
      fileExists: { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) },
      baseEnvironment: ProcessInfo.processInfo.environment
    )
  }

  /// 테스트용: 파일 확인·기본 환경도 바꾼다.
  init(
    developerDirectory: DeveloperDirectoryProvider?,
    command: any CommandClient,
    fileExists: @escaping @Sendable (URL) -> Bool,
    baseEnvironment: [String: String]
  ) {
    self.developerDirectory = developerDirectory
    self.command = command
    self.fileExists = fileExists
    self.baseEnvironment = baseEnvironment
  }

  public func fetchInventory() async throws(SimulatorError) -> DeviceInventory {
    let directory = try await self.resolveDeveloperDirectory()
    return try await self.inventory(developerDirectory: directory)
  }

  public func boot(_ id: VirtualDevice.ID) async throws(SimulatorError) {
    try await self.changeState(of: id, arguments: SimctlCommand.boot(udid:), succeedsIn: [.booted, .booting])
  }

  public func shutdown(_ id: VirtualDevice.ID) async throws(SimulatorError) {
    try await self.changeState(
      of: id,
      arguments: SimctlCommand.shutdown(udid:),
      succeedsIn: [.shutdown, .shuttingDown]
    )
  }

  public func create(
    name: String,
    deviceType: DeviceType.ID,
    runtime: DeviceRuntime.ID
  ) async throws(SimulatorError) -> VirtualDevice.ID {
    guard DeviceName.problem(in: name) == nil else {
      throw .invalidDeviceName
    }
    let directory = try await self.resolveDeveloperDirectory()
    let inventory = try await self.inventory(developerDirectory: directory)
    guard DeviceCreationOptions(inventory: inventory).contains(runtime: runtime, deviceType: deviceType) else {
      throw .creationOptionUnavailable
    }
    let result = try await self.run(
      SimctlCommand.xcrun,
      SimctlCommand.create(
        name: DeviceName.normalized(name),
        deviceTypeID: deviceType.rawValue,
        runtimeID: runtime.rawValue
      ),
      developerDirectory: directory,
      launchFailure: .developerToolsUnavailable
    )
    // 실패하면 기기가 생기지 않으므로 재조회하지 않는다.
    guard result.exitCode == 0 else {
      throw Self.classify(result)
    }
    // 해석하지 못해도 기기는 생겼을 수 있다. 호출한 쪽이 목록을 다시 읽어 보인다.
    guard let udid = SimctlCommand.createdUDID(fromStdout: result.stdout) else {
      throw .creationResultUnknown
    }
    return VirtualDevice.ID(udid)
  }

  public func delete(_ id: VirtualDevice.ID) async throws(SimulatorError) {
    try await self.runOnShutdownDevice(id, arguments: SimctlCommand.delete(udid:))
  }

  public func erase(_ id: VirtualDevice.ID) async throws(SimulatorError) {
    try await self.runOnShutdownDevice(id, arguments: SimctlCommand.erase(udid:))
  }

  public func openSimulatorApp() async throws(SimulatorError) {
    let directory: URL
    if let provided = try await self.resolveDeveloperDirectory() {
      directory = provided
    } else {
      let result = try await self.run(
        SimctlCommand.xcodeSelect,
        SimctlCommand.printDeveloperDirectory(),
        developerDirectory: nil,
        launchFailure: .developerToolsUnavailable
      )
      guard
        result.exitCode == 0,
        let selected = SimulatorAppLocator.developerDirectory(fromXcodeSelectOutput: result.stdout)
      else {
        throw .developerToolsUnavailable
      }
      directory = selected
    }
    guard let app = SimulatorAppLocator.candidates(developerDirectory: directory).first(where: self.fileExists) else {
      throw .simulatorAppNotFound
    }
    let result = try await self.run(
      SimctlCommand.open,
      [app.path(percentEncoded: false)],
      developerDirectory: directory,
      launchFailure: .commandFailed
    )
    if result.exitCode != 0 {
      throw .commandFailed
    }
  }

  /// 재조회하지 않는다: 실패 뒤 목록으로 설치 성공을 판정할 수 없다.
  public func install(_ app: URL, on id: VirtualDevice.ID) async throws(SimulatorError) {
    guard let udid = SimctlCommand.validatedUDID(id.rawValue) else {
      throw .deviceNotFound
    }
    guard app.isFileURL else {
      throw .appNotFound
    }
    let appPath = app.standardizedFileURL.path(percentEncoded: false)
    let directory = try await self.resolveDeveloperDirectory()
    let result = try await self.run(
      SimctlCommand.xcrun,
      SimctlCommand.install(udid: udid, appPath: appPath),
      developerDirectory: directory,
      launchFailure: .developerToolsUnavailable
    )
    guard result.exitCode == 0 else {
      throw SimctlErrorClassifier.installError(exitCode: result.exitCode, stderr: Self.stderr(result))
    }
  }

  /// 성공 stdout("<번들 ID>: <pid>")은 읽지 않는다. 재조회하지 않는다.
  public func launch(_ bundleID: AppBundleID, on id: VirtualDevice.ID) async throws(SimulatorError) {
    guard let udid = SimctlCommand.validatedUDID(id.rawValue) else {
      throw .deviceNotFound
    }
    let directory = try await self.resolveDeveloperDirectory()
    let result = try await self.run(
      SimctlCommand.xcrun,
      SimctlCommand.launch(udid: udid, bundleID: bundleID.rawValue),
      developerDirectory: directory,
      launchFailure: .developerToolsUnavailable
    )
    guard result.exitCode == 0 else {
      throw SimctlErrorClassifier.launchError(exitCode: result.exitCode, stderr: Self.stderr(result))
    }
  }

  /// 재조회하지 않는다: 실패 뒤 목록으로 링크가 열렸는지 판정할 수 없다.
  public func openURL(_ link: DeepLink, on id: VirtualDevice.ID) async throws(SimulatorError) {
    guard let udid = SimctlCommand.validatedUDID(id.rawValue) else {
      throw .deviceNotFound
    }
    let directory = try await self.resolveDeveloperDirectory()
    let result = try await self.run(
      SimctlCommand.xcrun,
      SimctlCommand.openURL(udid: udid, url: link.url.absoluteString),
      developerDirectory: directory,
      launchFailure: .developerToolsUnavailable
    )
    guard result.exitCode == 0 else {
      throw SimctlErrorClassifier.openURLError(exitCode: result.exitCode, stderr: Self.stderr(result))
    }
  }

  /// provider 가 없으면 nil (`xcode-select` 기본값). provider 가 nil 을 돌려주면 명령을 실행하지 않도록 던진다.
  private func resolveDeveloperDirectory() async throws(SimulatorError) -> URL? {
    guard let developerDirectory = self.developerDirectory else { return nil }
    guard let directory = await developerDirectory() else {
      throw .developerToolsUnavailable
    }
    return directory
  }

  private func inventory(developerDirectory: URL?) async throws(SimulatorError) -> DeviceInventory {
    let result = try await self.run(
      SimctlCommand.xcrun,
      SimctlCommand.list(),
      developerDirectory: developerDirectory,
      launchFailure: .developerToolsUnavailable
    )
    guard result.exitCode == 0 else {
      throw Self.classify(result)
    }
    return try SimctlListDecoder.inventory(from: result.stdout)
  }

  /// 명령이 실패하면 같은 디렉터리로 다시 읽어, 이미 원하는 상태면 성공으로 본다.
  /// 아니면(재조회가 실패해도) 처음 실패를 분류한 에러를 던진다.
  private func changeState(
    of id: VirtualDevice.ID,
    arguments: (String) -> [String],
    succeedsIn targetStates: Set<VirtualDevice.State>
  ) async throws(SimulatorError) {
    guard let udid = SimctlCommand.validatedUDID(id.rawValue) else {
      throw .deviceNotFound
    }
    let directory = try await self.resolveDeveloperDirectory()
    let result = try await self.run(
      SimctlCommand.xcrun,
      arguments(udid),
      developerDirectory: directory,
      launchFailure: .developerToolsUnavailable
    )
    guard result.exitCode != 0 else { return }
    let failure = Self.classify(result)
    if
      let inventory = try? await self.inventory(developerDirectory: directory),
      let device = inventory.devices.first(where: { SimctlCommand.validatedUDID($0.id.rawValue) == udid }),
      targetStates.contains(device.state)
    {
      return
    }
    throw failure
  }

  /// 같은 디렉터리로 목록을 다시 읽어 꺼진 기기일 때만 명령을 실행한다 (delete 는 켜진 기기도 끄고 지우므로).
  /// 쓸 수 있는지는 보지 않는다. 확인과 실행 사이에 상태가 바뀌는 드문 경우는 막지 못하고, 실패 뒤 재조회는 하지 않는다.
  private func runOnShutdownDevice(
    _ id: VirtualDevice.ID,
    arguments: (String) -> [String]
  ) async throws(SimulatorError) {
    guard let udid = SimctlCommand.validatedUDID(id.rawValue) else {
      throw .deviceNotFound
    }
    let directory = try await self.resolveDeveloperDirectory()
    let inventory = try await self.inventory(developerDirectory: directory)
    guard let device = inventory.devices.first(where: { SimctlCommand.validatedUDID($0.id.rawValue) == udid }) else {
      throw .deviceNotFound
    }
    guard device.state == .shutdown else {
      throw .deviceNotShutdown
    }
    let result = try await self.run(
      SimctlCommand.xcrun,
      arguments(udid),
      developerDirectory: directory,
      launchFailure: .developerToolsUnavailable
    )
    guard result.exitCode == 0 else {
      throw Self.classify(result)
    }
  }

  private func run(
    _ executable: URL,
    _ arguments: [String],
    developerDirectory: URL?,
    launchFailure: SimulatorError
  ) async throws(SimulatorError) -> CommandResult {
    let environment = SimctlCommand.environment(base: self.baseEnvironment, developerDirectory: developerDirectory)
    do {
      return try await self.command.run(executable, arguments, environment: environment)
    } catch {
      throw launchFailure
    }
  }

  private static func classify(_ result: CommandResult) -> SimulatorError {
    SimctlErrorClassifier.error(exitCode: result.exitCode, stderr: String(bytes: result.stderr, encoding: .utf8) ?? "")
  }

  /// install·launch·openurl 의 stderr 에는 앱이 정한 글자나 사용자가 넣은 URL 이 섞인다. 잘못된 UTF-8 이면 Latin-1 로 읽는다
  /// (실패하지 않고, 분류가 보는 domain 줄·"reason: NotFound" 는 ASCII 라 그대로 남는다).
  private static func stderr(_ result: CommandResult) -> String {
    String(bytes: result.stderr, encoding: .utf8) ?? String(bytes: result.stderr, encoding: .isoLatin1) ?? ""
  }
}

// MARK: - 런타임 이미지

public extension SimulatorClientImpl {
  func fetchRuntimeImages() async throws(SimulatorError) -> [RuntimeImage] {
    let directory = try await self.resolveDeveloperDirectory()
    let result = try await self.run(
      SimctlCommand.xcrun,
      SimctlCommand.runtimeList(),
      developerDirectory: directory,
      launchFailure: .developerToolsUnavailable
    )
    guard result.exitCode == 0 else {
      throw Self.classify(result)
    }
    return try SimctlRuntimeListDecoder.images(from: result.stdout)
  }
}
