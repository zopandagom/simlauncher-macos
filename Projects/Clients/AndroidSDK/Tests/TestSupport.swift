import AndroidSDKInterface
import CommandInterface
import CommandTesting
import Core
import CryptoKit
import DownloadInterface
import DownloadTesting
import Foundation
import Synchronization
import Testing
@testable import AndroidSDKImpl

/// 테스트마다 만드는 임시 폴더. 끝나면 `remove()` 로 지운다.
struct TemporaryDirectory {
  /// 심볼릭 링크를 푼 경로 (`/var` → `/private/var`).
  let url: URL

  init() throws {
    let base = FileManager.default.temporaryDirectory.appending(path: "AndroidSDKTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    self.url = try URL(filePath: #require(RealPath.of(base)), directoryHint: .isDirectory)
  }

  /// 읽기·쓰기 권한을 뺀 폴더가 있어도 지우도록 폴더마다 u+rwx 를 더하며 훑은 뒤 지운다.
  func remove() {
    StagingFolders.forceRemove(self.url)
  }

  func child(_ path: String) -> URL {
    self.url.appending(path: path, directoryHint: .isDirectory)
  }
}

/// 테스트가 만드는 파일 트리. 경로는 `base` 기준 상대 경로이고 중간 폴더를 만든다.
enum FileTree {
  static func directory(_ base: URL, _ path: String, mode: Int16? = nil) throws {
    let url = base.appending(path: path, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    if let mode {
      try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path(percentEncoded: false))
    }
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
  static func exists(_ url: URL) -> Bool {
    SDKFiles.exists(url)
  }

  static func names(_ url: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))) ?? []).sorted()
  }

  static func read(_ url: URL) -> String? {
    try? String(contentsOf: url, encoding: .utf8)
  }

  /// 설치된 구성 요소 트리 (실행 파일 0o755·source.properties).
  static func installed(_ component: AndroidSDKComponent, in sdk: URL) throws {
    let spec = PackageSpec(component)
    let destination = spec.destination(in: sdk)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    for file in spec.files {
      try self.file(destination, file.name, contents: file.contents, mode: file.mode)
    }
  }
}

/// 패키지 안 파일 하나 (맨 위 폴더 기준 이름).
struct PackageFile {
  let name: String
  let contents: String
  let mode: Int16

  init(_ name: String, _ contents: String, mode: Int16) {
    self.name = name
    self.contents = contents
    self.mode = mode
  }
}

/// 테스트 패키지 하나: 계획의 path, zip 안 맨 위 폴더 이름, 푼 뒤의 파일.
struct PackageSpec {
  let component: AndroidSDKComponent
  let path: AndroidPackagePath
  let top: String
  let files: [PackageFile]

  init(_ component: AndroidSDKComponent) {
    self.component = component
    switch component {
    case .platformTools:
      self.path = AndroidPackagePath("platform-tools")!
      self.top = "platform-tools"
      self.files = [
        PackageFile("adb", "adb", mode: 0o755),
        PackageFile("source.properties", "Pkg.UserSrc=false\nPkg.Revision=37.0.1\n", mode: 0o644),
      ]
    case .emulator:
      self.path = AndroidPackagePath("emulator")!
      self.top = "emulator"
      self.files = [
        PackageFile("emulator", "emulator", mode: 0o755),
        PackageFile("source.properties", "Pkg.Path=emulator\nPkg.Revision=37.2.12\n", mode: 0o644),
      ]
    case .systemImage:
      self.path = AndroidPackagePath("system-images;android-37.0;google_apis;arm64-v8a")!
      self.top = "arm64-v8a"
      self.files = [
        PackageFile("system.img", "img", mode: 0o644),
        PackageFile("source.properties", "Pkg.Revision=7\nSystemImage.Abi=arm64-v8a\n", mode: 0o644),
      ]
    }
  }

  func destination(in sdk: URL) -> URL {
    var url = sdk
    for part in self.path.components {
      url = url.appending(path: part, directoryHint: .isDirectory)
    }
    return url
  }

  /// 받은 파일 내용. Fake 명령이 `source.zip` 링크 대상을 읽어 어느 패키지인지 안다.
  var bytes: Data {
    Data("zip:\(self.component.folderName)".utf8)
  }

  var url: DownloadURL {
    DownloadURL("https://dl.example.com/\(self.component.folderName).zip")!
  }

  /// `env -i zipinfo -s -T` 와 같은 모양의 목록 (폴더 항목 없이 파일만, 실측 platform-tools 와 같다).
  /// 시스템 이미지는 Zip64 크기 열(`5498732544`)을 넣는다.
  var zipinfo: String {
    let sizes: [Int64] = self.component == .systemImage ? [5_498_732_544, 120] : [1000, 60]
    var lines = [
      "Archive:  /x/source.zip",
      "Zip file size: 2104098168 bytes, number of entries: \(self.files.count)",
    ]
    for (index, file) in self.files.enumerated() {
      let permissions = file.mode == 0o755 ? "-rwxr-xr-x" : "-rw-r--r--"
      lines.append("\(permissions)  3.0 unx \(sizes[index]) bx defN 20251014.120000 \(self.top)/\(file.name)")
    }
    lines.append("\(self.files.count) files, \(sizes.reduce(0, +)) bytes uncompressed, 100 bytes compressed:  99.0%")
    lines.append("")
    return lines.joined(separator: "\n")
  }

  var declaredBytes: Int64 {
    self.component == .systemImage ? 5_498_732_664 : 1060
  }

  /// unzip 자리에서 `contents/<top>/…` 를 만든다.
  func extract(into contents: URL) throws {
    for file in self.files {
      try FileTree.file(contents, "\(self.top)/\(file.name)", contents: file.contents, mode: file.mode)
    }
  }

  static func sha1(_ data: Data) -> ArchiveChecksum {
    ArchiveChecksum(algorithm: .sha1, hex: Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined())!
  }
}

/// 공개 메서드가 부르는 provider. 호출 수를 세고, 테스트가 도중에 값을 바꾼다.
final class RootProvider: Sendable {
  private let state: Mutex<(choice: AndroidSDKRootChoice, calls: Int)>

  init(_ choice: AndroidSDKRootChoice) {
    self.state = Mutex((choice, 0))
  }

  var calls: Int {
    self.state.withLock { $0.calls }
  }

  func set(_ choice: AndroidSDKRootChoice) {
    self.state.withLock { $0.choice = choice }
  }

  func next() -> AndroidSDKRootChoice {
    self.state.withLock { state in
      state.calls += 1
      return state.choice
    }
  }
}

/// 순서대로 쌓는 기록.
final class Recorder<Value: Sendable>: Sendable {
  private let values = Mutex<[Value]>([])

  func append(_ value: Value) {
    self.values.withLock { $0.append(value) }
  }

  var all: [Value] {
    self.values.withLock { $0 }
  }
}

extension CommandClientFake {
  /// 명령을 부르면 안 되는 테스트용.
  static var unused: CommandClientFake {
    CommandClientFake { invocation throws(CommandError) in
      Issue.record("명령을 부르지 않아야 한다: \(invocation.executable.path(percentEncoded: false))")
      throw .launchFailed
    }
  }
}

/// 테스트마다 만드는 SDK 루트·받기 폴더와 Impl. 실제 zipinfo·unzip 대신 CommandClientFake 가 패키지별 목록을 돌려주고,
/// unzip 자리에서 `contents/` 에 트리를 만든다. 받기는 DownloadClientFake 가 주소별로 테스트가 쓴 작은 파일을 돌려준다.
struct Harness {
  let directory: TemporaryDirectory
  let sdk: URL
  let downloads: URL
  let download: DownloadClientFake
  let command: CommandClientFake
  let provider: RootProvider
  let client: AndroidSDKClientImpl

  /// - Parameters:
  ///   - root: nil 이면 `<tmp>/sdk` 기본 위치 (isDefault true, 처음에는 없다).
  ///   - zipinfo: 패키지마다 zipinfo 결과.
  ///   - unzip: 패키지마다 받은 `contents/` 에 트리를 만들고 결과를 돌려준다.
  ///   - cancellableUnzip: 있으면 unzip 을 이것이 맡는다 (취소 테스트).
  ///   - capacity: 경로별 여유 공간.
  ///   - volume: 경로별 볼륨 사실.
  init(
    root: AndroidSDKRootChoice? = nil,
    zipinfo: @escaping @Sendable (PackageSpec) -> CommandResult = { .success(Data($0.zipinfo.utf8)) },
    unzip: @escaping @Sendable (PackageSpec, URL) throws -> CommandResult = { spec, contents in
      try spec.extract(into: contents)
      return .success()
    },
    cancellableUnzip: CommandClientFake.CancellableHandler? = nil,
    capacity: @escaping @Sendable (URL) -> Int64? = { _ in .max },
    volume: @escaping @Sendable (URL) -> SDKVolume = { _ in SDKVolume(
      device: 1,
      name: "Test",
      supportsSymbolicLinks: true
    ) }
  ) throws {
    self.directory = try TemporaryDirectory()
    self.sdk = self.directory.child("sdk")
    self.downloads = self.directory.child("downloads")
    try FileManager.default.createDirectory(at: self.downloads, withIntermediateDirectories: true)
    self.download = DownloadClientFake()
    self.command = CommandClientFake(
      handler: { invocation throws(CommandError) in
        guard let spec = Self.spec(source: invocation.arguments[2]) else {
          Issue.record("모르는 source: \(invocation.arguments)")
          throw .launchFailed
        }
        switch invocation.executable {
        case PackageZipCommand.zipinfo:
          return zipinfo(spec)
        case PackageZipCommand.unzip:
          do {
            return try unzip(spec, URL(filePath: invocation.arguments[4], directoryHint: .isDirectory))
          } catch {
            Issue.record("트리를 만들지 못했다: \(error)")
            throw .launchFailed
          }
        default:
          Issue.record("모르는 명령: \(invocation.executable)")
          throw .launchFailed
        }
      },
      cancellableHandler: cancellableUnzip
    )
    let provider = RootProvider(root ?? .root(AndroidSDKRoot(url: self.sdk, isDefault: true)))
    self.provider = provider
    self.client = AndroidSDKClientImpl(
      download: self.download,
      command: self.command,
      hostArchitecture: .arm64,
      sdkRoot: { provider.next() },
      availableCapacity: capacity,
      volume: volume,
      downloadsDirectory: self.downloads,
      endpoints: Self.endpoints
    )
  }

  static let endpoints = RepositoryEndpoints(
    repository: DownloadURL("https://repo.example.com/android/repository2-3.xml")!,
    repositoryBase: DownloadURL("https://repo.example.com/android/")!,
    systemImages: DownloadURL("https://repo.example.com/android/sys-img/sys-img2-3.xml")!,
    systemImagesBase: DownloadURL("https://repo.example.com/android/sys-img/")!
  )

  static let license = AndroidLicense(id: "android-sdk-license", text: "Terms (test)")

  var root: AndroidSDKRoot {
    AndroidSDKRoot(url: self.sdk, isDefault: true)
  }

  /// `source.zip` 링크 대상의 내용으로 패키지를 찾는다.
  static func spec(source: String) -> PackageSpec? {
    guard let text = try? String(contentsOfFile: source, encoding: .utf8) else {
      return nil
    }
    return AndroidSDKComponent.allCases.map(PackageSpec.init).first { String(data: $0.bytes, encoding: .utf8) == text }
  }

  /// 구성 요소마다 받은 파일을 쓰고 Fake 의 주소별 결과로 둔 계획. `corrupt` 의 구성 요소는 계획의 체크섬이 다르다.
  func plan(
    _ components: [AndroidSDKComponent] = AndroidSDKComponent.allCases,
    root: AndroidSDKRoot? = nil,
    corrupt: Set<AndroidSDKComponent> = [],
    wrongSize: Set<AndroidSDKComponent> = []
  ) throws -> AndroidSDKInstallPlan {
    var packages: [AndroidSelectedPackage] = []
    for (index, component) in components.enumerated() {
      let spec = PackageSpec(component)
      let folder = self.downloads.appending(path: "SimLauncher-Download-\(index)", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let file = folder.appending(path: "download", directoryHint: .notDirectory)
      try spec.bytes.write(to: file)
      self.download.setDownloadResult(
        .success(DownloadedFile(
          file: file,
          folder: folder,
          byteCount: Int64(spec.bytes.count),
          mimeType: "application/zip"
        )),
        for: spec.url
      )
      let checksum = corrupt.contains(component) ? PackageSpec.sha1(Data("other".utf8)) : PackageSpec.sha1(spec.bytes)
      let size = Int64(spec.bytes.count) + (wrongSize.contains(component) ? 1 : 0)
      packages.append(AndroidSelectedPackage(
        component: component,
        path: spec.path,
        revision: AndroidRevision(major: 1),
        displayName: component.folderName,
        license: Self.license,
        archive: AndroidArchive(
          hostOS: "macosx",
          hostArch: nil,
          size: size,
          checksum: checksum,
          fileName: "\(component.folderName).zip"
        ),
        url: spec.url
      ))
    }
    return AndroidSDKInstallPlan(
      root: root ?? self.root,
      sdkVolumeName: "Test",
      sameVolumeAsDownloads: true,
      packages: packages,
      licenses: packages.isEmpty ? [] : [Self.license]
    )
  }

  /// 설치하고 결과와 진행 알림을 돌려준다. `onProgress` 는 알림마다 설치 Task 안에서 부른다.
  func install(
    _ plan: AndroidSDKInstallPlan,
    accepted: Set<String>? = nil,
    onProgress: @escaping @Sendable (AndroidSDKInstallProgress) -> Void = { _ in }
  ) async -> (result: Result<AndroidSDKInstallOutcome, AndroidSDKInstallError>, progress: [AndroidSDKInstallProgress]) {
    let recorder = Recorder<AndroidSDKInstallProgress>()
    let accepted = accepted ?? Set(plan.licenses.map(\.fingerprint))
    do throws(AndroidSDKInstallError) {
      let outcome = try await self.client.install(plan, acceptedLicenses: accepted) { progress in
        recorder.append(progress)
        onProgress(progress)
      }
      return (.success(outcome), recorder.all)
    } catch {
      return (.failure(error), recorder.all)
    }
  }

  func planResult() async -> Result<AndroidSDKInstallPlan, AndroidSDKPlanError> {
    do throws(AndroidSDKPlanError) {
      return try await .success(self.client.fetchInstallPlan())
    } catch {
      return .failure(error)
    }
  }

  /// 받기 호출 수.
  var downloadCount: Int {
    self.download.calls.count(where: {
      if case .download = $0 {
        true
      } else {
        false
      }
    })
  }

  /// 지운 받은 파일 수.
  var removedDownloads: [DownloadedFile] {
    self.download.calls.compactMap {
      if case let .removeDownloaded(file) = $0 {
        file
      } else {
        nil
      }
    }
  }

  /// SDK 안 스테이징 폴더 이름.
  var stagingNames: [String] {
    FileTree.names(self.sdk).filter { $0.hasPrefix(StagingFolders.prefix) }
  }

  var executables: [URL] {
    self.command.invocations.map(\.executable)
  }
}

/// 기다리기 (10초 상한). 넘으면 실패.
func waitUntil(_ condition: @escaping @Sendable () -> Bool) async throws {
  let deadline = ContinuousClock.now + .seconds(10)
  while !condition() {
    guard ContinuousClock.now < deadline else {
      Issue.record("10초 안에 조건이 맞지 않았다")
      throw CancellationError()
    }
    try await Task.sleep(for: .milliseconds(5))
  }
}
