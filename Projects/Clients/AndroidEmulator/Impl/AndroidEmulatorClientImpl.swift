import AndroidEmulatorInterface
import CommandInterface
import Core
import Foundation

/// `~/.android/avd` 의 파일을 읽고 쓰며, SDK 의 emulator(`launch`)·adb(`runCancellable`)를 `CommandClient` 로 실행하는
/// `AndroidEmulatorClient`. emulator 의 실패 문구는 원인과 맞지 않아(실측) 출력을 해석하지 않고 켜기 전에 파일로 검사한다.
/// 이 앱이 띄운 에뮬레이터는 앱이 끝나도 남는다 (종료 때 끄지 않는다).
public struct AndroidEmulatorClientImpl: AndroidEmulatorClient {
  /// 확인 간격과 제한 시간. 테스트가 줄인다.
  struct Timing: Sendable {
    /// 켜기 완료 확인·끌 serial 다시 찾기 간격.
    var pollInterval: Duration
    /// 켜기 완료를 기다리는 한도 (동시 첫 부팅 2대 실측 81~197초를 덮는다).
    var bootLimit: Duration
    /// 끄기 뒤 잠금 풀림 확인 간격.
    var shutdownPollInterval: Duration
    /// 끄기를 기다리는 한도 (에뮬레이터 자체 감시가 120초면 스스로 강제 종료한다).
    var shutdownLimit: Duration
    /// 끌 serial 이 adb 에 아직 없을 때 다시 찾는 한도. 지나도 adb 가 답했으면 실패하지 않고 잠금 풀림을 기다린다(앱 밖에서 끄는 중).
    var serialSearchLimit: Duration
    /// adb 명령 하나의 한도.
    var adbTimeout: Duration
    /// `adb install` 하나의 한도 (실측 최대 48 MB 11.3초에서 크게 잡았다).
    var installTimeout: Duration
    /// `screencap` 하나의 한도 (실측 1.0~1.5초, 녹화 중에는 3.0초).
    var screenshotTimeout: Duration = .seconds(30)
    /// 기기 안 `kill -2` 뒤 녹화 adb 가 끝나기를 기다리는 한도 (실측 0.82초 이하). 넘으면 호스트에서 대신 멈춘다.
    var recordingStopLimit: Duration = .seconds(30)
    /// 호스트에서 대신 멈춘 뒤 기기 쪽 마무리를 기다리는 시간 (실측: 호스트 SIGINT 뒤 약 0.8초에 끝났다).
    var recordingSettle: Duration = .seconds(2)
    /// 녹화 파일 `adb pull` 하나의 한도 (실측 7.7 MB 0.07초).
    var transferTimeout: Duration = .seconds(600)

    static let standard = Timing(
      pollInterval: .seconds(1),
      bootLimit: .seconds(600),
      shutdownPollInterval: .milliseconds(500),
      shutdownLimit: .seconds(150),
      serialSearchLimit: .seconds(10),
      adbTimeout: .seconds(10),
      installTimeout: .seconds(600)
    )
  }

  /// 목록 읽기로 얻은 기기 하나와 그 사실.
  struct ReadDevice: Sendable {
    let entry: AVDEntry
    let facts: AndroidAVDFacts
    let device: AndroidVirtualDevice
    /// adb 로 찾은 에뮬레이터 (실행 중인 AVD 가 있을 때만 adb 를 부른다).
    let emulator: ADBEmulator?
  }

  let command: any CommandClient
  let sdkRoot: @Sendable () async -> AndroidSDKRootChoice
  let home: URL
  let host: AndroidHostArchitecture
  let timing: Timing
  let launched = LaunchedEmulators()

  /// App 은 이 Impl 을 하나만 만든다 (이 앱이 띄운 에뮬레이터 표를 함께 쓴다).
  /// - Parameters:
  ///   - command: AndroidSDK Impl 과 같은 인스턴스.
  ///   - sdkRoot: 공개 메서드 한 번에 한 번 부른다. AndroidSDK Impl 과 같은 클로저.
  ///   - home: 사용자 홈 폴더. AVD 는 `home/.android/avd`, emulator·adb 의 `HOME` 도 이것이다.
  ///   - host: 이 Mac 의 아키텍처 (`AndroidHostArchitecture(AppBundleClientImpl.hostArchitecture)`).
  public init(
    command: any CommandClient,
    sdkRoot: @escaping @Sendable () async -> AndroidSDKRootChoice,
    home: URL,
    host: AndroidHostArchitecture
  ) {
    self.init(command: command, sdkRoot: sdkRoot, home: home, host: host, timing: .standard)
  }

  /// 테스트용: 확인 간격·제한 시간을 정한다.
  init(
    command: any CommandClient,
    sdkRoot: @escaping @Sendable () async -> AndroidSDKRootChoice,
    home: URL,
    host: AndroidHostArchitecture,
    timing: Timing
  ) {
    self.command = command
    self.sdkRoot = sdkRoot
    self.home = home
    self.host = host
    self.timing = timing
  }

  @concurrent
  public func fetchDevices() async throws(AndroidEmulatorError) -> AndroidDeviceInventory {
    let tools = try await SDKTools.resolve(self.sdkRoot())
    let devices = try await self.readDevices(tools: tools)
    return AndroidDeviceInventory(
      devices: devices.map(\.device),
      creationOptions: self.creationOptions(tools)
    )
  }

  /// 다시 읽기 → 쓸 수 있는지 → (이 앱이 띄운 프로세스가 돌거나 잠금이 있으면 띄우지 않고) `adb devices` 한 번(실패 무시)
  /// → emulator 띄우기 → 완료 기다리기.
  @concurrent
  public func boot(_ id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) {
    let tools = try await SDKTools.resolve(self.sdkRoot())
    let target = try await self.read(id, tools: tools)
    if case let .unavailable(reason) = target.device.availability {
      throw .deviceUnavailable(reason)
    }
    guard let folder = target.entry.folder else {
      throw .deviceUnavailable(.folderMissing)
    }
    var process = self.launched.running(target.entry.name, command: self.command)
    if process == nil, target.facts.lockHeld != true {
      process = try await self.launchEmulator(target.entry.name, tools: tools)
    }
    try await self.waitForBoot(target.entry.name, folder: folder, process: process, tools: tools)
  }

  /// 다시 읽기 → 꺼져 있으면 성공 → serial 이면 `emu kill`, 없고 이 앱이 띄운 프로세스면 SIGINT,
  /// 둘 다 없으면 serial 을 다시 찾는다 → 잠금 풀림(또는 프로세스 끝남)까지 기다린다.
  /// 앱 밖에서 끄는 중이면 저장이 끝날 때까지 adb 목록에는 남고 `emu avd name`·`emu kill` 이 막힌다(실측). 그래서 다시 찾아도
  /// 없는데 adb 는 답했거나, `emu kill` 이 실패했는데 이 앱이 띄운 프로세스가 없고 잠금이 풀렸거나 잠금이 잡힌 채 그 기기가 이름에 답하지 않으면
  /// 실패로 끝내지 않고 잠금 풀림을 기다린다.
  @concurrent
  public func shutdown(_ id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) {
    let tools = try await SDKTools.resolve(self.sdkRoot())
    let target = try await self.read(id, tools: tools)
    let name = target.entry.name
    let process = self.launched.running(name, command: self.command)
    guard target.facts.lockHeld == true || process != nil || target.emulator != nil else {
      return
    }
    let adb = self.adb(tools)
    var serial = target.emulator?.serial
    if serial == nil, process == nil {
      switch try await self.searchSerial(name, folder: target.entry.folder, adb: adb) {
      case let .found(found):
        serial = found
      case .released:
        return
      case .unidentified:
        break
      }
    }
    try await self.requestShutdown(serial: serial, process: process, target: target, adb: adb)
    try await self.waitForShutdown(name, folder: target.entry.folder, process: process)
  }

  /// serial 이면 `emu kill`(실패하면 SIGINT 또는 앱 밖 종료 확인), 없으면 이 앱이 띄운 프로세스에 SIGINT.
  private func requestShutdown(
    serial: String?,
    process: LaunchedProcess?,
    target: ReadDevice,
    adb: ADBCommand
  ) async throws(AndroidEmulatorError) {
    if let serial {
      do throws(AndroidEmulatorError) {
        try await adb.emuKill(serial: serial)
      } catch {
        guard error != .cancelled else {
          throw error
        }
        if let process {
          self.command.interrupt(process)
        } else {
          guard try await self.externalShutdownInProgress(target.entry.name, folder: target.entry.folder, adb: adb)
          else {
            throw error
          }
        }
      }
    } else if let process {
      self.command.interrupt(process)
    }
  }

  /// 표시 이름 검사 → 선택지 다시 읽기 → 폴더 준비 → 이름 정하기 → 독점 생성.
  @concurrent
  public func create(
    displayName: String,
    image: AndroidSystemImageRef,
    profile: AndroidDeviceProfile.ID
  ) async throws(AndroidEmulatorError) -> AndroidVirtualDevice.ID {
    // AVDIniFile.render 는 줄 바꿈을 막지 않으므로 쓰기 전에 반드시 이 검사를 통과시킨다.
    if let problem = DeviceName.problem(in: displayName) {
      throw .invalidDeviceName(problem)
    }
    let tools = try await SDKTools.resolve(self.sdkRoot())
    let options = self.creationOptions(tools)
    guard options.contains(image: image, profile: profile), let chosen = AndroidDeviceProfile.profile(profile) else {
      throw .creationOptionUnavailable
    }
    try AVDFiles.prepareFolders(home: self.home)
    return try AVDFiles.create(
      home: self.home,
      device: .init(
        displayName: DeviceName.normalized(displayName),
        image: image,
        profile: chosen,
        host: self.host
      ),
      taken: AVDFolderScan.takenNames(home: self.home)
    )
  }

  @concurrent
  public func delete(_ id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) -> AndroidDeleteOutcome {
    let tools = try await SDKTools.resolve(self.sdkRoot())
    let target = try await self.read(id, tools: tools)
    try Self.rejectRunning(target)
    return try AVDFiles.remove(target.entry)
  }

  @concurrent
  public func erase(_ id: AndroidVirtualDevice.ID) async throws(AndroidEmulatorError) {
    let tools = try await SDKTools.resolve(self.sdkRoot())
    let target = try await self.read(id, tools: tools)
    try Self.rejectRunning(target)
    if case let .unavailable(reason) = target.device.availability {
      throw .deviceUnavailable(reason)
    }
    guard let folder = target.entry.folder, AVDFiles.isDeviceFolder(folder) else {
      throw .unsafeDeviceFolder(target.entry.folder)
    }
    try AVDFiles.reset(folder: folder)
  }
}

// MARK: - 읽기

extension AndroidEmulatorClientImpl {
  /// 지금 SDK 의 만들기 선택지. 이미지 목록을 한 번만 읽고 그 이미지들의 접기 설정 파일을 확인한다.
  func creationOptions(_ tools: SDKTools) -> AndroidDeviceCreationOptions {
    let images = tools.installedImages()
    return AndroidDeviceCreationOptions(
      installedImages: images,
      foldableImages: tools.foldableImages(images),
      host: self.host
    )
  }

  /// 폴더를 읽어 기기마다 사실을 모으고, 잠금이 있는 기기가 하나라도 있을 때만 adb 를 부른다.
  /// adb 가 실패하면 adb 상태 없이(잠금만으로) 판정한다. adb 가 성공했는데 잠금 있는 기기의 serial 이 없으면 `.offline`.
  func readDevices(tools: SDKTools) async throws(AndroidEmulatorError) -> [ReadDevice] {
    let entries = try AVDFolderScan.entries(home: self.home)
    let facts = entries.map { AVDFolderScan.facts($0, tools: tools) }
    let emulators: [String: ADBEmulator]? = if facts.contains(where: { $0.lockHeld == true }) {
      await self.adb(tools).emulators(names: Set(entries.map(\.name)))
    } else {
      [:]
    }
    return zip(entries, facts).map { entry, facts in
      let emulator = emulators?[entry.name]
      let adbState: AndroidADBBootState? = if let emulators {
        emulator?.state ?? (facts.lockHeld == true ? .offline : nil)
      } else {
        nil
      }
      return ReadDevice(
        entry: entry,
        facts: facts,
        device: AndroidDeviceJudge.device(facts, host: self.host, adb: adbState),
        emulator: emulator
      )
    }
  }

  /// 파일 이름이 정확히 `<id>.ini` 인 항목. 없으면 `.deviceNotFound`.
  func read(_ id: AndroidVirtualDevice.ID, tools: SDKTools) async throws(AndroidEmulatorError) -> ReadDevice {
    guard let found = try await self.readDevices(tools: tools).first(where: { $0.entry.name == id.rawValue }) else {
      throw .deviceNotFound
    }
    return found
  }

  /// 잠금이 있거나 adb 에 보이면 `.deviceRunning`.
  static func rejectRunning(_ target: ReadDevice) throws(AndroidEmulatorError) {
    if target.facts.lockHeld == true || target.emulator != nil {
      throw .deviceRunning
    }
  }

  func adb(_ tools: SDKTools) -> ADBCommand {
    ADBCommand(command: self.command, executable: tools.adb, home: self.home, timeout: self.timing.adbTimeout)
  }
}
