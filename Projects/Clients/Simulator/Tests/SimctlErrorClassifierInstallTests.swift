import SimulatorInterface
import Testing
@testable import SimulatorImpl

/// install·launch 분류. 픽스처는 Xcode 27.1·iOS 27.0(시스템 언어 한국어)에서 확인한 stderr 원문이다 (경로는 줄였다).
extension SimctlErrorClassifierTests {
  struct AppCase: Sendable, CustomTestStringConvertible {
    let name: String
    let exitCode: Int32
    let stderr: String
    let expected: SimulatorError

    var testDescription: String {
      self.name
    }
  }

  // MARK: - domainAndCode

  @Test("domain 줄로 시작하는 첫 줄의 domain·code 를 읽는다")
  func domainAndCode() {
    let result = SimctlErrorClassifier.domainAndCode(Stderr.shutdown)
    #expect(result?.domain == "com.apple.CoreSimulator.SimError")
    #expect(result?.code == 405)
  }

  @Test("앞에 경고 줄이 있어도 찾고, 접두어로 시작하지 않는 줄 안의 (domain=…) 은 보지 않는다")
  func domainLineSearch() {
    let warned = "WARNING: something\n" + Stderr.x86Only
    #expect(SimctlErrorClassifier.domainAndCode(warned)?.code == 4)
    #expect(SimctlErrorClassifier.installError(exitCode: 4, stderr: warned) == .appIncompatible)
    #expect(SimctlErrorClassifier.domainAndCode("Underlying error (domain=IXErrorDomain, code=13):\n") == nil)
    #expect(SimctlErrorClassifier.domainAndCode("Invalid device: 00000000-0000-0000-0000-000000000000\n") == nil)
    #expect(SimctlErrorClassifier.domainAndCode("") == nil)
  }

  // MARK: - install

  @Test(
    "install 실패를 domain·code 로 분류한다",
    arguments: [
      AppCase(name: "꺼진 기기", exitCode: 149, stderr: Stderr.shutdown, expected: .deviceNotBooted),
      AppCase(
        name: "없는 기기",
        exitCode: 148,
        stderr: "Invalid device: 00000000-0000-0000-0000-000000000000\n",
        expected: .deviceNotFound
      ),
      AppCase(name: "x86_64 만 있음", exitCode: 4, stderr: Stderr.x86Only, expected: .appIncompatible),
      AppCase(name: "기기용 빌드", exitCode: 4, stderr: Stderr.deviceBuild, expected: .appIncompatible),
      AppCase(name: "Mac 앱", exitCode: 4, stderr: Stderr.macApp, expected: .appIncompatible),
      AppCase(name: "기기 종류 미지원", exitCode: 6, stderr: Stderr.deviceFamily, expected: .appIncompatible),
      AppCase(name: "높은 최소 iOS", exitCode: 16, stderr: Stderr.minimumOS, expected: .appRequiresNewerOS),
      AppCase(name: "없는 경로", exitCode: 2, stderr: Stderr.noSuchPath, expected: .appNotFound),
      AppCase(name: "번들 ID 없음", exitCode: 13, stderr: Stderr.missingBundleID, expected: .appInvalid),
      AppCase(name: "폴더가 아닌 파일", exitCode: 42, stderr: Stderr.notFolder, expected: .appInvalid),
      AppCase(name: "실행 파일 없음", exitCode: 1, stderr: Stderr.missingExecutable, expected: .commandFailed),
      AppCase(
        name: "xcrun 오류",
        exitCode: 72,
        stderr: "xcrun: error: unable to find utility \"simctl\", not a developer tool or in PATH\n",
        expected: .developerToolsUnavailable
      ),
      AppCase(name: "앱 이름에 Invalid device type", exitCode: 4, stderr: Stderr.injectedName, expected: .appIncompatible),
      AppCase(name: "모르는 출력", exitCode: 1, stderr: "something\n", expected: .commandFailed),
    ]
  )
  func installError(testCase: AppCase) {
    #expect(SimctlErrorClassifier.installError(exitCode: testCase.exitCode, stderr: testCase.stderr) == testCase
      .expected)
  }

  // MARK: - denialReason

  @Test("거절 이유는 domain 줄 뒤 최상위 거절 줄의 정해진 자리에서만 읽는다")
  func denialReason() {
    #expect(SimctlErrorClassifier.denialReason(Stderr.unknownToFrontBoard) == "NotFound")
    #expect(SimctlErrorClassifier.denialReason(Stderr.injectedReason) == "Security")
    #expect(SimctlErrorClassifier.denialReason(Stderr.notInstalled) == nil)
    #expect(SimctlErrorClassifier.denialReason(Stderr.indentedDenialOnly) == nil)
    #expect(SimctlErrorClassifier.denialReason(Stderr.reasonInOtherLine) == nil)
  }

  // MARK: - launch

  @Test(
    "launch 실패를 domain·code 로 분류한다",
    arguments: [
      AppCase(name: "꺼진 기기", exitCode: 149, stderr: Stderr.shutdown, expected: .deviceNotBooted),
      AppCase(name: "켜는 중 기기", exitCode: 149, stderr: Stderr.booting, expected: .deviceNotBooted),
      AppCase(
        name: "없는 기기",
        exitCode: 148,
        stderr: "Invalid device: 00000000-0000-0000-0000-000000000000\n",
        expected: .deviceNotFound
      ),
      AppCase(name: "설치되지 않은 번들 ID", exitCode: 4, stderr: Stderr.notInstalled, expected: .appNotInstalled),
      AppCase(name: "설치에 실패한 번들 ID", exitCode: 1, stderr: Stderr.unknownToFrontBoard, expected: .appNotInstalled),
      AppCase(name: "FBS 1 다른 이유", exitCode: 1, stderr: Stderr.fbsOtherReason, expected: .appLaunchFailed),
      AppCase(
        name: "괄호 설명에 for reason: NotFound",
        exitCode: 1,
        stderr: Stderr.injectedReason,
        expected: .appLaunchFailed
      ),
      AppCase(
        name: "거절 줄 밖의 reason: NotFound",
        exitCode: 1,
        stderr: Stderr.reasonInOtherLine,
        expected: .appLaunchFailed
      ),
      AppCase(name: "FBS 그 밖의 code", exitCode: 7, stderr: Stderr.fbs(7), expected: .appLaunchFailed),
      AppCase(name: "프로세스 없음", exitCode: 3, stderr: Stderr.noProcessHandle, expected: .appLaunchFailed),
      AppCase(name: "NSPOSIX 2", exitCode: 2, stderr: Stderr.noSuchPath, expected: .commandFailed),
      AppCase(name: "IX 4", exitCode: 4, stderr: Stderr.x86Only, expected: .commandFailed),
    ]
  )
  func launchError(testCase: AppCase) {
    #expect(SimctlErrorClassifier.launchError(exitCode: testCase.exitCode, stderr: testCase.stderr) == testCase
      .expected)
  }
}

/// 확인한 stderr 원문.
private enum Stderr {
  static let prefix = "An error was encountered processing the command "

  static let shutdown = Self.prefix + "(domain=com.apple.CoreSimulator.SimError, code=405):\n"
    + "Unable to lookup in current state: Shutdown\n"

  static let booting = Self.prefix + "(domain=com.apple.CoreSimulator.SimError, code=405):\n"
    + "Unable to lookup in current state: Booting\n"

  static let x86Only = Self.ix4(app: "X86", platforms: "[iOS-simulator, x86_64]")
  static let deviceBuild = Self.ix4(app: "Dev", platforms: "[iOS, arm64]")
  static let macApp = Self.ix4(app: "MacApp", platforms: "[macOS, arm64]")
  /// 앱 표시 이름에 다른 분류의 문구를 넣어도 domain 줄로 분류한다.
  static let injectedName = Self.ix4(app: "Invalid device type: Invalid device", platforms: "[iOS, arm64]")

  static let deviceFamily = Self.prefix + "(domain=IXUserPresentableErrorDomain, code=6):\n"
    + "App installation failed: ‘Ok’을(를) 설치할 수 없음\n"
    + "해당 앱은 이 기기용이 아닙니다.\n"
    + "This app was not built to support this device family; app is compatible with (\n    2\n"
    + ") but this device supports (\n    1\n)\n"
    + "Underlying error (domain=IXUserPresentableErrorDomain, code=6):\n"
    + "\t‘Ok’을(를) 설치할 수 없음\n"

  static let minimumOS = Self.prefix + "(domain=IXUserPresentableErrorDomain, code=16):\n"
    + "App installation failed: ‘MinHigh’ 앱은 최신 버전의 iOS가 필요합니다.\n"
    + "이 앱을 설치하려면 이 iPhone을 iOS 99.0 버전으로 업데이트해야 합니다.\n"
    + "The system version is lower than the minimum OS version specified for bundle at /…/MinHigh.app. "
    + "Have 27.0; need 99.0\n"
    + "Underlying error (domain=IXUserPresentableErrorDomain, code=16):\n"

  static let noSuchPath = Self.prefix + "(domain=NSPOSIXErrorDomain, code=2):\n"
    + "Simulator device failed to install the application.\n"
    + "Unhandled error domain NSPOSIXErrorDomain, code 2\n"
    + "Underlying error (domain=NSPOSIXErrorDomain, code=2):\n"
    + "\tlstat of /…/nonexistent.app failed: No such file or directory\n"

  static let missingBundleID = Self.prefix + "(domain=IXErrorDomain, code=13):\n"
    + "Simulator device failed to install the application.\n"
    + "Missing bundle ID.\n"
    + "Underlying error (domain=IXErrorDomain, code=13):\n"
    + "\tFailed to get bundle ID from /…/NoPlist.app\n"

  static let notFolder = Self.prefix + "(domain=IXErrorDomain, code=42):\n"
    + "Simulator device failed to install the application.\n"
    + "Failed to extract IPA.\n"
    + "Underlying error (domain=IXErrorDomain, code=42):\n"

  static let missingExecutable = Self.prefix + "(domain=IXUserPresentableErrorDomain, code=1):\n"
    + "App installation failed: … is missing its bundle executable\n"

  static let notInstalled = Self.fbs(4) + "Simulator device failed to launch com.example.notinstalled.\n"
    + "Underlying error (domain=FBSOpenApplicationServiceErrorDomain, code=4):\n"
    + "\tThe request to open \"com.example.notinstalled\" failed.\n"

  /// 설계 §11.2 원문 (`SL-FBS-2A` 기기, 설치에 실패한 x86_64 앱).
  static let unknownToFrontBoard = Self.fbs(1) + "Simulator device failed to launch com.example.fbs1.\n"
    + "The request was denied by service delegate (SBMainWorkspace) for reason: NotFound "
    + "(\"Application \"com.example.fbs1\" is unknown to FrontBoard\").\n"
    + "Underlying error (domain=FBSOpenApplicationServiceErrorDomain, code=1):\n"
    + "\tThe request to open \"com.example.fbs1\" failed.\n"
    + "\tThe request was denied by service delegate (SBMainWorkspace) for reason: NotFound "
    + "(\"Application \"com.example.fbs1\" is unknown to FrontBoard\").\n"

  /// 최상위 거절 줄의 reason 은 Security 이고, 앱 글자가 들어갈 수 있는 괄호 설명에 `for reason: NotFound (` 가 있다.
  static let injectedReason = Self.fbs(1) + "Simulator device failed to launch com.example.fbs1.\n"
    + "The request was denied by service delegate (SBMainWorkspace) for reason: Security "
    + "(\"Evil for reason: NotFound (x\").\n"

  /// 거절 줄이 없고 다른 줄에 `reason: NotFound` 가 있다.
  static let reasonInOtherLine = Self.fbs(1) + "Simulator device failed to launch Evil reason: NotFound.\n"
    + "Underlying error (domain=FBSOpenApplicationServiceErrorDomain, code=1):\n"

  /// 거절 줄이 탭 들여쓰기(Underlying 쪽)에만 있다.
  static let indentedDenialOnly = Self.fbs(1) + "Simulator device failed to launch com.example.fbs1.\n"
    + "Underlying error (domain=FBSOpenApplicationServiceErrorDomain, code=1):\n"
    + "\tThe request was denied by service delegate (SBMainWorkspace) for reason: NotFound (\"…\").\n"

  static let fbsOtherReason = Self.fbs(1) + "Simulator device failed to launch com.example.ok.\n"
    + "The request was denied by service delegate (SBMainWorkspace) for reason: Security (\"…\").\n"

  static let noProcessHandle = Self.prefix + "(domain=NSPOSIXErrorDomain, code=3):\n"
    + "Simulator device failed to launch com.example.crash.\n"
    + "did not return a process handle nor launch error\n"

  static func fbs(_ code: Int) -> String {
    self.prefix + "(domain=FBSOpenApplicationServiceErrorDomain, code=\(code)):\n"
  }

  private static func ix4(app: String, platforms: String) -> String {
    self.prefix + "(domain=IXUserPresentableErrorDomain, code=4):\n"
      + "App installation failed: ‘\(app)’의 업데이트가 필요함\n"
      + "해당 앱을 이 iOS 버전에서 사용하려면 개발자가 업데이트해야 합니다.\n"
      + "The executable at \"/…/\(app).app/Exec\" does not contain code for any platform and CPU architecture "
      + "combination that is runnable on this device. The executable has code for these platforms and architectures: "
      + "\(platforms). This device can run code for these platforms: iOS-simulator\n"
      + "Underlying error (domain=IXUserPresentableErrorDomain, code=4):\n"
      + "\t‘\(app)’의 업데이트가 필요함\n"
  }
}
