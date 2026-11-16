import Core
import Foundation

/// 이 앱 배포 저장소(GitHub)의 최신 정식 릴리스 버전을 묻는다. 네트워크는 Download Client 를 거친다(Impl 이 조합).
/// 받는 주소는 빌드 설정의 배포 저장소로 만든 고정 주소
/// `https://github.com/<저장소>/releases/latest/download/SimLauncher-version.json`(최신 정식 릴리스의 버전 파일) 하나이고,
/// 응답에서는 `version` 만 쓴다 (응답 안의 값을 주소로 쓰지 않는다).
public protocol UpdateCheckClient: Sendable {
  /// 다운로드 페이지(`https://github.com/<저장소>/releases/latest`). nil 이면 이 빌드에 배포 저장소가 없어 업데이트 기능이 없다.
  var releasePageURL: URL? { get }

  /// 최신 정식 릴리스의 버전(버전 파일의 `version`). 버전 파일의 값이 숫자 버전이 아니면 nil.
  /// 한 번 부를 때 요청 하나(리다이렉트 포함). 저장소가 없으면 요청 없이 `.notConfigured`.
  /// Task 가 취소되면 `.cancelled` (Download 와 같은 취소 계약).
  func latestReleaseVersion() async throws(UpdateCheckError) -> AppVersion?
}
