import Foundation
import WorkspaceInterface

/// 로그 내보내기: 클립보드 쓰기와 사용자가 저장 패널에서 고른 파일 쓰기.
public extension WorkspaceClientImpl {
  /// `NSPasteboard` 는 스레드 안전이 문서화되어 있지 않아 메인에서 쓴다 (메인 밖에서도 됐지만(측정) 기대지 않는다).
  func copyToClipboard(_ text: String) async throws(WorkspaceExportError) {
    let copy = self.copy
    let succeeded = await MainActor.run { copy(text) }
    guard succeeded else {
      throw .clipboardUnavailable
    }
  }

  /// `Data.write(options: .atomic)`: 같은 폴더의 임시 파일에 쓴 뒤 바꿔 넣는다. 33.7 MB 14.7ms (측정), 변환·쓰기는 메인 밖.
  /// 읽기 전용(444) 파일도 폴더에 쓸 수 있으면 바꿔 넣는다 (측정, 덮어쓰기는 패널이 확인했다).
  @concurrent
  func writeTextFile(_ text: String, to file: URL) async throws(WorkspaceExportError) {
    guard file.isFileURL else {
      throw .writeFailed
    }
    do {
      try Data(text.utf8).write(to: file, options: .atomic)
    } catch {
      throw Self.exportError(error)
    }
  }

  /// 쓰기 오류를 화면 문구 단위로 나눈다. CocoaError 코드를 먼저 보고, 맞는 것이 없으면 `NSUnderlyingErrorKey` 의 POSIX 코드를 본다.
  /// 측정 (macOS 27.2, `Data.write(.atomic)`): 권한 없는 폴더 513/EACCES 13, 디스크 가득 참 640/ENOSPC 28,
  /// 읽기 전용 볼륨 642/EROFS 30, 상위 폴더 없음 4/ENOENT 2, 그 이름이 폴더 512/EISDIR 21.
  internal static func exportError(_ error: any Error) -> WorkspaceExportError {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain, let mapped = Self.cocoaExportError(nsError.code) {
      return mapped
    }
    return Self.posixCode(nsError).flatMap(Self.posixExportError) ?? .writeFailed
  }

  /// 뜻이 분명한 CocoaError 코드만. 일반 코드(512 `fileWriteUnknown` 등)는 nil 이라 밑 POSIX 코드로 넘어간다.
  private static func cocoaExportError(_ code: Int) -> WorkspaceExportError? {
    switch CocoaError.Code(rawValue: code) {
    case .fileWriteNoPermission: .noPermission
    case .fileWriteOutOfSpace: .diskFull
    case .fileWriteVolumeReadOnly: .readOnlyVolume
    case .fileNoSuchFile: .folderNotFound
    default: nil
    }
  }

  private static func posixExportError(_ code: Int32) -> WorkspaceExportError? {
    switch code {
    case EACCES, EPERM: .noPermission
    case ENOSPC, EDQUOT: .diskFull
    case EROFS: .readOnlyVolume
    case ENOENT: .folderNotFound
    default: nil
    }
  }

  /// 오류 자체가 POSIX 도메인이면 그 코드, 아니면 `NSUnderlyingErrorKey` 의 POSIX 코드.
  private static func posixCode(_ error: NSError) -> Int32? {
    if error.domain == NSPOSIXErrorDomain {
      return Int32(error.code)
    }
    guard
      let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError,
      underlying.domain == NSPOSIXErrorDomain
    else {
      return nil
    }
    return Int32(underlying.code)
  }
}
