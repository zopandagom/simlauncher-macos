import AndroidEmulatorInterface
import Core
import Foundation

/// 지금 SDK 위치의 emulator·adb 실행 파일과 설치된 시스템 이미지 (파일만 읽는다).
struct SDKTools: Sendable {
  let root: URL
  /// `<SDK>/emulator/emulator`.
  let emulator: URL
  /// `<SDK>/platform-tools/adb`.
  let adb: URL

  static let systemImageFileName = "system.img"

  /// 위치가 쓸 수 없거나 두 실행 파일 중 하나라도 실행할 수 있는 일반 파일(링크는 따라간다)이 아니면 `.sdkUnavailable`.
  static func resolve(_ choice: AndroidSDKRootChoice) throws(AndroidEmulatorError) -> SDKTools {
    guard case let .root(root) = choice else {
      throw .sdkUnavailable
    }
    let emulator = root.folder(for: .emulator).appending(path: "emulator", directoryHint: .notDirectory)
    let adb = root.folder(for: .platformTools).appending(path: "adb", directoryHint: .notDirectory)
    guard FileFacts.isExecutableFile(emulator), FileFacts.isExecutableFile(adb) else {
      throw .sdkUnavailable
    }
    return SDKTools(root: root.url, emulator: emulator, adb: adb)
  }

  /// `system-images/<api>/<tag>/<abi>/system.img` 가 일반 파일인 이미지. 읽지 못한 폴더는 건너뛴다.
  /// 구성 요소 검사는 `AndroidSystemImageRef` 가 한다.
  func installedImages() -> [AndroidSystemImageRef] {
    let base = self.root.appending(path: AndroidSDKComponent.systemImage.folderName, directoryHint: .isDirectory)
    var images: [AndroidSystemImageRef] = []
    for api in FileFacts.childNames(base) {
      let apiURL = base.appending(path: api, directoryHint: .isDirectory)
      for tag in FileFacts.childNames(apiURL) {
        let tagURL = apiURL.appending(path: tag, directoryHint: .isDirectory)
        for abi in FileFacts.childNames(tagURL) {
          if let image = AndroidSystemImageRef(apiFolder: api, tag: tag, abi: abi), self.isInstalled(image) {
            images.append(image)
          }
        }
      }
    }
    return images
  }

  /// `<SDK>/system-images/<api>/<tag>/<abi>/system.img` 가 일반 파일이다 (링크는 따라간다).
  func isInstalled(_ image: AndroidSystemImageRef) -> Bool {
    let url = self.imageFolder(image).appending(path: Self.systemImageFileName, directoryHint: .notDirectory)
    return FileFacts.isRegularFile(url)
  }

  /// 접히는 프로필의 `Fold.requiredImageFiles` 가 이미지 폴더 아래 모두 일반 파일인 이미지 (링크는 따라간다).
  /// 읽지 못하면 없는 것으로 본다. 접히는 프로필이 하나라 집합 하나로 충분하다 (둘 이상이 되면 프로필별 집합이 필요하다).
  func foldableImages(_ images: [AndroidSystemImageRef]) -> Set<AndroidSystemImageRef> {
    let files = AndroidDeviceProfile.all.compactMap(\.fold).flatMap(\.requiredImageFiles)
    return Set(images.filter { image in
      let folder = self.imageFolder(image)
      return files.allSatisfy { FileFacts.isRegularFile(folder.appending(path: $0, directoryHint: .notDirectory)) }
    })
  }

  /// `<SDK>/system-images/<api>/<tag>/<abi>/`.
  private func imageFolder(_ image: AndroidSystemImageRef) -> URL {
    self.root
      .appending(path: AndroidSDKComponent.systemImage.folderName, directoryHint: .isDirectory)
      .appending(path: image.apiFolder, directoryHint: .isDirectory)
      .appending(path: image.tag, directoryHint: .isDirectory)
      .appending(path: image.abi, directoryHint: .isDirectory)
  }
}

/// 파일 종류 판정 도우미. 링크를 따라가는지는 함수마다 적는다.
enum FileFacts {
  enum Kind: Equatable {
    case absent, directory, file, link, other
  }

  /// 링크를 따라가지 않은 종류. 끝 `/` 는 뗀다 (붙어 있으면 `lstat` 이 마지막 링크를 따라간다).
  /// 없음(ENOENT·ENOTDIR)은 `.absent`, 그 밖의 실패는 `.other`.
  static func kindWithoutFollowing(_ url: URL) -> Kind {
    var info = stat()
    guard lstat(self.path(url), &info) == 0 else {
      return errno == ENOENT || errno == ENOTDIR ? .absent : .other
    }
    switch info.st_mode & S_IFMT {
    case S_IFDIR: return .directory
    case S_IFREG: return .file
    case S_IFLNK: return .link
    default: return .other
    }
  }

  /// 링크를 따라간 디렉터리다.
  static func isDirectory(_ url: URL) -> Bool {
    var info = stat()
    return stat(self.path(url), &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
  }

  /// 링크를 따라간 일반 파일이다.
  static func isRegularFile(_ url: URL) -> Bool {
    var info = stat()
    return stat(self.path(url), &info) == 0 && info.st_mode & S_IFMT == S_IFREG
  }

  /// 링크를 따라간 일반 파일이고 `access(X_OK)` 다.
  static func isExecutableFile(_ url: URL) -> Bool {
    self.isRegularFile(url) && access(self.path(url), X_OK) == 0
  }

  /// 폴더 안 이름 (정렬). 읽지 못하면 빈 배열.
  static func childNames(_ url: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: self.path(url))) ?? []).sorted()
  }

  /// 최대 `limit` 바이트까지 읽는다. 없거나 읽지 못하거나 `limit` 을 넘으면 nil.
  static func read(_ url: URL, limit: Int) -> Data? {
    guard let handle = try? FileHandle(forReadingFrom: url) else {
      return nil
    }
    defer { try? handle.close() }
    do {
      // 빈 파일이면 nil 이 온다.
      let data = try handle.read(upToCount: limit + 1) ?? Data()
      return data.count > limit ? nil : data
    } catch {
      return nil
    }
  }

  /// 끝 `/` 를 뗀 경로 (루트 `/` 는 그대로).
  static func path(_ url: URL) -> String {
    var path = url.path(percentEncoded: false)
    while path.count > 1, path.hasSuffix("/") {
      path.removeLast()
    }
    return path
  }
}
