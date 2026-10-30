import Foundation

/// apk 를 읽는 명령의 실행 파일·인자·환경. 경로는 항상 `/` 로 시작하는 절대 경로라 옵션으로 해석되지 않는다.
/// 두 명령 모두 인자의 zip 이름을 와일드카드로 해석하므로(실측: `d[x].apk` 를 넘기면 옆의 `dx.apk` 를 연다)
/// `source` 는 고정 이름 링크(`source.apk`)를 넘긴다.
enum APKCommand {
  static let zipinfo = URL(filePath: "/usr/bin/zipinfo")
  static let unzip = URL(filePath: "/usr/bin/unzip")

  /// 빈 환경. `ZIPINFO`·`UNZIP` 옵션이 섞이지 않고, C 로케일이라 zipinfo 출력이 ASCII 다.
  static let environment: [String: String] = [:]

  /// apk 맨 위의 manifest 항목 이름. 와일드카드 문자가 없어 unzip 이 정확히 이 이름만 고른다.
  static let manifestEntry = "AndroidManifest.xml"

  /// `-s` 는 권한·크기·종류를 한 줄에, `-T` 는 시각을 한 토큰으로 보여 열 나누기가 단순하다.
  static func listArguments(source: URL) -> [String] {
    ["-s", "-T", source.path(percentEncoded: false)]
  }

  /// `-p` 는 풀지 않고 항목 내용을 stdout 으로 낸다 (항목 없음은 종료 코드 11, 잘림 9, 실측).
  static func manifestArguments(source: URL) -> [String] {
    ["-p", source.path(percentEncoded: false), self.manifestEntry]
  }
}
