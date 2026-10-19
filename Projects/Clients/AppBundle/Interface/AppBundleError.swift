/// 번들 검사 실패. 화면 문구는 Feature 가 케이스별로 정한다.
public enum AppBundleError: Error, Hashable, Sendable {
  /// 파일 URL 이 아니다 (브라우저·메신저에서 끌어온 https 링크 등).
  case notLocalFile
  /// 심볼릭 링크를 따라간 경로에 아무것도 없다.
  case fileNotFound
  /// 확장자가 .ipa (대소문자 무시). 내용은 보지 않는다.
  case ipaFile
  /// 확장자가 .app 이 아니거나(.zip 포함. 2-B 에서 바뀐다), .app 이지만 폴더가 아니다.
  case notAppBundle
  /// .app 폴더에 Info.plist 가 없고 Contents/Info.plist 가 있다 (Mac 앱).
  case macOSApp
  /// Info.plist 없음·일반 파일 아님·1 MB 초과·읽기 실패·사전이 아님, CFBundleIdentifier 없음·`AppBundleID` 형식 위반,
  /// CFBundleExecutable 없음·`/`·NUL 포함·정확히 `.`·`..`, 실행 파일 없음·일반 파일 아님·읽기 실패·Mach-O 아님.
  case invalidBundle
}
