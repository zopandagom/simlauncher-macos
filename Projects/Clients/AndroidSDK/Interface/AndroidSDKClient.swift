import Core
import Foundation

/// Android SDK 위치의 상태 확인과 없는 구성 요소(platform-tools·emulator·기본 시스템 이미지) 설치.
/// SDK 위치는 App 이 주입한 provider(`AndroidSDKRootChoice`: 기본 `~/Library/Android/sdk` 또는 설정 창에서 고른 폴더)를
/// 공개 메서드 한 번에 한 번 부른다. 디렉터리를 가리키는 링크면 따라간다. ANDROID_HOME·ANDROID_SDK_ROOT 는 보지 않는다.
/// 이미 있는 패키지 폴더는 고치거나 덮어쓰지 않는다. 네트워크는 주입받은 DownloadClient 로만 쓰고, 명령은 CommandClient 로
/// `zipinfo`·`unzip` 만 실행한다 (adb·emulator 는 실행하지 않는다).
public protocol AndroidSDKClient: Sendable {
  /// 파일만 읽는다 (네트워크·명령 없음). 메인 밖에서 돈다. 실패는 없다 (읽지 못한 것은 쓸 수 없음으로 판정한다).
  func checkSDK() async -> AndroidSDKStatus

  /// 저장소 XML 두 개를 동시에 메모리로 받아(`fetchData`, 상한 `AndroidRepository.maxByteCount`) 해석하고,
  /// 부를 때 다시 읽은 상태의 없는 구성 요소로 계획을 만든다. 없는 것이 없으면 빈 계획 (XML 을 받지 않는다).
  /// 위치가 쓸 수 없으면 `.sdkFolderUnavailable`.
  /// 취소: `fetchData` 의 규칙에 더해, 받은 뒤 해석·선택 중이거나 그 뒤에 Task 가 취소됐으면 결과와 관계없이 `.cancelled`
  /// (돌려주기 직전에 `Task.isCancelled` 확인).
  func fetchInstallPlan() async throws(AndroidSDKPlanError) -> AndroidSDKInstallPlan

  /// 계획의 패키지를 순서대로 설치한다. 시작 때(패키지 전) 차례로: provider 의 지금 위치가 `plan.root` 와 다르면
  /// `.sdkLocationChanged` → `acceptedLicenses`(지문)에 계획의 라이선스가 모두 없으면 `.licenseNotAccepted` →
  /// 받을 패키지의 최종 경로의 가장 가까운 있는 조상과 위치에 쓸 수 없으면 `.sdkFolderUnavailable` → 필요 공간 어림
  /// (archive 크기 × 3 의 합을 SDK 볼륨, 가장 큰 archive 를 받기 볼륨과 비교)이 모자라면 `.insufficientDiskSpace`.
  /// 어느 것이든 걸리면 아무것도 받지 않는다. 그 뒤 `plan.root` 에 끝까지 설치하고 provider 를 다시 부르지 않는다.
  /// 패키지마다 시작 직전에 최종 경로를 다시 보고 무엇이든 있으면 건너뛴다(alreadyPresent). 진행은 순서대로 알린다
  /// (앞 알림이 끝난 뒤 다음). 패키지 하나가 실패하면 나머지는 하지 않는다.
  /// 취소: 받기·확인·풀기 중이면 멈추고 그 패키지의 받은 폴더·스테이징을 지운 뒤 `.cancelled` (앞서 끝난 패키지는 남는다).
  /// 마무리(rename·스테이징 지우기)는 취소를 받지 않고, 끝낸 뒤 다음 패키지 시작에서 `.cancelled`. 돌아오면 unzip 은 끝나 있다.
  func install(
    _ plan: AndroidSDKInstallPlan,
    acceptedLicenses: Set<String>,
    progress: @escaping @Sendable (AndroidSDKInstallProgress) async -> Void
  ) async throws(AndroidSDKInstallError) -> AndroidSDKInstallOutcome

  /// 지금 위치의 남은 `.simlauncher-staging-*`(이 프로세스가 지금 쓰는 것 제외)를 지우고
  /// `DownloadClient.removeLeftoverDownloads()` 를 부른다. 실패는 무시한다.
  func removeLeftovers() async

  /// 설정 창이 고른 폴더를 판정한다 (파일만 읽고 쓰지 않는다). 링크면 따라간 실제 폴더를 본다.
  /// writable: 폴더의 `access(W_OK)` 와, `system-images` 가 있으면 그 `access(W_OK)`. 하나라도 false 면 false.
  func inspectCandidateFolder(_ url: URL) async -> (candidate: AndroidSDKFolderCandidate, writable: Bool)
}

/// 받기 실패 원인 (DownloadError 를 그대로 옮긴다. Interface 는 다른 Interface 를 import 하지 않는다).
public enum AndroidDownloadFailure: Hashable, Sendable {
  case insecureRedirect
  case httpStatus(Int)
  case offline
  case hostNotFound
  case cannotConnect
  case timedOut
  case connectionLost
  case secureConnectionFailed
  /// 받기 임시 폴더 볼륨(시동 디스크)의 여유가 모자라다.
  case insufficientDiskSpace
  /// 저장소 XML 이 `AndroidRepository.maxByteCount` 를 넘었다.
  case tooLarge
  case storageUnavailable
  case failed
}

/// 계획을 만들지 못한 이유. 화면 문구는 Feature 가 정한다.
public enum AndroidSDKPlanError: Error, Hashable, Sendable {
  /// 저장소 XML 을 받지 못했다.
  case download(AndroidDownloadFailure)
  /// 저장소 XML 형식을 읽지 못했다 (깨진 XML·모르는 루트).
  case repositoryUnreadable
  /// 이 Mac 에 맞는 패키지가 없다 (라이선스 원문이 없는 것도 여기 든다: 앱 업데이트가 필요할 수 있다).
  case noCompatiblePackage(AndroidSDKComponent)
  /// SDK 위치를 쓸 수 없다 (위치 문제·쓰기 권한·링크 미지원 볼륨).
  case sdkFolderUnavailable
  case cancelled
}

/// 설치 실패. 화면 문구는 Feature 가 정한다.
public enum AndroidSDKInstallError: Error, Hashable, Sendable {
  case download(AndroidSDKComponent, AndroidDownloadFailure)
  /// 받은 크기나 체크섬이 계획과 다르다.
  case checksumMismatch(AndroidSDKComponent)
  /// zipinfo·unzip 이 실패했다, 맨 위 폴더가 없다, 푼 트리를 읽지 못했다.
  case archiveUnreadable(AndroidSDKComponent)
  /// 경로 탈출·밖을 가리키는 링크·맨 위 항목 여럿 등 모양이 틀린 zip.
  case archiveUnsafe(AndroidSDKComponent)
  /// 저장 공간이 모자라다. required 는 필요한 바이트(어림 포함), available 은 여유(읽지 못하면 nil).
  case insufficientDiskSpace(AndroidSDKComponent, required: Int64, available: Int64?)
  /// SDK 폴더를 만들 수 없다·쓸 수 없다·파일이 있다·링크 미지원 볼륨.
  case sdkFolderUnavailable
  /// 최종 경로에 이미 무엇인가 생겼다 (Android Studio 가 그사이 설치했을 수 있다). 덮어쓰지 않았다.
  case destinationExists(AndroidSDKComponent)
  /// 계획의 라이선스 중 동의하지 않은 원문이 있다. 아무것도 하지 않았다.
  case licenseNotAccepted
  /// 설치 시작 때 SDK 위치가 계획과 다르다. 아무것도 하지 않았다.
  case sdkLocationChanged
  case cancelled
}
