import Foundation

/// 업데이트를 확인할 GitHub 저장소 "<소유자>/<이름>". 앱이 여는·받는 주소는 이 값으로만 만든다.
/// 값은 빌드 설정(`Env.releaseRepository` → 앱 Info.plist `SimLauncherReleaseRepository`)에서 오고, 사용자·관리자 설정으로 바꾸지 않는다.
public struct ReleaseRepository: Hashable, Sendable {
  public let owner: String
  public let name: String
  /// 최신 정식 릴리스에 올리는 버전 파일의 고정 이름. 릴리스 쪽(`scripts/release.sh`·`.github/workflows/release.yml`)과 같은 값.
  public static let versionFileName = "SimLauncher-version.json"
  /// `https://github.com/<소유자>/<이름>/releases/latest/download/SimLauncher-version.json` (최신 정식 릴리스의 버전 파일).
  public let versionFileURL: DownloadURL
  /// `https://github.com/<소유자>/<이름>/releases/latest` (브라우저로 여는 다운로드 페이지).
  public let latestReleasePageURL: URL

  static let maxOwnerLength = 39
  static let maxNameLength = 100

  /// "<소유자>/<이름>" 만 받는다. 소유자: ASCII 영숫자·`-`, 1~39자, `-` 로 시작하지 않음. 이름: ASCII 영숫자·`.`·`_`·`-`, 1~100자,
  /// `.`·`..` 아님. 슬래시는 정확히 하나. 앞뒤 공백·빈 문자열·그 밖은 nil.
  public init?(_ text: String) {
    let parts = text.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 2 else {
      return nil
    }
    let owner = String(parts[0])
    let name = String(parts[1])
    guard Self.isValidOwner(owner), Self.isValidName(name) else {
      return nil
    }
    guard
      let versionFileURL = DownloadURL(
        "https://github.com/\(owner)/\(name)/releases/latest/download/\(Self.versionFileName)"
      ),
      let pageURL = URL(string: "https://github.com/\(owner)/\(name)/releases/latest")
    else {
      return nil
    }
    self.owner = owner
    self.name = name
    self.versionFileURL = versionFileURL
    self.latestReleasePageURL = pageURL
  }

  private static func isValidOwner(_ owner: String) -> Bool {
    guard (1 ... self.maxOwnerLength).contains(owner.utf8.count), owner.first != "-" else {
      return false
    }
    return owner.utf8.allSatisfy { self.isASCIIAlphanumeric($0) || $0 == UInt8(ascii: "-") }
  }

  private static func isValidName(_ name: String) -> Bool {
    guard (1 ... self.maxNameLength).contains(name.utf8.count), name != ".", name != ".." else {
      return false
    }
    return name.utf8.allSatisfy { byte in
      self.isASCIIAlphanumeric(byte) || byte == UInt8(ascii: ".") || byte == UInt8(ascii: "_")
        || byte == UInt8(ascii: "-")
    }
  }

  private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
    (UInt8(ascii: "a") ... UInt8(ascii: "z")).contains(byte)
      || (UInt8(ascii: "A") ... UInt8(ascii: "Z")).contains(byte)
      || (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(byte)
  }
}
