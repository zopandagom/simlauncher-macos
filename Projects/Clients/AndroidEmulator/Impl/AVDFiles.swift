import AndroidEmulatorInterface
import Core
import Foundation

/// 만들기·삭제·초기화의 파일 작업. 링크는 따라가지 않는다 (지우는 것은 링크 자체).
enum AVDFiles {
  /// 만들 기기의 값 (이름·시스템 이미지·프로필·호스트).
  struct NewDevice {
    let displayName: String
    let image: AndroidSystemImageRef
    let profile: AndroidDeviceProfile
    let host: AndroidHostArchitecture
  }

  /// 이름이 겹쳐(EEXIST) 다음 번호로 다시 시도하는 최대 횟수.
  static let maxCreateAttempts = 3

  /// `~/.android`(0750)·`~/.android/avd`(0755)가 없으면 만든다 (실측 권한과 같게). 디렉터리가 아니거나 만들지 못하면
  /// `.avdFolderUnavailable`. 링크면 따라간 디렉터리를 쓴다.
  static func prepareFolders(home: URL) throws(AndroidEmulatorError) {
    for (url, mode) in [(AVDFolderScan.androidFolder(home: home), 0o750), (
      AVDFolderScan.avdFolder(home: home),
      0o755
    )] {
      if FileFacts.kindWithoutFollowing(url) == .absent, mkdir(FileFacts.path(url), mode_t(mode)) != 0,
         errno != EEXIST
      {
        throw .avdFolderUnavailable
      }
      guard FileFacts.isDirectory(url) else {
        throw .avdFolderUnavailable
      }
    }
  }

  /// `<이름>.avd` 폴더(mkdir) → `config.ini`(O_EXCL) → `<이름>.ini`(O_EXCL) 순서로 만든다. ini 를 마지막에 써야 목록에
  /// 반쯤 만든 기기가 보이지 않는다. 폴더나 ini 가 이미 있으면(EEXIST) 이번에 만든 것을 지우고 그 이름을 `taken` 에 더해 다음 번호로
  /// 다시 시도하고, `maxCreateAttempts` 번 모두 겹치거나 `AndroidAVDName.make` 가 nil 이면 `.nameUnavailable`.
  /// 그 밖의 실패는 만든 것을 지우고 `.avdFolderUnavailable`.
  /// - Parameter displayName: `DeviceName.problem` 이 없는 정규화된 값 (`AVDIniFile.render` 는 줄 바꿈을 막지 않는다).
  static func create(
    home: URL,
    device: NewDevice,
    taken: Set<String>
  ) throws(AndroidEmulatorError) -> AndroidVirtualDevice.ID {
    let displayName = device.displayName
    let image = device.image
    let avdFolder = AVDFolderScan.avdFolder(home: home)
    let config = AndroidAVDConfig.configFile(
      displayName: displayName,
      image: image,
      profile: device.profile,
      host: device.host
    )
    var taken = taken
    for _ in 0 ..< self.maxCreateAttempts {
      guard let name = AndroidAVDName.make(from: displayName, existing: taken) else {
        throw .nameUnavailable
      }
      taken.insert(name)
      let folder = avdFolder.appending(path: name + AVDFolderScan.folderExtension, directoryHint: .isDirectory)
      guard mkdir(FileFacts.path(folder), 0o755) == 0 else {
        if errno == EEXIST {
          continue
        }
        throw .avdFolderUnavailable
      }
      guard self.writeExclusive(config, to: folder.appending(path: AVDFolderScan.configFileName)) == .written else {
        self.removeCreated(folder)
        throw .avdFolderUnavailable
      }
      let id = AndroidVirtualDevice.ID(name)
      let pointer = AndroidAVDConfig.pointerFile(folder: folder, name: id, image: image)
      switch self.writeExclusive(pointer, to: avdFolder.appending(path: name + AVDFolderScan.pointerExtension)) {
      case .written:
        return id
      case .exists:
        self.removeCreated(folder)
      case .failed:
        self.removeCreated(folder)
        throw .avdFolderUnavailable
      }
    }
    throw .nameUnavailable
  }

  /// 기기 폴더 조건: 링크 아닌 실제 디렉터리이고 마지막 구성 요소가 `.avd` 로 끝난다.
  static func isDeviceFolder(_ url: URL) -> Bool {
    FileFacts.kindWithoutFollowing(url) == .directory
      && URL(filePath: FileFacts.path(url)).lastPathComponent.hasSuffix(AVDFolderScan.folderExtension)
  }

  /// 폴더를 먼저, ini 를 나중에 지운다 (폴더 지우기가 도중에 실패하면 ini 가 남아 다시 지울 수 있다).
  /// 폴더가 기기 폴더 조건을 통과하지 못하면 남기고 `.folderKept`, 없으면 ini 만 지운다. 지우지 못하면 `.fileOperationFailed`.
  static func remove(_ entry: AVDEntry) throws(AndroidEmulatorError) -> AndroidDeleteOutcome {
    var outcome = AndroidDeleteOutcome.deleted
    if let folder = entry.folder, FileFacts.kindWithoutFollowing(folder) != .absent {
      if self.isDeviceFolder(folder) {
        do {
          try FileManager.default.removeItem(atPath: FileFacts.path(folder))
        } catch {
          throw .fileOperationFailed
        }
      } else {
        outcome = .folderKept(folder)
      }
    }
    if unlink(FileFacts.path(entry.pointerURL)) != 0, errno != ENOENT {
      throw .fileOperationFailed
    }
    return outcome
  }

  /// `AndroidAVDReset` 의 항목을 지운다 (있는 것만). 중간 구성 요소가 링크이거나 디렉터리가 아니면 그 항목은 건너뛰고,
  /// 마지막 구성 요소가 링크면 링크만 지운다. 하나라도 지우지 못하면 나머지를 마친 뒤 `.fileOperationFailed`.
  /// 기기 폴더 조건은 부르는 쪽이 먼저 확인한다.
  static func reset(folder: URL) throws(AndroidEmulatorError) {
    var failed = false
    for relative in AndroidAVDReset.fileNames + AndroidAVDReset.directoryNames {
      guard let target = self.resetTarget(relative, in: folder) else {
        continue
      }
      switch FileFacts.kindWithoutFollowing(target) {
      case .absent:
        continue
      case .directory:
        do {
          try FileManager.default.removeItem(atPath: FileFacts.path(target))
        } catch {
          failed = true
        }
      case .file, .link, .other:
        if unlink(FileFacts.path(target)) != 0, errno != ENOENT {
          failed = true
        }
      }
    }
    if failed {
      throw .fileOperationFailed
    }
  }

  /// 중간 구성 요소가 모두 링크 아닌 디렉터리일 때만 대상 URL.
  private static func resetTarget(_ relative: String, in folder: URL) -> URL? {
    let components = relative.split(separator: "/").map(String.init)
    var url = folder
    for component in components.dropLast() {
      url = url.appending(path: component, directoryHint: .isDirectory)
      guard FileFacts.kindWithoutFollowing(url) == .directory else {
        return nil
      }
    }
    guard let last = components.last else {
      return nil
    }
    return url.appending(path: last, directoryHint: .notDirectory)
  }

  private enum WriteResult {
    case written, exists, failed
  }

  /// `O_CREAT|O_EXCL` 로 새 파일을 써서 덮어쓰지 않는다. 쓰다 실패하면 그 파일을 지운다.
  private static func writeExclusive(_ data: Data, to url: URL) -> WriteResult {
    let path = FileFacts.path(url)
    let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
    guard descriptor >= 0 else {
      return errno == EEXIST ? .exists : .failed
    }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    do {
      try handle.write(contentsOf: data)
      try handle.close()
      return .written
    } catch {
      try? handle.close()
      unlink(path)
      return .failed
    }
  }

  /// 이번 만들기가 만든 폴더를 지운다 (실패는 무시한다. 남으면 다음 만들기의 이름 집합에 들어가 겹치지 않는다).
  private static func removeCreated(_ folder: URL) {
    try? FileManager.default.removeItem(atPath: FileFacts.path(folder))
  }
}
