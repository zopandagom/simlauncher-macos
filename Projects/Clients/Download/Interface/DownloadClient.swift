import Core
import Foundation

/// 사용자가 입력하거나 등록한 HTTPS 주소와, 사용자가 Android 도구 설치를 고를 때 AndroidSDK Client 가 넘기는 Google Android SDK
/// 저장소 주소(앱이 정한 고정 주소 `dl.google.com/android/repository` 와 그 XML 의 archive)에서 파일을 받는 Client.
/// 네트워크는 이 Client 의 Impl 에서만 쓴다
/// (lint `network_only_in_download_impl` 과 리뷰, CONVENTIONS §4). 호출마다 따로 받는다 (동시에 여러 개 가능).
/// 리다이렉트는 https 로만 따라간다. 쿠키·캐시·자격 증명을 쓰거나 남기지 않고, 서버의 인증 요구(Basic·Negotiate 등)에
/// 응하지 않는다.
public protocol DownloadClient: Sendable {
  /// 새 임시 폴더 `SimLauncher-Download-<UUID>` 의 `download` 파일로 받는다. 크기 상한은 없고,
  /// Content-Length 가 있으면 시작 전에 임시 폴더 볼륨의 여유와 비교한다.
  /// - `onProgress`: 응답을 받으면 (0, 전체) 한 번, 받는 중 최대 0.1초마다 한 번, 성공하면 마지막 (받은 전체, 전체) 한 번.
  ///   같은 값을 연속으로 넘기지 않는다 (빈 본문이면 (0, 전체) 한 번뿐). 앞 호출이 끝난 뒤 다음을 부르고, 늦게 처리하면
  ///   중간 값은 건너뛴다(가장 최근 값만). 돌아온 뒤에는 부르지 않는다.
  /// - 실패하면 만든 폴더를 지우고 던진다. 성공하면 호출한 쪽이 `removeDownloaded(_:)` 를 부른다.
  /// - Task 가 취소되면 전송을 멈추고, 전송이 끝난 뒤 폴더를 지우고 `.cancelled` 를 던진다. 시작 전에 이미 취소됐으면
  ///   폴더를 만들지 않고 요청도 보내지 않는다. 취소된 채로 끝나면 전송 결과(성공·다른 실패)와 관계없이 `.cancelled` 다.
  func download(
    _ url: DownloadURL,
    onProgress: @escaping @Sendable (DownloadProgress) async -> Void
  ) async throws(DownloadError) -> DownloadedFile

  /// 작은 파일(카탈로그 JSON·Android SDK 저장소 XML)을 메모리로 받는다. 파일을 만들지 않는다. Content-Length 가 `maxBytes` 를 넘으면 본문을 받지 않고,
  /// 없으면 받는 중 넘는 순간 멈추고 `.tooLarge`. 전체 시간 제한 60초. 취소 규칙은 `download` 와 같다.
  func fetchData(_ url: DownloadURL, maxBytes: Int) async throws(DownloadError) -> Data

  /// `download` 가 만든 폴더를 지운다. 실패는 던지지 않는다 (다음 `removeLeftoverDownloads()` 가 다시 지운다).
  /// 이 Client 가 만든 형식의 폴더가 아니면 아무것도 하지 않는다.
  func removeDownloaded(_ file: DownloadedFile) async

  /// 남은 `SimLauncher-Download-*` 폴더(앞선 실행이 남겼거나 지우지 못한 것)를 지운다. 이 프로세스가 지금 쓰는 폴더는
  /// 건너뛴다. 실패는 무시한다.
  func removeLeftoverDownloads() async
}
