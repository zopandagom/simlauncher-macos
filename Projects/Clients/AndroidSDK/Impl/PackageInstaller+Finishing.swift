import AndroidSDKInterface
import Core
import Foundation

/// 마무리 단계 도우미: 맨 위 폴더에 package.xml 만들기, 최종 경로 계산, `RENAME_EXCL` 로 옮기기와 그 실패 매핑.
extension PackageInstaller {
  static func destination(of package: AndroidSelectedPackage, rootReal: String) -> URL {
    var destination = URL(filePath: rootReal, directoryHint: .isDirectory)
    for part in package.path.components {
      destination = destination.appending(path: part, directoryHint: .isDirectory)
    }
    return destination
  }

  /// 맨 위 폴더에 package.xml 을 새로 만든다 (`open(O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC, 0o644)`, 끝까지 write,
  /// close). 이미 무엇이든 있으면(`EEXIST`: zip 이 담은 파일·링크) 건드리지 않고 성공으로 본다. 성공이면 nil, 실패면 errno.
  /// 실패 뒤 반쯤 쓴 파일은 지우지 않는다 (스테이징째 지워진다).
  static func writeLocalPackageXML(_ data: Data, into top: URL) -> Int32? {
    let path = top.appending(path: "package.xml", directoryHint: .notDirectory).path(percentEncoded: false)
    let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
    if descriptor < 0 {
      let code = errno
      return code == EEXIST ? nil : code
    }
    var failure: Int32?
    data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
      var offset = 0
      while offset < buffer.count, let base = buffer.baseAddress {
        let written = write(descriptor, base + offset, buffer.count - offset)
        if written < 0 {
          if errno == EINTR {
            continue
          }
          failure = errno
          return
        }
        offset += written
      }
    }
    if close(descriptor) != 0, failure == nil {
      failure = errno
    }
    return failure
  }

  /// package.xml 만들기 실패. `ENOSPC`·`EDQUOT` → `.insufficientDiskSpace` (unzip 종료 코드 50 과 같은 값),
  /// 그 밖(`EACCES`·`EPERM`·`EROFS`·`EIO` 등) → `.sdkFolderUnavailable` (스테이징 준비 실패와 같다).
  static func packageXMLFailure(
    errno code: Int32,
    component: AndroidSDKComponent,
    required: Int64,
    available: Int64?
  ) -> AndroidSDKInstallError {
    switch code {
    case ENOSPC, EDQUOT: .insufficientDiskSpace(component, required: required, available: available)
    default: .sdkFolderUnavailable
    }
  }

  /// 최종 경로의 부모(0o755, 중간 폴더 포함)를 만들고 `RENAME_EXCL` 로 옮긴다 (덮어쓰지 않는다).
  static func move(
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
}
