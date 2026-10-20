import CommandInterface
import Core
import DevEnvironmentInterface
import Foundation
import Synchronization

/// xcode-select(`CommandClient`)와 `/Applications` 의 번들로 쓸 Xcode 를 고르고, 그 안의 xcodebuild 로 준비 상태를 보고
/// 기본 iOS 런타임을 설치하는 `DevEnvironmentClient`. 실행하는 것은 `/usr/bin/xcode-select`, 고른 Xcode 안의 xcodebuild,
/// `/usr/bin/open` 뿐이다.
/// 상태를 갖지 않아 여러 호출이 동시에 와도 각자 다시 찾는다.
public struct DevEnvironmentClientImpl: DevEnvironmentClient {
  /// Info.plist 를 읽는 상한. 넘으면 그 번들은 Xcode 로 보지 않는다.
  static let infoPlistSizeLimit = 1_048_576
  /// 확인 명령(xcode-select -p·-checkFirstLaunchStatus·-license check)의 시간 제한. 정상 값은 합쳐 0.3초 미만이다.
  /// 지나면 멈추기 시작해(SIGINT → SIGTERM → SIGKILL) 실패로 본다.
  static let checkTimeout: Duration = .seconds(30)

  private let command: any CommandClient
  private let applicationsDirectory: URL
  private let baseEnvironment: [String: String]

  /// `/Applications` 와 이 프로세스의 환경을 쓴다.
  /// - Parameter command: xcode-select·xcodebuild·open 실행. App 이 `CommandClientImpl` 을 넘긴다.
  public init(command: any CommandClient) {
    self.init(command: command, applicationsDirectory: Self.defaultApplicationsDirectory)
  }

  /// 테스트용: Xcode 를 찾을 폴더와 명령에 물려줄 환경을 정한다.
  init(
    command: any CommandClient,
    applicationsDirectory: URL,
    baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.command = command
    self.applicationsDirectory = applicationsDirectory
    self.baseEnvironment = baseEnvironment
  }

  static let defaultApplicationsDirectory = URL(filePath: "/Applications", directoryHint: .isDirectory)

  @concurrent
  public func selectedXcode() async -> XcodeInstallation? {
    await self.choose().xcode
  }

  /// 고른 Xcode 의 `-checkFirstLaunchStatus` 가 0 이면 준비됨 (라이선스·구성요소 모두 확인된다).
  /// 0 이 아니면 라이선스 때문인지 `-license check` 로 따로 본다. Xcode 가 없으면 xcodebuild 를 실행하지 않는다.
  @concurrent
  public func checkEnvironment() async throws(DevEnvironmentError) -> DevEnvironmentStatus {
    let choice = await self.choose()
    guard let xcode = choice.xcode else {
      return DevEnvironmentStatus(
        xcode: nil,
        commandLineToolsSelected: choice.commandLineToolsSelected,
        checks: .notRun
      )
    }
    let firstLaunch = try await self.runCheck(xcode, XcodeCommand.checkFirstLaunchStatus())
    let checks: XcodeSetupChecks
    if XcodeCommand.passed(firstLaunch) {
      checks = XcodeSetupChecks(licenseAccepted: true, firstLaunchComplete: true)
    } else {
      let license = try await self.runCheck(xcode, XcodeCommand.licenseCheck())
      checks = XcodeSetupChecks(licenseAccepted: XcodeCommand.passed(license), firstLaunchComplete: false)
    }
    return DevEnvironmentStatus(
      xcode: xcode,
      commandLineToolsSelected: choice.commandLineToolsSelected,
      checks: checks
    )
  }

  @concurrent
  public func openXcode() async throws(DevEnvironmentError) {
    guard let xcode = await self.choose().xcode else {
      throw .xcodeNotFound
    }
    try await self.runOpen(XcodeCommand.openApp(bundlePath: xcode.bundleURL.path(percentEncoded: false)))
  }

  public func openXcodeInAppStore() async throws(DevEnvironmentError) {
    try await self.runOpen(XcodeCommand.openAppStorePage())
  }

  /// 고른 Xcode 의 iOS Simulator SDK 파일을 읽는다 (명령은 xcode-select 하나, 네트워크 없음).
  @concurrent
  public func defaultIOSRuntime() async -> DefaultIOSRuntime? {
    guard
      let xcode = await self.choose().xcode,
      let settings = Self.readInfoPlist(XcodeCommand.iOSSimulatorSDKSettings(in: xcode)),
      let version = XcodeBundleReader.sdkVersion(settings: settings)
    else {
      return nil
    }
    let systemVersion = Self.readInfoPlist(XcodeCommand.iOSSimulatorSDKSystemVersion(in: xcode))
    let build = systemVersion.flatMap(XcodeBundleReader.sdkBuild(systemVersion:))
    return DefaultIOSRuntime(version: version, build: build)
  }

  /// 고른 Xcode 안의 xcodebuild 로 `-downloadPlatform iOS` 를 시간 제한 없이 실행한다 (느린 회선에서 1시간을 넘을 수 있고,
  /// 끊김에도 실패하지 않고 기다린다). 진행은 출력 해석기가 바뀐 것만 알리고,
  /// 결과는 전체 출력(`CommandResult`)의 종료 코드, xcodebuild 의 취소 알림(`Download was cancelled.`), 내려받기 줄 여부로
  /// 정한다 (넘기지 못한 조각이 있어도 같다).
  @concurrent
  public func installDefaultIOSRuntime(
    progress: @escaping @Sendable (RuntimeInstallProgress) async -> Void
  ) async throws(RuntimeInstallError) -> RuntimeInstallOutcome {
    guard let xcode = await self.choose().xcode else {
      throw .xcodeNotFound
    }
    guard !Task.isCancelled else {
      throw .cancelled
    }
    await progress(.preparing)
    let parser = ParserBox()
    let environment = XcodeCommand.environment(base: self.baseEnvironment, developerDirectory: xcode.developerDirectory)
    let result: CommandResult
    do throws(CommandError) {
      result = try await self.command.runCancellable(
        XcodeCommand.xcodebuild(in: xcode),
        XcodeCommand.downloadPlatformIOS(),
        environment: environment,
        timeout: nil
      ) { output in
        // 해석은 lock 안에서, 알림은 lock 밖에서 하나씩 기다린다.
        let updates = parser.state.withLock { $0.feed(output) }
        for update in updates {
          await progress(update)
        }
      }
    } catch {
      switch error {
      case .launchFailed:
        throw .launchFailed
      case .cancelled:
        throw .cancelled
      case .timedOut:
        throw .failed
      }
    }
    // 진행 해석기는 알림에만 쓴다: 늦게 온 취소로 넘기지 못한 조각이 있어도 결과는 전체 출력으로 정한다.
    let outcome = RuntimeInstallOutputParser.outcome(
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.exitCode
    )
    return try outcome.get()
  }

  /// realpath(3) 로 링크·`..` 를 푼 번들 경로. 대상이 없으면 nil.
  /// `URL.resolvingSymlinksInPath()` 는 `/private` 접두어를 지워 같은 번들이 경로마다 달라지므로 쓰지 않는다.
  static func canonicalBundleURL(_ url: URL) -> URL? {
    guard let path = realPath(url.path(percentEncoded: false)) else {
      return nil
    }
    return URL(filePath: path, directoryHint: .isDirectory)
  }

  /// xcode-select 가 가리키는 Xcode 가 유효하면 /Applications 를 나열하지 않고 그것을 쓴다
  /// (`XcodeSelection.choose` 도 selected 가 있으면 installed 를 보지 않는다).
  private func choose() async -> (xcode: XcodeInstallation?, commandLineToolsSelected: Bool) {
    let selection = await self.selection()
    if let selected = selection.selected {
      return (selected, selection.commandLineToolsSelected)
    }
    let xcode = XcodeSelection.choose(selected: nil, installed: self.installedXcodes())
    return (xcode, selection.commandLineToolsSelected)
  }

  /// `xcode-select -p` 를 `DEVELOPER_DIR` 를 지운 환경에서 실행한다. 시작 실패·시간 초과·0 아님·해석 실패면 선택 없음.
  /// 비구조 Task 안에서 실행해 호출한 Task 의 취소를 전하지 않는다: 취소로 "선택 없음"이 되면 `/Applications` 의
  /// 다른 Xcode 를 골라, xcode-select 와 다른 Xcode 로 명령을 돌리게 된다 (시간 제한만 받는다).
  private func selection() async -> (selected: XcodeInstallation?, commandLineToolsSelected: Bool) {
    let environment = XcodeCommand.environment(base: self.baseEnvironment, developerDirectory: nil)
    let command = self.command
    let output: CommandResult? = await Task {
      try? await command.runCancellable(
        XcodeCommand.xcodeSelect,
        XcodeCommand.printDeveloperDirectory(),
        environment: environment,
        timeout: Self.checkTimeout
      ) { _ in }
    }.value
    guard
      let result = output,
      let directory = XcodeCommand.selectedDeveloperDirectory(from: result)
    else {
      return (nil, false)
    }
    let selected = XcodeCommand.xcodeBundle(forDeveloperDirectory: directory).flatMap(Self.inspectBundle)
    return (selected, XcodeCommand.isCommandLineTools(directory))
  }

  /// 앱 폴더 맨 위의 .app 중 Xcode 번들. 하위 폴더는 보지 않고, 폴더를 못 읽으면 빈 배열.
  private func installedXcodes() -> [XcodeInstallation] {
    guard let entries = try? FileManager.default.contentsOfDirectory(
      at: self.applicationsDirectory,
      includingPropertiesForKeys: nil
    ) else {
      return []
    }
    return XcodeBundleReader.unique(XcodeBundleReader.candidates(entries).compactMap(Self.inspectBundle))
  }

  /// 표준 경로 → Info.plist(일반 파일, 상한까지) → Xcode 식별자·버전 → 안의 xcodebuild 가 실행 가능한 일반 파일.
  /// 하나라도 실패하면 nil (설치 중·부분 복사·다른 앱).
  private static func inspectBundle(_ url: URL) -> XcodeInstallation? {
    guard
      let bundle = canonicalBundleURL(url),
      let infoPlist = readInfoPlist(bundle.appending(path: "Contents/Info.plist", directoryHint: .notDirectory)),
      let installation = XcodeBundleReader.installation(bundleURL: bundle, infoPlist: infoPlist),
      isExecutableRegularFile(XcodeCommand.xcodebuild(in: installation))
    else {
      return nil
    }
    return installation
  }

  /// 링크를 따라간 일반 파일(Info.plist·SDK plist)을 상한 + 1 바이트까지 읽는다. 일반 파일이 아니거나(폴더·FIFO·대상 없는 링크),
  /// 읽지 못하거나, 상한을 넘으면 nil (전체를 메모리에 올리지 않는다).
  static func readInfoPlist(_ url: URL, limit: Int = Self.infoPlistSizeLimit) -> Data? {
    guard let path = realPath(url.path(percentEncoded: false)), isRegularFile(path) else {
      return nil
    }
    guard let handle = FileHandle(forReadingAtPath: path) else {
      return nil
    }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: limit + 1) ?? Data(), data.count <= limit else {
      return nil
    }
    return data
  }

  private static func isExecutableRegularFile(_ url: URL) -> Bool {
    guard let path = realPath(url.path(percentEncoded: false)) else {
      return false
    }
    return Self.isRegularFile(path) && FileManager.default.isExecutableFile(atPath: path)
  }

  private static func isRegularFile(_ path: String) -> Bool {
    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
    return attributes?[.type] as? FileAttributeType == .typeRegular
  }

  private static func realPath(_ path: String) -> String? {
    guard let resolved = realpath(path, nil) else {
      return nil
    }
    defer { free(resolved) }
    return String(cString: resolved)
  }

  /// 고른 Xcode 안의 xcodebuild 를 그 개발자 디렉터리로 `checkTimeout` 안에 실행한다.
  /// 시작하지 못했거나, 시간 초과·취소로 멈췄으면 `.checkFailed`.
  private func runCheck(_ xcode: XcodeInstallation, _ arguments: [String]) async throws(DevEnvironmentError)
    -> CommandResult
  {
    let environment = XcodeCommand.environment(base: self.baseEnvironment, developerDirectory: xcode.developerDirectory)
    do {
      return try await self.command.runCancellable(
        XcodeCommand.xcodebuild(in: xcode),
        arguments,
        environment: environment,
        timeout: Self.checkTimeout
      ) { _ in }
    } catch {
      throw .checkFailed
    }
  }

  /// `DEVELOPER_DIR` 를 지운 환경에서 `open` 을 실행한다. 시작하지 못하거나 0 이 아니면 `.openFailed`.
  private func runOpen(_ arguments: [String]) async throws(DevEnvironmentError) {
    let environment = XcodeCommand.environment(base: self.baseEnvironment, developerDirectory: nil)
    let result: CommandResult
    do {
      result = try await self.command.run(XcodeCommand.open, arguments, environment: environment)
    } catch {
      throw .openFailed
    }
    guard result.exitCode == 0 else {
      throw .openFailed
    }
  }
}

/// 진행 알림용 설치 출력 해석기 (결과 판정에는 쓰지 않는다). 출력 전달 클로저(@Sendable)가 바꾸므로 lock 으로 감싼다.
private final class ParserBox: Sendable {
  let state = Mutex(RuntimeInstallOutputParser())
}
