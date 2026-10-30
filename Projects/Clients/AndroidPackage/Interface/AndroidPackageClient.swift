import Core
import Foundation

/// 로컬 .apk 를 읽는 Client. Mac 에 풀지 않고(AndroidManifest.xml 하나만 메모리로) 원본을 고치지 않는다.
public protocol AndroidPackageClient: Sendable {
  /// 검사한다 (설치 판정은 하지 않는다, Core `installProblem`). 메인 밖에서 돈다. 첫 실패에서 멈춘다:
  /// 파일 URL → 실제 경로·일반 파일 → 확장자 → 임시 폴더·고정 이름 링크 → zipinfo 목록 검사 → 서명 유무
  /// → AndroidManifest.xml(unzip -p) → AXML 해석 → (끝나면 늘) 임시 폴더 지우기.
  func inspect(_ url: URL) async throws(AndroidPackageError) -> AndroidPackageInfo
}
