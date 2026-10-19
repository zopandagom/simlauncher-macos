import AppBundleInterface
import CommandInterface
import Core
import Foundation

/// 파일 시스템에서 .app 을 읽고, zip 은 임시 폴더에 zipinfo·ditto(`CommandClient`)로 풀어 검사하는 `AppBundleClient`.
/// 원본 파일은 고치지 않고, .app 은 일반 파일만 정해진 크기까지 읽는다.
public struct AppBundleClientImpl: AppBundleClient {
  /// Info.plist 를 읽는 상한. 넘으면 `.invalidBundle`.
  static let infoPlistSizeLimit = 1_048_576
  /// 실행 파일에서 읽는 앞부분 크기 (Mach-O·fat 헤더).
  static let executableHeaderSize = 4096

  public let hostArchitecture: CPUArchitecture
  private let command: any CommandClient
  private let temporaryDirectory: URL
  private let availableCapacity: @Sendable (URL) -> Int64?
  private let folders: ExtractionFolders

  /// 이 Mac 의 아키텍처(`HostArchitecture.current()`), `FileManager.default.temporaryDirectory`,
  /// 그 볼륨의 실제 여유 공간을 쓴다. App 은 이 Impl 을 하나만 만든다 (지금 쓰는 임시 폴더 목록을 함께 쓴다).
  /// - Parameter command: zipinfo·ditto 실행. App 이 `CommandClientImpl` 을 넘긴다.
  public init(command: any CommandClient) {
    self.init(hostArchitecture: HostArchitecture.current(), command: command)
  }

  /// 테스트용: 아키텍처·임시 폴더·여유 공간 읽기를 정한다. 여유 공간이 nil 이면 디스크 여유 확인을 건너뛴다.
  init(
    hostArchitecture: CPUArchitecture,
    command: any CommandClient,
    temporaryDirectory: URL = FileManager.default.temporaryDirectory,
    availableCapacity: @escaping @Sendable (URL) -> Int64? = Self.volumeAvailableCapacity
  ) {
    self.hostArchitecture = hostArchitecture
    self.command = command
    self.temporaryDirectory = temporaryDirectory
    self.availableCapacity = availableCapacity
    self.folders = ExtractionFolders(temporaryDirectory: temporaryDirectory)
  }

  /// 첫 실패에서 멈춘다: 파일 URL → 실제 경로 → 일반 파일 → 임시 폴더 준비 → zipinfo 목록 검사 → 디스크 여유 → ditto 풀기
  /// → 푼 뒤 실제 파일 검사. 임시 폴더를 만든 뒤의 실패는 폴더를 지운 뒤 던진다.
  /// 임시 폴더 `<tmp>/SimLauncher-Unzip-<UUID>/` 안에 `source.zip`(zip 의 실제 경로를 가리키는 링크)과 `contents/` 를 둔다.
  /// zipinfo 는 인자의 파일 이름을 와일드카드로 해석하므로 두 명령 모두 고정 이름 링크를 읽게 한다.
  @concurrent
  public func extractApp(fromZip url: URL) async throws(AppBundleError) -> ExtractedApp {
    guard url.isFileURL else {
      throw .notLocalFile
    }
    guard let zip = RealPath.of(url) else {
      throw .fileNotFound
    }
    guard
      let attributes = try? FileManager.default.attributesOfItem(atPath: zip),
      attributes[.type] as? FileAttributeType == .typeRegular
    else {
      throw .zipUnreadable
    }
    guard let tmp = RealPath.of(self.temporaryDirectory) else {
      throw .extractionUnavailable
    }
    let name = ExtractionFolders.newName()
    self.folders.register(name)
    let folder = URL(filePath: tmp, directoryHint: .isDirectory).appending(path: name, directoryHint: .isDirectory)
    do throws(AppBundleError) {
      let source = folder.appending(path: "source.zip", directoryHint: .notDirectory)
      let contents = folder.appending(path: "contents", directoryHint: .isDirectory)
      try Self.prepare(folder: folder, contents: contents, source: source, zip: zip)
      let listing = try await self.list(source)
      if let available = self.availableCapacity(URL(filePath: tmp, directoryHint: .isDirectory)),
         listing.declaredTotalBytes > available
      {
        throw .insufficientDiskSpace
      }
      try await self.extract(source, into: contents)
      let app = try ExtractedTreeCheck.check(contents: contents)
      return ExtractedApp(app: app, folder: folder)
    } catch {
      self.folders.remove(folder)
      throw error
    }
  }

  @concurrent
  public func removeExtracted(_ extracted: ExtractedApp) async {
    self.folders.remove(extracted.folder)
  }

  @concurrent
  public func removeLeftoverExtractions() async {
    self.folders.removeLeftovers()
  }

  /// 임시 폴더 볼륨의 `volumeAvailableCapacityForImportantUsage`. 읽지 못하면 nil.
  static func volumeAvailableCapacity(_ url: URL) -> Int64? {
    try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      .volumeAvailableCapacityForImportantUsage
  }

  /// 임시 폴더(0o700, 중간 폴더는 만들지 않음) → `contents/` → `source.zip` 링크. 실패하면 `.extractionUnavailable`.
  private static func prepare(folder: URL, contents: URL, source: URL, zip: String) throws(AppBundleError) {
    do {
      try FileManager.default.createDirectory(
        at: folder,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: false)
      try FileManager.default.createSymbolicLink(
        atPath: source.path(percentEncoded: false),
        withDestinationPath: zip
      )
    } catch {
      throw .extractionUnavailable
    }
  }

  /// zipinfo 목록을 읽어 풀기 전 검사를 한다. 항목이 0 개면 `.zipWithoutApp` (빈 zip 은 종료 코드 1),
  /// 그 밖에 종료 코드가 0 이 아니거나(경고도 1) 출력을 읽지 못하면 `.zipUnreadable`.
  private func list(_ source: URL) async throws(AppBundleError) -> ZipListing {
    let result = try await self.run(ZipCommand.zipinfo, ZipCommand.listArguments(source: source))
    let listing = ZipListing.parse(String(bytes: result.stdout, encoding: .utf8) ?? "")
    if listing?.declaredCount == 0 {
      throw .zipWithoutApp
    }
    guard result.exitCode == 0, let listing else {
      throw .zipUnreadable
    }
    try ZipListingCheck.check(listing)
    return listing
  }

  /// ditto 로 푼다. 종료 코드가 0 이면 stderr 는 보지 않는다 (숨긴 항목 등은 푼 뒤 검사가 본다).
  /// 0 이 아니고 stderr 에 `No space left on device` 가 있으면 `.insufficientDiskSpace`, 아니면 `.zipUnreadable`.
  private func extract(_ source: URL, into contents: URL) async throws(AppBundleError) {
    let result = try await self.run(ZipCommand.ditto, ZipCommand.extractArguments(source: source, contents: contents))
    guard result.exitCode != 0 else {
      return
    }
    let stderr = String(data: result.stderr, encoding: .utf8) ?? String(data: result.stderr, encoding: .isoLatin1) ?? ""
    throw stderr.contains("No space left on device") ? .insufficientDiskSpace : .zipUnreadable
  }

  /// 명령을 시작하지 못하면 `.extractionUnavailable`.
  private func run(_ executable: URL, _ arguments: [String]) async throws(AppBundleError) -> CommandResult {
    do {
      return try await self.command.run(executable, arguments, environment: ZipCommand.environment)
    } catch {
      throw .extractionUnavailable
    }
  }

  /// 첫 실패에서 멈춘다: 파일 URL → 존재 → 확장자·폴더 → Mac 앱 → Info.plist → 실행 파일 헤더.
  /// 심볼릭 링크를 푼 실제 경로로 모든 검사를 하고 그 경로를 `location` 에 담는다. 파일 읽기는 동기 I/O 라 메인 밖에서 한다.
  @concurrent
  public func inspect(_ url: URL) async throws(AppBundleError) -> AppBundleInfo {
    guard url.isFileURL else {
      throw .notLocalFile
    }
    let app = url.resolvingSymlinksInPath().standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: app.path(percentEncoded: false), isDirectory: &isDirectory) else {
      throw .fileNotFound
    }
    let pathExtension = app.pathExtension.lowercased()
    if pathExtension == "ipa" {
      throw .ipaFile
    }
    guard pathExtension == "app", isDirectory.boolValue else {
      throw .notAppBundle
    }
    let infoPlist = app.appending(path: "Info.plist", directoryHint: .notDirectory)
    let macInfoPlist = app.appending(path: "Contents/Info.plist", directoryHint: .notDirectory)
    if !Self.exists(infoPlist), Self.exists(macInfoPlist) {
      throw .macOSApp
    }
    let fields = try InfoPlistReader.fields(from: Self.readWholeRegularFile(infoPlist, limit: Self.infoPlistSizeLimit))
    let executable = app.appending(path: fields.executableName, directoryHint: .notDirectory)
    let header = try Self.readRegularFilePrefix(executable, count: Self.executableHeaderSize)
    guard let architectures = MachOArchitectureReader.architectures(fromHeader: header) else {
      throw .invalidBundle
    }
    return AppBundleInfo(
      bundleID: fields.bundleID,
      displayName: fields.displayName ?? app.deletingPathExtension().lastPathComponent,
      version: fields.version,
      build: fields.build,
      platforms: fields.platforms,
      architectures: architectures,
      minimumOSVersion: fields.minimumOSVersion,
      location: app
    )
  }

  /// 심볼릭 링크를 따라간 경로에 무엇이든 있는지.
  private static func exists(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
  }

  /// 링크를 따라간 일반 파일 전체. 일반 파일이 아니거나(FIFO·장치 파일에서 멈추지 않게) `limit` 을 넘거나 읽지 못하면 `.invalidBundle`.
  private static func readWholeRegularFile(_ url: URL, limit: Int) throws(AppBundleError) -> Data {
    let data = try Self.readRegularFilePrefix(url, count: limit + 1)
    guard data.count <= limit else {
      throw .invalidBundle
    }
    return data
  }

  /// 링크를 따라간 일반 파일의 앞 `count` 바이트까지. 일반 파일이 아니거나 읽지 못하면 `.invalidBundle`.
  private static func readRegularFilePrefix(_ url: URL, count: Int) throws(AppBundleError) -> Data {
    let resolved = url.resolvingSymlinksInPath()
    guard
      let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path(percentEncoded: false)),
      attributes[.type] as? FileAttributeType == .typeRegular
    else {
      throw .invalidBundle
    }
    do {
      let handle = try FileHandle(forReadingFrom: resolved)
      defer { try? handle.close() }
      return try handle.read(upToCount: count) ?? Data()
    } catch {
      throw .invalidBundle
    }
  }
}
