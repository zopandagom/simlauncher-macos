/// 번들 검사·zip 풀기 실패. 화면 문구는 Feature 가 케이스별로 정한다.
public enum AppBundleError: Error, Hashable, Sendable {
  /// 파일 URL 이 아니다 (브라우저·메신저에서 끌어온 https 링크 등). zip 에서도 같다.
  case notLocalFile
  /// 심볼릭 링크를 따라간 경로에 아무것도 없다. zip 에서도 같다 (실제 경로를 얻지 못함).
  case fileNotFound
  /// 확장자가 .ipa (대소문자 무시). 내용은 보지 않는다.
  case ipaFile
  /// 확장자가 .app 이 아니거나(.zip 은 `extractApp(fromZip:)` 으로 푼 뒤 검사한다), .app 이지만 폴더가 아니다.
  case notAppBundle
  /// .app 폴더에 Info.plist 가 없고 Contents/Info.plist 가 있다 (Mac 앱).
  case macOSApp
  /// Info.plist 없음·일반 파일 아님·1 MB 초과·읽기 실패·사전이 아님, CFBundleIdentifier 없음·`AppBundleID` 형식 위반,
  /// CFBundleExecutable 없음·`/`·NUL 포함·정확히 `.`·`..`, 실행 파일 없음·일반 파일 아님·읽기 실패·Mach-O 아님.
  case invalidBundle
  /// zip 이 일반 파일이 아님, zipinfo 종료 코드가 0 이 아님(항목 0 개는 제외), zipinfo 출력을 읽지 못함
  /// (헤더 형식·항목 수가 맞지 않음·크기를 숫자로 읽지 못함), ditto 종료 코드가 0 이 아님(디스크 부족 제외),
  /// 푼 뒤 트리를 훑다 오류. 깨짐·잘림·암호화·zip 아님이 여기 든다.
  case zipUnreadable
  /// 빈 zip, 또는 맨 위에 .app 폴더가 없다 (`__MACOSX`·`._*` 는 무시. 하위 폴더에만 있는 .app 과 파일인 X.app 포함).
  case zipWithoutApp
  /// 맨 위 .app 폴더가 둘 이상 (이름은 대소문자 무시로 `.app`). .app 하나와 다른 맨 위 항목은 받고 다른 항목은 무시한다.
  case zipWithMultipleApps
  /// 이름에 `..` 구성 요소가 있거나 `/` 로 시작한다, 맨 위 .app 이 심볼릭 링크다, 링크가 대상 없음·루프이거나
  /// 실제 경로가 범위 밖이다 (.app 안의 링크는 .app 밖, 그 밖의 링크는 푼 폴더 밖).
  case zipUnsafeEntry
  /// zip 이 선언한 풀린 크기 합이 임시 폴더 볼륨의 여유보다 크다, 또는 풀다가 디스크가 찼다 (`No space left on device`).
  case insufficientDiskSpace
  /// 임시 폴더·`contents`·`source.zip` 링크를 만들지 못했다, zipinfo·ditto 를 시작하지 못했다.
  case extractionUnavailable
}
