import Foundation
import WorkspaceInterface

/// 스크린샷·녹화 저장 폴더(사진 폴더·동영상 폴더) 실패 문구. iOS 기기 목록(Launcher)과 같은 키·값이다 (`LauncherTextSyncTests`).
extension AndroidDevicesText {
  /// 스크린샷 저장 폴더(사진 폴더) 문구.
  static func screenshotMessage(for error: WorkspaceError) -> String {
    switch error {
    case .folderUnavailable:
      String(
        localized: """
        사진 폴더 안에 SimLauncher 폴더를 만들거나 그 안에 파일을 쓸 수 없습니다. \
        Finder 에서 사진 폴더에 SimLauncher 라는 이름의 파일이 있지 않은지, 디스크 공간이 남아 있는지 확인한 뒤 다시 시도하세요.
        """,
        bundle: .module
      )
    case .fileNameUnavailable:
      String(
        localized: """
        같은 이름의 스크린샷이 너무 많아 새 파일 이름을 정하지 못했습니다. \
        사진 폴더의 SimLauncher 폴더에서 이전 스크린샷을 다른 곳으로 옮긴 뒤 다시 시도하세요.
        """,
        bundle: .module
      )
    case .fileNotFound:
      String(
        localized: """
        저장한 스크린샷 파일을 찾지 못했습니다. 파일이 옮겨지거나 지워졌을 수 있습니다. \
        Finder 에서 사진 폴더의 SimLauncher 폴더를 열어 확인하세요.
        """,
        bundle: .module
      )
    }
  }

  /// 녹화 저장 폴더(동영상 폴더) 문구. 스크린샷과 같은 원인이고 폴더·파일 이름만 다르다.
  static func recordingMessage(for error: WorkspaceError) -> String {
    switch error {
    case .folderUnavailable:
      String(
        localized: """
        동영상 폴더 안에 SimLauncher 폴더를 만들거나 그 안에 파일을 쓸 수 없습니다. \
        Finder 에서 동영상 폴더에 SimLauncher 라는 이름의 파일이 있지 않은지, 디스크 공간이 남아 있는지 확인한 뒤 다시 시도하세요.
        """,
        bundle: .module
      )
    case .fileNameUnavailable:
      String(
        localized: """
        같은 이름의 녹화 파일이 너무 많아 새 파일 이름을 정하지 못했습니다. \
        동영상 폴더의 SimLauncher 폴더에서 이전 녹화 파일을 다른 곳으로 옮긴 뒤 다시 시도하세요.
        """,
        bundle: .module
      )
    case .fileNotFound:
      String(
        localized: """
        저장한 녹화 파일을 찾지 못했습니다. 파일이 옮겨지거나 지워졌을 수 있습니다. \
        Finder 에서 동영상 폴더의 SimLauncher 폴더를 열어 확인하세요.
        """,
        bundle: .module
      )
    }
  }
}
