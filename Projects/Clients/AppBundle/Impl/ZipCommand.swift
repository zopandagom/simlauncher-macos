import Foundation

/// zip 을 읽고 푸는 명령의 실행 파일·인자·환경. 경로는 항상 `/` 로 시작하는 절대 경로라 옵션으로 해석되지 않는다.
enum ZipCommand {
  static let zipinfo = URL(filePath: "/usr/bin/zipinfo")
  static let ditto = URL(filePath: "/usr/bin/ditto")

  /// 빈 환경. `ZIPINFO`·`UNZIP` 옵션이 섞이지 않고, C 로케일이라 zipinfo 출력이 ASCII 이고
  /// ditto stderr 가 영어(`No space left on device`)다.
  static let environment: [String: String] = [:]

  /// `-s` 는 권한·크기·종류를 한 줄에, `-T` 는 시각을 한 토큰으로 보여 열 나누기가 단순하다.
  /// zipinfo 는 파일 이름을 와일드카드로 해석하므로 `source` 는 고정 이름 링크(`source.zip`)를 넘긴다.
  static func listArguments(source: URL) -> [String] {
    ["-s", "-T", source.path(percentEncoded: false)]
  }

  /// `--noqtn`·`--norsrc` 는 쓰지 않는다 (`--norsrc` 면 `._` 파일이 .app 안에 일반 파일로 남는다).
  static func extractArguments(source: URL, contents: URL) -> [String] {
    ["-x", "-k", source.path(percentEncoded: false), contents.path(percentEncoded: false)]
  }
}
