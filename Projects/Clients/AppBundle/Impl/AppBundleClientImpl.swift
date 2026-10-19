import AppBundleInterface
import Core
import Foundation

/// 파일 시스템에서 .app 을 읽는 `AppBundleClient`. 파일을 고치지 않고, 일반 파일만 정해진 크기까지 읽는다.
public struct AppBundleClientImpl: AppBundleClient {
  /// Info.plist 를 읽는 상한. 넘으면 `.invalidBundle`.
  static let infoPlistSizeLimit = 1_048_576
  /// 실행 파일에서 읽는 앞부분 크기 (Mach-O·fat 헤더).
  static let executableHeaderSize = 4096

  public let hostArchitecture: CPUArchitecture

  /// 이 Mac 의 아키텍처(`HostArchitecture.current()`)를 쓴다.
  public init() {
    self.init(hostArchitecture: HostArchitecture.current())
  }

  /// 테스트용: 아키텍처를 정한다.
  init(hostArchitecture: CPUArchitecture) {
    self.hostArchitecture = hostArchitecture
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
