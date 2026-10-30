/// apk 검사 실패. 화면 문구는 Feature 가 케이스별로 정한다.
public enum AndroidPackageError: Error, Hashable, Sendable {
  /// 파일 URL 이 아니다 (브라우저에서 끌어온 https 링크 등).
  case notLocalFile
  /// 링크를 따라간 경로에 아무것도 없다.
  case fileNotFound
  /// 확장자 .aab(대소문자 무시, 내용은 보지 않는다), 또는 .apk 인데 맨 위에 AndroidManifest.xml 이 없고
  /// `base/manifest/AndroidManifest.xml` 이 있다 (이름만 바꾼 App Bundle).
  case appBundle
  /// 확장자 .apks·.xapk·.apkm (분할 apk 묶음).
  case splitPackage
  /// 그 밖의 확장자, 폴더, 일반 파일이 아님.
  case notAPK
  /// zipinfo 종료 코드 ≠ 0(잘림·zip 아님은 9, 실측)·출력 해석 실패, AndroidManifest.xml 이 없거나 둘 이상이거나 선언 크기 4 MiB 초과,
  /// unzip 종료 코드 ≠ 0 또는 4 MiB 초과, AXML 해석 실패, package 없음·형식 위반.
  case unreadable
  /// 링크(`l`) 항목, 이름에 `..` 구성 요소나 `/` 로 시작.
  case unsafeEntry
  /// v1 서명 파일(`META-INF/` 바로 아래 `.RSA`·`.DSA`·`.EC`, 대소문자 무시)도 v2+ 서명 블록도 없다.
  /// 끝부분을 읽지 못하거나 Zip64 라 블록 위치를 모르면 서명 없음으로 보지 않는다 (기기에 맡긴다).
  case unsigned
  /// 임시 폴더·링크를 만들지 못했다, zipinfo·unzip 을 시작하지 못했다.
  case inspectionUnavailable
}
