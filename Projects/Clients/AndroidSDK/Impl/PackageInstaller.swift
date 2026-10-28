import AndroidSDKInterface
import CommandInterface
import Core
import DownloadInterface
import Foundation

/// 패키지 하나의 설치 단계. 첫 실패에서 멈추고, 실패·취소 때는 스테이징과 (아직이면) 받은 폴더를 지운 뒤 던진다.
/// 받기 → 크기·체크섬 확인 → SDK 루트 준비 → 스테이징(`<SDK>/.simlauncher-staging-<UUID>/` 0o700, `source.zip` 링크, `contents/`)
/// → zipinfo 목록 검사·SDK 볼륨 여유 → unzip → 받은 폴더 지우기 → 푼 트리 검사 → (취소 확인) → 마무리:
/// 최종 경로의 부모 만들기 → `renamex_np(RENAME_EXCL)` → 스테이징 지우기. 마무리는 취소를 받지 않는다.
struct PackageInstaller: Sendable {
  let download: any DownloadClient
  let command: any CommandClient
  let staging: StagingFolders
  let availableCapacity: @Sendable (URL) -> Int64?

  func install(
    _ package: AndroidSelectedPackage,
    index: Int,
    root: AndroidSDKRoot,
    reporter: InstallProgressReporter
  ) async throws(AndroidSDKInstallError) {
    let component = package.component
    let file = try await self.fetch(package, index: index, reporter: reporter)
    reporter.downloaded(package)
    var downloaded: DownloadedFile? = file
    var stagingFolder: (folder: URL, root: String)?
    do throws(AndroidSDKInstallError) {
      try await Self.verify(file, package, index: index, reporter: reporter)
      await reporter.phase(.extracting, package, index: index)
      let rootReal = try Self.prepareRoot(root)
      let folder = self.newStagingFolder(in: rootReal)
      stagingFolder = (folder, rootReal)
      let contents = try await self.extractStaged(file.file, folder: folder, rootReal: rootReal, component: component)
      await self.download.removeDownloaded(file)
      downloaded = nil
      let top: URL
      do throws(PackageArchiveFailure) {
        top = try PackageTreeCheck.check(contents: contents)
      } catch {
        throw Self.error(error, component)
      }
      guard !Task.isCancelled else {
        throw .cancelled
      }
      await reporter.phase(.finishing, package, index: index)
      try Self.move(top, to: Self.destination(of: package, rootReal: rootReal), component: component)
      self.staging.remove(folder, root: rootReal)
    } catch {
      if let downloaded {
        await self.download.removeDownloaded(downloaded)
      }
      if let stagingFolder {
        self.staging.remove(stagingFolder.folder, root: stagingFolder.root)
      }
      throw error
    }
  }

  /// 받기. 취소 → `.cancelled`, 그 밖 → `.download`.
  private func fetch(
    _ package: AndroidSelectedPackage,
    index: Int,
    reporter: InstallProgressReporter
  ) async throws(AndroidSDKInstallError) -> DownloadedFile {
    await reporter.downloading(package, index: index, received: 0)
    do throws(DownloadError) {
      return try await self.download.download(package.url) { progress in
        await reporter.downloading(package, index: index, received: progress.receivedBytes)
      }
    } catch {
      guard let failure = DownloadFailureMapping.failure(error) else {
        throw .cancelled
      }
      throw .download(package.component, failure)
    }
  }

  /// 크기·체크섬 확인 뒤 취소 확인.
  private static func verify(
    _ file: DownloadedFile,
    _ package: AndroidSelectedPackage,
    index: Int,
    reporter: InstallProgressReporter
  ) async throws(AndroidSDKInstallError) {
    await reporter.phase(.verifying, package, index: index)
    switch await ArchiveChecksumVerifier.verify(
      file.file,
      size: package.archive.size,
      checksum: package.archive.checksum
    ) {
    case .match: break
    case .mismatch: throw .checksumMismatch(package.component)
    case .cancelled: throw .cancelled
    }
    guard !Task.isCancelled else {
      throw .cancelled
    }
  }

  /// 새 스테이징 이름을 등록하고 그 폴더 주소를 돌려준다 (폴더는 아직 만들지 않는다).
  private func newStagingFolder(in rootReal: String) -> URL {
    let name = StagingFolders.newName()
    self.staging.register(name)
    return URL(filePath: rootReal, directoryHint: .isDirectory).appending(
      path: name,
      directoryHint: .isDirectory
    )
  }

  /// 스테이징 준비 → zipinfo 목록 검사 → SDK 볼륨 여유 → unzip. 푼 `contents/` 를 돌려준다.
  private func extractStaged(
    _ file: URL,
    folder: URL,
    rootReal: String,
    component: AndroidSDKComponent
  ) async throws(AndroidSDKInstallError) -> URL {
    let source = folder.appending(path: "source.zip", directoryHint: .notDirectory)
    let contents = folder.appending(path: "contents", directoryHint: .isDirectory)
    try Self.prepareStaging(folder, source: source, contents: contents, file: file)
    let declared = try await self.list(source, component: component)
    let volume = URL(filePath: rootReal, directoryHint: .isDirectory)
    if let available = self.availableCapacity(volume), declared > available {
      throw .insufficientDiskSpace(component, required: declared, available: available)
    }
    try await self.extract(source, into: contents, component: component, declared: declared, volume: volume)
    return contents
  }

  private static func destination(of package: AndroidSelectedPackage, rootReal: String) -> URL {
    var destination = URL(filePath: rootReal, directoryHint: .isDirectory)
    for part in package.path.components {
      destination = destination.appending(path: part, directoryHint: .isDirectory)
    }
    return destination
  }

  /// SDK 루트의 실제 경로. 없으면 기본 위치만 만든다(0o755, 중간 폴더 포함). 고른 폴더가 없거나 파일·깨진 링크면
  /// `.sdkFolderUnavailable`.
  static func prepareRoot(_ root: AndroidSDKRoot) throws(AndroidSDKInstallError) -> String {
    let path = root.url.path(percentEncoded: false)
    switch SDKFiles.rootKind(path) {
    case .directory:
      break
    case .absent where root.isDefault:
      do {
        try FileManager.default.createDirectory(
          at: root.url,
          withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o755]
        )
      } catch {
        throw .sdkFolderUnavailable
      }
    default:
      throw .sdkFolderUnavailable
    }
    guard let real = RealPath.of(path) else {
      throw .sdkFolderUnavailable
    }
    return real
  }

  /// 스테이징 폴더(0o700, 중간 폴더는 만들지 않음) → `contents/` → `source.zip` 링크(받은 파일의 실제 경로).
  private static func prepareStaging(
    _ folder: URL,
    source: URL,
    contents: URL,
    file: URL
  ) throws(AndroidSDKInstallError) {
    do {
      try FileManager.default.createDirectory(
        at: folder,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
      try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: false)
      try FileManager.default.createSymbolicLink(
        atPath: source.path(percentEncoded: false),
        withDestinationPath: RealPath.of(file) ?? file.path(percentEncoded: false)
      )
    } catch {
      throw .sdkFolderUnavailable
    }
  }

  /// zipinfo 목록 → 풀기 전 검사. 선언 크기 합을 돌려준다. 시작 실패·0 이 아닌 종료 코드·출력을 읽지 못함 → `.archiveUnreadable`.
  private func list(_ source: URL, component: AndroidSDKComponent) async throws(AndroidSDKInstallError) -> Int64 {
    let result: CommandResult
    do {
      result = try await self.command.run(
        PackageZipCommand.zipinfo,
        PackageZipCommand.listArguments(source: source),
        environment: PackageZipCommand.environment
      )
    } catch {
      throw .archiveUnreadable(component)
    }
    guard
      result.exitCode == 0,
      let listing = PackageZipListing.parse(String(bytes: result.stdout, encoding: .utf8) ?? "")
    else {
      throw .archiveUnreadable(component)
    }
    do throws(PackageArchiveFailure) {
      try PackageZipListingCheck.check(listing)
    } catch {
      throw Self.error(error, component)
    }
    return listing.declaredTotalBytes
  }

  /// unzip (`runCancellable`, 시간 제한 없음, Task 취소가 멈춤). 0 → 성공, 50 → 저장 공간 부족, Task 취소로 멈춤 → `.cancelled`,
  /// 그 밖(1 경고 포함)·시작 실패 → `.archiveUnreadable`. 0 이 아니면 stderr 는 보지 않는다 (경로가 들어 있다).
  private func extract(
    _ source: URL,
    into contents: URL,
    component: AndroidSDKComponent,
    declared: Int64,
    volume: URL
  ) async throws(AndroidSDKInstallError) {
    let result: CommandResult
    do throws(CommandError) {
      result = try await self.command.runCancellable(
        PackageZipCommand.unzip,
        PackageZipCommand.extractArguments(source: source, contents: contents),
        environment: PackageZipCommand.environment,
        timeout: nil,
        onOutput: { _ in }
      )
    } catch {
      throw error == .cancelled ? .cancelled : .archiveUnreadable(component)
    }
    switch result.exitCode {
    case 0:
      return
    case PackageZipCommand.diskFullExitCode:
      throw .insufficientDiskSpace(component, required: declared, available: self.availableCapacity(volume))
    default:
      throw .archiveUnreadable(component)
    }
  }

  /// 최종 경로의 부모(0o755, 중간 폴더 포함)를 만들고 `RENAME_EXCL` 로 옮긴다 (덮어쓰지 않는다).
  private static func move(
    _ top: URL,
    to destination: URL,
    component: AndroidSDKComponent
  ) throws(AndroidSDKInstallError) {
    do {
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o755]
      )
    } catch {
      throw .sdkFolderUnavailable
    }
    let status = renamex_np(
      SDKFiles.withoutTrailingSlash(top.path(percentEncoded: false)),
      SDKFiles.withoutTrailingSlash(destination.path(percentEncoded: false)),
      UInt32(RENAME_EXCL)
    )
    if status != 0 {
      throw self.renameFailure(errno: errno, component: component)
    }
  }

  /// `EEXIST` → `.destinationExists`. 그 밖(`ENOTSUP`: RENAME_EXCL 을 지원하지 않는 볼륨 등) → `.sdkFolderUnavailable`.
  /// 대체 `rename(2)` 는 쓰지 않는다 (대상이 빈 폴더면 대체해 "덮어쓰지 않음" 이 깨진다).
  static func renameFailure(errno code: Int32, component: AndroidSDKComponent) -> AndroidSDKInstallError {
    code == EEXIST ? .destinationExists(component) : .sdkFolderUnavailable
  }

  private static func error(
    _ failure: PackageArchiveFailure,
    _ component: AndroidSDKComponent
  ) -> AndroidSDKInstallError {
    switch failure {
    case .unreadable: .archiveUnreadable(component)
    case .unsafe: .archiveUnsafe(component)
    }
  }
}
