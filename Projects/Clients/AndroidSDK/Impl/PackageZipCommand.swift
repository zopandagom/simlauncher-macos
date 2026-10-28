import Foundation

/// 패키지 zip 을 읽고 푸는 명령의 실행 파일·인자·환경. 세 패키지 모두 `/usr/bin/unzip` 으로 푼다: AppBundle 이 쓰는 풀기 명령은
/// Zip64 인 시스템 이미지 zip 을 풀지 못한다(종료 코드 1, `Couldn't read pkzip signature.`, 실측. ARCHITECTURE §4 명령 행).
/// 경로는 항상 `/` 로 시작하는 절대 경로라 옵션으로 해석되지 않는다.
enum PackageZipCommand {
  static let zipinfo = URL(filePath: "/usr/bin/zipinfo")
  static let unzip = URL(filePath: "/usr/bin/unzip")

  /// 빈 환경. `ZIPINFO`·`UNZIP` 옵션이 섞이지 않고 C 로케일이라 zipinfo 출력이 ASCII 다.
  static let environment: [String: String] = [:]

  /// unzip 이 디스크가 차서 끝났을 때의 종료 코드 (`write error (disk full?)`, stdin 이 tty 가 아니면 묻지 않고 계속한 뒤 50, 실측).
  static let diskFullExitCode: Int32 = 50

  /// `-s` 는 권한·크기·종류를 한 줄에, `-T` 는 시각을 한 토큰으로 보인다 (Zip64 도 읽는다, 실측).
  /// zipinfo 는 파일 이름을 와일드카드로 해석하므로 `source` 는 고정 이름 링크(`source.zip`)를 넘긴다.
  static func listArguments(source: URL) -> [String] {
    ["-s", "-T", source.path(percentEncoded: false)]
  }

  /// `-q` 조용히, `-n` 있는 파일을 덮어쓰지 않는다 (contents 는 빈 폴더라 실제로는 겹치지 않는다).
  /// `-:`(`../` 허용)·`-o`(덮어쓰기)는 쓰지 않는다.
  static func extractArguments(source: URL, contents: URL) -> [String] {
    ["-q", "-n", source.path(percentEncoded: false), "-d", contents.path(percentEncoded: false)]
  }
}
