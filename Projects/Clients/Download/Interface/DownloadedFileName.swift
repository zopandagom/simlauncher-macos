/// `DownloadClient.download(_:savingAs:onProgress:)` 가 받은 파일의 고정 이름. 서버가 준 이름은 쓰지 않는다.
public enum DownloadedFileName: String, Hashable, Sendable, CaseIterable {
  /// 빌드 zip·Android SDK 패키지.
  case download
  /// Android apk. adb 가 `.apk` 로 끝나는 경로만 받는다.
  case apk = "download.apk"
}
