import Core
import Foundation
import UpdateCheckInterface

/// 최신 정식 릴리스의 버전 파일(`SimLauncher-version.json`) 해석. 형식은 릴리스 워크플로가 만드는 `{"version":"<버전>"}` (docs/RELEASING.md).
/// `version` 만 쓰고, 모르는 키는 무시한다 (앞으로 더할 키를 옛 앱이 그대로 읽게).
enum ReleaseVersionFile {
  /// 최상위가 JSON 객체가 아니거나 `version` 이 없거나 문자열이 아니면 `.unexpectedResponse`.
  /// 그 밖은 `AppVersion(version)` (숫자 버전이 아니면 nil).
  static func version(from data: Data) throws(UpdateCheckError) -> AppVersion? {
    let body: ReleaseVersionFileBody
    do {
      body = try JSONDecoder().decode(ReleaseVersionFileBody.self, from: data)
    } catch {
      throw .unexpectedResponse
    }
    return AppVersion(body.version)
  }
}

private struct ReleaseVersionFileBody: Decodable {
  let version: String
}
