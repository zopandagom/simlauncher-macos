import CommandInterface
import Core
import CryptoKit
import Foundation

/// iOS 레이아웃 러너의 명령 인자·환경과 결과 해석 (순수). 인자는 배열이고 셸을 거치지 않는다.
/// 경로는 모두 `/` 로 시작하는 절대 경로라 옵션으로 읽히지 않는다.
enum LayoutRunnerCommands {
  /// 선택한 Xcode 의 xcodebuild (`<Developer>/usr/bin/xcodebuild`).
  static func xcodebuild(_ xcode: XcodeInstallation) -> URL {
    xcode.developerDirectory.appending(path: "usr/bin/xcodebuild", directoryHint: .notDirectory)
  }

  /// 기본 환경 + `DEVELOPER_DIR=<Developer>`.
  static func environment(base: [String: String], xcode: XcodeInstallation) -> [String: String] {
    var environment = base
    environment["DEVELOPER_DIR"] = xcode.developerDirectory.path(percentEncoded: false)
    return environment
  }

  /// `xcodebuild build-for-testing` 인자. 서명 없이 시뮬레이터용으로, 산출물은 `derivedData` 아래.
  static func buildArguments(sourceDirectory: URL, derivedData: URL) -> [String] {
    [
      "build-for-testing",
      "-project", sourceDirectory.appending(path: LayoutRunnerSource.projectFolder).path(percentEncoded: false),
      "-scheme", LayoutRunnerSource.scheme,
      "-destination", "generic/platform=iOS Simulator",
      "-derivedDataPath", derivedData.path(percentEncoded: false),
      "-quiet",
      "CODE_SIGNING_ALLOWED=NO",
    ]
  }

  /// 상주 러너 `xcodebuild test-without-building` 인자. DerivedData·결과 번들을 세션 폴더로 준다
  /// (주지 않으면 `~/Library/Developer/Xcode/DerivedData` 에 만든다, 실측). 테스트 시간 제한은 끈다.
  static func testArguments(xctestrun: URL, udid: String, sessionDirectory: URL) -> [String] {
    [
      "test-without-building",
      "-xctestrun", xctestrun.path(percentEncoded: false),
      "-destination", "id=\(udid)",
      "-derivedDataPath", sessionDirectory.appending(path: "DerivedData").path(percentEncoded: false),
      "-resultBundlePath", sessionDirectory.appending(path: "result.xcresult").path(percentEncoded: false),
      "-test-timeouts-enabled", "NO",
    ]
  }

  /// 상주 러너 환경: 기본 환경 + `DEVELOPER_DIR` + `TEST_RUNNER_` 를 붙인 세션 폴더·토큰·유휴 초.
  static func testEnvironment(
    base: [String: String],
    xcode: XcodeInstallation,
    sessionDirectory: URL,
    token: String,
    idleSeconds: Int
  ) -> [String: String] {
    var environment = self.environment(base: base, xcode: xcode)
    let prefix = LayoutRunnerProtocol.testRunnerPrefix
    environment[prefix + LayoutRunnerProtocol.directoryVariable] = sessionDirectory.path(percentEncoded: false)
    environment[prefix + LayoutRunnerProtocol.sessionVariable] = token
    environment[prefix + LayoutRunnerProtocol.idleVariable] = String(idleSeconds)
    return environment
  }

  // MARK: 러너 생존 확인

  static let psExecutable = URL(filePath: "/bin/ps", directoryHint: .notDirectory)

  static func psArguments(pid: Int32) -> [String] {
    ["-p", String(pid), "-o", "comm="]
  }

  /// `ps -p <pid> -o comm=` 결과가 이 기기의 러너면 true: 종료 코드 0, 앞뒤 공백을 뺀 출력이 `/Devices/<UDID>/` 를 포함하고
  /// `/<productName>-Runner` 로 끝난다 (pid 재사용에 속지 않는다). 죽은 pid 는 종료 코드 1·빈 출력(실측).
  static func isRunnerAlive(_ result: CommandResult, udid: String) -> Bool {
    guard result.exitCode == 0, let text = String(bytes: result.stdout, encoding: .utf8) else { return false }
    let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return path.contains("/Devices/\(udid)/") && path.hasSuffix("/\(IOSLayoutRunner.productName)-Runner")
  }

  // MARK: 빌드 키

  /// `<Xcode 번들>/Contents/version.plist` (xcodebuild -version 과 같은 빌드 번호. Info.plist 의 DTXcodeBuild 와 다를 수 있다, 실측).
  static func versionPlist(_ xcode: XcodeInstallation) -> URL {
    xcode.bundleURL.appending(path: "Contents/version.plist", directoryHint: .notDirectory)
  }

  /// version.plist 의 `ProductBuildVersion` 에서 영숫자만 남긴 값. plist 가 아니거나 키가 없거나 남은 것이 없으면 nil.
  static func productBuildVersion(fromVersionPlist data: Data) -> String? {
    guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          let version = plist["ProductBuildVersion"] as? String
    else {
      return nil
    }
    let kept = String(version.unicodeScalars.filter { $0.isASCII && CharacterSet.alphanumerics.contains($0) })
    return kept.isEmpty ? nil : kept
  }

  /// `<ProductBuildVersion 또는 unknown>-<hex16>`. hex16 = SHA-256(소스 digest ‖ 0 ‖ Xcode 번들 경로) 앞 16자.
  /// Xcode 가 바뀌거나(다른 번들·같은 자리 업데이트) 소스가 바뀌면 키가 달라져 다시 빌드한다.
  static func buildKey(productBuildVersion: String?, sourceDigest: String, xcodePath: String) -> String {
    var hasher = SHA256()
    hasher.update(data: Data(sourceDigest.utf8))
    hasher.update(data: Data([0]))
    hasher.update(data: Data(xcodePath.utf8))
    let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
    return "\(productBuildVersion ?? "unknown")-\(hex.prefix(16))"
  }

  /// 시뮬레이터 UDID 형식(UUID)인지. 아니면 명령을 실행하지 않는다.
  static func isUDID(_ value: String) -> Bool {
    UUID(uuidString: value) != nil
  }
}
