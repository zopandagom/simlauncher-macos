import AppKit
import Core
import Foundation
import WorkspaceInterface

/// 사진 폴더의 `SimLauncher` 폴더에 스크린샷 파일을 예약하고, Finder 에서 파일을 선택해 보인다.
/// 사진 폴더는 TCC 보호 폴더가 아니라 권한 팝업이 없다 (측정). 저장 폴더는 누를 때 만들고, 생성자는 파일을 건드리지 않는다.
/// 이름 경쟁은 독점 생성(`Data.write(options: .withoutOverwriting)`)으로 푼다: 목록을 보고 고른 뒤 쓰는 사이의 틈이 없다.
/// `SimLauncher` 가 디렉터리를 가리키는 심볼릭 링크면 따라간다 (사용자의 의도적 설정, 막지 않는다).
public struct WorkspaceClientImpl: WorkspaceClient {
  static let folderName = "SimLauncher"

  private let picturesDirectory: URL?
  private let reveal: @MainActor @Sendable ([URL]) -> Void

  public init() {
    self.init(
      picturesDirectory: FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first,
      reveal: { NSWorkspace.shared.activateFileViewerSelecting($0) }
    )
  }

  /// 테스트용: 사진 폴더(임시 폴더)와 Finder 열기를 바꾼다.
  init(picturesDirectory: URL?, reveal: @escaping @MainActor @Sendable ([URL]) -> Void) {
    self.picturesDirectory = picturesDirectory
    self.reveal = reveal
  }

  public func reserveScreenshotFile(_ name: ScreenshotFileName) async throws(WorkspaceError) -> URL {
    try Self.reserve(in: Self.folder(in: self.picturesDirectory), maxAttempts: ScreenshotFileName.maxAttempts) {
      name.fileName(attempt: $0)
    }
  }

  public func removeReservedFile(_ file: URL) async {
    guard let folder = Self.folder(in: self.picturesDirectory), Self.isDirectChild(file, of: folder) else {
      return
    }
    // 예약한 것은 빈 파일이다. 같은 자리의 폴더는 지우지 않는다 (링크는 링크 자체를 본다).
    if (try? file.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
      return
    }
    try? FileManager.default.removeItem(at: file)
  }

  public func revealInFinder(_ file: URL) async throws(WorkspaceError) {
    guard file.isFileURL, FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) else {
      throw .fileNotFound
    }
    let reveal = self.reveal
    await MainActor.run { reveal([file]) }
  }

  /// 저장 폴더 (링크를 풀지 않은 경로). 사진 폴더를 찾지 못하면 nil.
  private static func folder(in directory: URL?) -> URL? {
    directory?.appending(path: self.folderName, directoryHint: .isDirectory)
  }

  /// `folder` 를 준비하고 `fileName(1...maxAttempts)` 중 처음 독점 생성에 성공한 빈 파일을 돌려준다.
  private static func reserve(
    in folder: URL?,
    maxAttempts: Int,
    fileName: (Int) -> String?
  ) throws(WorkspaceError) -> URL {
    guard let folder else {
      throw .folderUnavailable
    }
    try Self.prepare(folder)
    for attempt in 1 ... maxAttempts {
      guard let fileName = fileName(attempt) else { break }
      // 링크를 풀지 않은 폴더 기준이다: 돌려주는 URL·Finder 경로는 `…/SimLauncher/…` 이고 실제 쓰기는 커널이 링크를 따라간다.
      let file = folder.appending(path: fileName, directoryHint: .notDirectory)
      // Core 규칙상 생기지 않지만, 이름이 저장 폴더 밖을 가리키면 쓰지 않는다.
      guard Self.isDirectChild(file, of: folder) else {
        throw .folderUnavailable
      }
      do {
        try Data().write(to: file, options: .withoutOverwriting)
        return file
      } catch let error as CocoaError where error.code == .fileWriteFileExists {
        // 같은 이름의 파일(대상 없는 심볼릭 링크 포함)이 있다. 링크 대상은 만들지 않는다 (측정).
        continue
      } catch {
        throw .folderUnavailable
      }
    }
    throw .fileNameUnavailable
  }

  /// 없으면 만들고, 링크를 따라간 결과가 디렉터리인지 확인한다.
  /// 그 자리에 파일(516)·대상 없는 링크(512)·파일을 가리키는 링크(516)·권한 없음이면 `.folderUnavailable` (측정).
  /// `isDirectoryKey` 는 링크 자체를 보아 디렉터리를 가리키는 링크에 false 를 주므로 링크를 따라간 값으로 본다.
  private static func prepare(_ folder: URL) throws(WorkspaceError) {
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    } catch {
      throw .folderUnavailable
    }
    let resolved = folder.resolvingSymlinksInPath()
    guard (try? resolved.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
      throw .folderUnavailable
    }
  }

  /// `file` 이 `folder` 바로 안의 이름 한 단계인지. 둘 다 `standardizedFileURL`(`..`·`.` 정리, 링크는 풀지 않는다)로 비교한다.
  /// `resolvingSymlinksInPath()` 는 `/private/tmp` → `/tmp` 처럼 표기가 바뀌어 쓰지 않는다. 예약과 지우기가 같은 기준을 쓴다.
  static func isDirectChild(_ file: URL, of folder: URL) -> Bool {
    guard file.isFileURL else {
      return false
    }
    let standardized = file.standardizedFileURL
    let name = standardized.lastPathComponent
    guard !name.isEmpty, name != ".", name != "..", name != "/" else {
      return false
    }
    let parent = standardized.deletingLastPathComponent().path(percentEncoded: false)
    return parent == folder.standardizedFileURL.path(percentEncoded: false)
  }
}
