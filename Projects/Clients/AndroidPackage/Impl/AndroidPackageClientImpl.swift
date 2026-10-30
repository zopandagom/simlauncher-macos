import AndroidPackageInterface
import CommandInterface
import Core
import Foundation

/// 로컬 .apk 를 zipinfo·`unzip -p`(`CommandClient`)와 파일 끝 읽기로 검사하는 `AndroidPackageClient`.
/// Mac 에 풀지 않고(AndroidManifest.xml 하나만 메모리로) 원본을 고치지 않는다.
public struct AndroidPackageClientImpl: AndroidPackageClient {
  private let command: any CommandClient
  private let temporaryDirectory: URL

  /// `FileManager.default.temporaryDirectory` 에 검사용 임시 폴더를 만든다.
  /// - Parameter command: zipinfo·unzip 실행. App 이 `CommandClientImpl` 을 넘긴다.
  public init(command: any CommandClient) {
    self.init(command: command, temporaryDirectory: FileManager.default.temporaryDirectory)
  }

  /// 테스트용: 임시 폴더 위치를 정한다.
  init(command: any CommandClient, temporaryDirectory: URL) {
    self.command = command
    self.temporaryDirectory = temporaryDirectory
  }

  /// 첫 실패에서 멈춘다: 파일 URL → 실제 경로 → 일반 파일 → 확장자 → 임시 폴더·고정 이름 링크 → zipinfo 목록 검사
  /// → 서명 유무 → `unzip -p` 로 manifest → AXML 해석 → package 형식. 임시 폴더는 성공·실패 모두 지운다.
  /// 파일 읽기는 동기 I/O 라 메인 밖에서 한다.
  @concurrent
  public func inspect(_ url: URL) async throws(AndroidPackageError) -> AndroidPackageInfo {
    guard url.isFileURL else {
      throw .notLocalFile
    }
    guard let path = RealPath.of(url) else {
      throw .fileNotFound
    }
    guard
      let attributes = try? FileManager.default.attributesOfItem(atPath: path),
      attributes[.type] as? FileAttributeType == .typeRegular
    else {
      throw .notAPK
    }
    let location = URL(filePath: path, directoryHint: .notDirectory)
    switch location.pathExtension.lowercased() {
    case "apk": break
    case "aab": throw .appBundle
    case "apks", "xapk", "apkm": throw .splitPackage
    default: throw .notAPK
    }
    guard let folder = InspectionFolder.make(in: self.temporaryDirectory, linkingTo: path) else {
      throw .inspectionUnavailable
    }
    defer { folder.remove() }
    let entries = try await self.list(folder.link)
    if !entries.hasV1Signature, APKSignatureCheck.hasSigningBlock(atPath: path) == false {
      throw .unsigned
    }
    let manifest = try await self.manifest(folder.link)
    guard let packageName = AndroidPackageName(manifest.package) else {
      throw .unreadable
    }
    return AndroidPackageInfo(
      location: location,
      packageName: packageName,
      minSDK: manifest.minSDK,
      nativeABIs: entries.nativeABIs
    )
  }

  /// zipinfo 종료 코드가 0 이 아니거나(잘림·zip 아님은 9) 출력을 읽지 못하면 `.unreadable`, 그 뒤 목록 검사.
  private func list(_ source: URL) async throws(AndroidPackageError) -> APKEntries {
    let result = try await self.run(APKCommand.zipinfo, APKCommand.listArguments(source: source))
    guard
      result.exitCode == 0,
      let listing = APKZipListing.parse(String(bytes: result.stdout, encoding: .utf8) ?? "")
    else {
      throw .unreadable
    }
    return try listing.check().get()
  }

  /// unzip 종료 코드가 0 이 아니거나(항목 없음 11·잘림 9) 상한을 넘거나 AXML 을 해석하지 못하면 `.unreadable`.
  private func manifest(_ source: URL) async throws(AndroidPackageError) -> AXMLManifest {
    let result = try await self.run(APKCommand.unzip, APKCommand.manifestArguments(source: source))
    guard
      result.exitCode == 0,
      result.stdout.count <= AXMLManifestReader.sizeLimit,
      let manifest = AXMLManifestReader.read(result.stdout)
    else {
      throw .unreadable
    }
    return manifest
  }

  /// 명령을 시작하지 못하면 `.inspectionUnavailable`.
  private func run(_ executable: URL, _ arguments: [String]) async throws(AndroidPackageError) -> CommandResult {
    do {
      return try await self.command.run(executable, arguments, environment: APKCommand.environment)
    } catch {
      throw .inspectionUnavailable
    }
  }
}
