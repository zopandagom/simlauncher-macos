import Foundation
import WorkspaceInterface

/// 로그 창 아래 줄 "복사"·"저장…" 문구 (버튼·도움말·결과·실패). 내보낼 글의 머리말 문구는 `LogExportText` 에 있다.
extension DeviceLogText {
  static var copyButton: String {
    String(localized: "복사", bundle: .module)
  }

  static var saveExportButton: String {
    String(localized: "저장…", bundle: .module)
  }

  static var copied: String {
    String(localized: "복사됨", bundle: .module)
  }

  /// 개인정보 안내를 겸한다 (확인창 없음).
  static var copyHelp: String {
    String(
      localized: """
      화면에 보이는 줄을 머리말(앱·기기·필터 정보)과 함께 클립보드에 복사합니다. \
      앱이 찍은 개인정보나 토큰이 들어 있을 수 있으니 보내기 전에 확인하세요.
      """,
      bundle: .module
    )
  }

  /// 개인정보 안내를 겸한다 (확인창 없음).
  static var saveExportHelp: String {
    String(
      localized: """
      화면에 보이는 줄을 머리말(앱·기기·필터 정보)과 함께 텍스트 파일로 저장합니다. \
      앱이 찍은 개인정보나 토큰이 들어 있을 수 있으니 보내기 전에 확인하세요.
      """,
      bundle: .module
    )
  }

  /// 저장 성공 줄. 경로는 보이지 않고 파일 이름만.
  static func saved(fileName: String) -> String {
    String(localized: "저장했습니다: \(fileName)", bundle: .module)
  }

  static var revealInFinder: String {
    String(localized: "Finder 에서 보기", bundle: .module)
  }

  /// 내보내기 실패 문구. 복사 실패는 모두 클립보드 문구이고, 저장 실패의 `.clipboardUnavailable` 은 오지 않지만 일반 문구다.
  static func exportFailed(_ failure: LogExportFailure) -> String {
    switch failure {
    case .copy:
      String(localized: "클립보드에 복사하지 못했습니다. 다시 시도하세요.", bundle: .module)
    case let .save(error):
      self.saveFailed(error)
    case .revealedFileMissing:
      String(localized: "저장한 파일을 찾지 못했습니다. 옮겨졌거나 지워졌을 수 있습니다.", bundle: .module)
    }
  }

  private static func saveFailed(_ error: WorkspaceExportError) -> String {
    switch error {
    case .noPermission:
      String(localized: "이 위치에 쓸 권한이 없어 저장하지 못했습니다. 다른 폴더를 고르세요.", bundle: .module)
    case .diskFull:
      String(localized: "디스크 공간이 부족해 저장하지 못했습니다. 공간을 비우거나 다른 위치를 고르세요.", bundle: .module)
    case .readOnlyVolume:
      String(localized: "읽기 전용 디스크라 저장하지 못했습니다. 다른 위치를 고르세요.", bundle: .module)
    case .folderNotFound:
      String(localized: "고른 폴더를 찾지 못해 저장하지 못했습니다. 다시 저장해 보세요.", bundle: .module)
    case .clipboardUnavailable, .writeFailed:
      String(localized: "저장하지 못했습니다. 다른 이름이나 위치로 다시 저장해 보세요.", bundle: .module)
    }
  }
}
