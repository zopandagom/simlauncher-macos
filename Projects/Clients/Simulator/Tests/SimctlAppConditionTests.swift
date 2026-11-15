import Core
import Foundation
import SimulatorInterface
import Testing
@testable import SimulatorImpl

/// simctl push 출력 원문 (TC-B 실측, Xcode 27.2·iOS 26.5·27.0). 성공은 stdout, 실패는 모두 stderr 이고 payload 글자는 나오지 않는다.
enum PushOutput {
  static let prefix = "An error was encountered processing the command "

  /// 성공 (stdout, exit 0). 26.5 는 알림 권한 없는 앱·미설치 앱에도 이 출력이다.
  static let sent = "Notification sent to 'com.apple.MobileSMS'\n"

  /// 4097 바이트 (exit 28).
  static let tooLarge = prefix + "(domain=NSPOSIXErrorDomain, code=28):\n"
    + "Payload too large, must be 4096 bytes or less\n"
    + "No space left on device\n"

  /// 깨진 JSON·빈 입력 (**exit 0**, stdout 비어 있음).
  static let notJSON = prefix + "(domain=NSCocoaErrorDomain, code=3840):\n"
    + "The data couldn\u{2019}t be read because it isn\u{2019}t in the correct format.\n"
    + "The data is not in the correct format.\n"

  /// 루트 배열 (exit 22).
  static let rootNotObject = prefix + "(domain=NSPOSIXErrorDomain, code=22):\n"
    + "JSON root is not an object\n"
    + "Invalid argument\n"

  /// aps 없음 (exit 22).
  static let missingAPS = prefix + "(domain=NSPOSIXErrorDomain, code=22):\n"
    + "Simulator device failed to complete the requested operation.\n"
    + "Invalid argument\n"
    + "Underlying error (domain=NSPOSIXErrorDomain, code=22):\n"
    + "\tNotification payload is missing the aps key\n"
    + "\tInvalid argument\n"

  /// aps 문자열·빈 사전·alert 숫자 (exit 14).
  static let badAddress = prefix + "(domain=NSPOSIXErrorDomain, code=14):\n"
    + "Simulator device failed to complete the requested operation.\n"
    + "Bad address\n"
    + "Underlying error (domain=NSPOSIXErrorDomain, code=14):\n"
    + "\tFailed to allocate UNNotificationRequest\n"
    + "\tBad address\n"

  /// 27.0: 알림 권한 없는 앱·미설치 번들 (exit 211).
  static let notAuthorized = prefix + "(domain=UNErrorDomain, code=2003):\n"
    + "Simulator device failed to complete the requested operation.\n"
    + "Underlying error (domain=UNErrorDomain, code=2003):\n"
    + "\tRepository could not save notification. Source is not authorized.\n"

  /// 27.0: alert 없는 badge·sound (exit 210).
  static let noContent = prefix + "(domain=UNErrorDomain, code=2002):\n"
    + "Simulator device failed to complete the requested operation.\n"
    + "Underlying error (domain=UNErrorDomain, code=2002):\n"
    + "\tRepository could not save notification. No content that needs to alert.\n"

  /// 27.0: content-available 만 (exit 121).
  static let noVisibleContent = prefix + "(domain=UNErrorDomain, code=1401):\n"
    + "Simulator device failed to complete the requested operation.\n"
    + "Underlying error (domain=UNErrorDomain, code=1401):\n"
    + "\tNotification has no user visible content\n"

  /// 꺼진 기기 (exit 149).
  static let notBooted = prefix + "(domain=com.apple.CoreSimulator.SimError, code=405):\n"
    + "Unable to lookup in current state: Shutdown\n"

  /// 없는 기기 (exit 148).
  static let invalidDevice = "Invalid device: 00000000-0000-0000-0000-000000000000\n"
}

/// 앱 단위 테스트 조건(privacy·push) 인자와 push 판정. 기대 배열은 실제 기기로 확인한 명령이다 (Xcode 27.2, iOS 26.5·27.0).
struct SimctlAppConditionTests {
  private static let udid = "B66201ED-154C-4F97-A6C7-C88F42E8D3A7"
  private static let bundle = "com.zopandagom.simlauncher.sampleapp"

  @Test("privacy 인자: 세 동작 × 서비스 토큰 전부, 번들 ID 앞 -- 없음", arguments: IOSPrivacyAction.allCases)
  func privacy(_ action: IOSPrivacyAction) {
    let tokens = IOSPrivacyService.allCases.map { service in
      SimctlCommand.privacy(udid: Self.udid, action: action, service: service, bundleID: Self.bundle)
    }
    let expected = [
      "location", "location-always", "camera", "microphone", "photos", "photos-add", "contacts", "calendar",
      "reminders", "motion", "media-library",
    ].map { ["simctl", "privacy", Self.udid, action.rawValue, $0, Self.bundle] }
    #expect(tokens == expected)
  }

  @Test("동작 토큰은 grant·revoke·reset")
  func actionTokens() {
    #expect(IOSPrivacyAction.allCases.map(\.rawValue) == ["grant", "revoke", "reset"])
  }

  @Test("push 인자: 번들 ID 뒤 - (stdin)")
  func push() {
    #expect(SimctlCommand.push(udid: Self.udid, bundleID: Self.bundle) == [
      "simctl",
      "push",
      Self.udid,
      Self.bundle,
      "-",
    ])
  }

  @Test("실행 중 앱을 끝내지 않는 서비스는 위치 둘뿐이다 (실측)")
  func terminatesRunningApp() {
    #expect(IOSPrivacyService.allCases.filter { !$0.terminatesRunningApp } == [.location, .locationAlways])
  }

  struct PushCase: Sendable, CustomTestStringConvertible {
    let name: String
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let expected: Result<IOSPushOutcome, SimulatorError>

    var testDescription: String {
      self.name
    }
  }

  @Test(
    "push 판정: 실측 출력 원문(`PushOutput`)·이름에 (합성) 을 붙인 만든 출력 → 결과",
    arguments: [
      PushCase(name: "보냄", exitCode: 0, stdout: PushOutput.sent, stderr: "", expected: .success(.sent)),
      PushCase(
        name: "알림 권한 없음 2003",
        exitCode: 211,
        stdout: "",
        stderr: PushOutput.notAuthorized,
        expected: .success(.notAuthorized)
      ),
      PushCase(
        name: "보일 내용 없음 2002",
        exitCode: 210,
        stdout: "",
        stderr: PushOutput.noContent,
        expected: .success(.noVisibleContent)
      ),
      PushCase(
        name: "보일 내용 없음 1401",
        exitCode: 121,
        stdout: "",
        stderr: PushOutput.noVisibleContent,
        expected: .success(.noVisibleContent)
      ),
      PushCase(
        name: "크기 28",
        exitCode: 28,
        stdout: "",
        stderr: PushOutput.tooLarge,
        expected: .success(.payloadRejected)
      ),
      PushCase(
        name: "루트 22",
        exitCode: 22,
        stdout: "",
        stderr: PushOutput.rootNotObject,
        expected: .success(.payloadRejected)
      ),
      PushCase(
        name: "aps 없음 22",
        exitCode: 22,
        stdout: "",
        stderr: PushOutput.missingAPS,
        expected: .success(.payloadRejected)
      ),
      PushCase(
        name: "aps 형식 14",
        exitCode: 14,
        stdout: "",
        stderr: PushOutput.badAddress,
        expected: .success(.payloadRejected)
      ),
      PushCase(
        name: "3840 은 exit 0 이어도 실패",
        exitCode: 0,
        stdout: "",
        stderr: PushOutput.notJSON,
        expected: .failure(.commandFailed)
      ),
      PushCase(
        name: "꺼진 기기 405",
        exitCode: 149,
        stdout: "",
        stderr: PushOutput.notBooted,
        expected: .failure(.deviceNotBooted)
      ),
      PushCase(
        name: "없는 기기",
        exitCode: 148,
        stdout: "",
        stderr: PushOutput.invalidDevice,
        expected: .failure(.deviceNotFound)
      ),
      PushCase(
        name: "xcrun 오류 (합성)",
        exitCode: 72,
        stdout: "",
        stderr: "xcrun: error: unable to find utility \"simctl\", not a developer tool or in PATH\n",
        expected: .failure(.developerToolsUnavailable)
      ),
      PushCase(
        name: "Invalid device 가 줄 머리에 없으면 commandFailed (합성)",
        exitCode: 1,
        stdout: "",
        stderr: "warning: Invalid device type\n",
        expected: .failure(.commandFailed)
      ),
      PushCase(
        name: "그 밖 domain (합성)",
        exitCode: 1,
        stdout: "",
        stderr: PushOutput.prefix + "(domain=NSPOSIXErrorDomain, code=1):\nOperation not permitted\n",
        expected: .failure(.commandFailed)
      ),
      PushCase(name: "exit 0 인데 보낸 줄 없음 (합성)", exitCode: 0, stdout: "", stderr: "", expected: .failure(.commandFailed)),
      PushCase(
        name: "보낸 줄이 줄 머리에 없음 (합성)",
        exitCode: 0,
        stdout: "note: Notification sent to 'x'\n",
        stderr: "",
        expected: .failure(.commandFailed)
      ),
      PushCase(
        name: "domain 줄 없는 0 아닌 종료 (합성)",
        exitCode: 117,
        stdout: "",
        stderr: "Usage: simctl push\n",
        expected: .failure(.commandFailed)
      ),
      PushCase(
        name: "보낸 줄과 domain 줄이 함께면 domain 이 먼저 (합성)",
        exitCode: 0,
        stdout: PushOutput.sent,
        stderr: PushOutput.notJSON,
        expected: .failure(.commandFailed)
      ),
    ]
  )
  func pushOutcome(_ pushCase: PushCase) {
    #expect(
      SimctlErrorClassifier.pushOutcome(exitCode: pushCase.exitCode, stdout: pushCase.stdout, stderr: pushCase.stderr)
        == pushCase.expected
    )
  }

  @Test(
    "privacy 실패 분류: 405 → deviceNotBooted, Invalid device → deviceNotFound, Operation not permitted·사용법 → commandFailed"
  )
  func privacyErrors() {
    #expect(SimctlErrorClassifier
      .bootedDeviceCommandError(exitCode: 149, stderr: PushOutput.notBooted) == .deviceNotBooted)
    #expect(SimctlErrorClassifier
      .bootedDeviceCommandError(exitCode: 148, stderr: PushOutput.invalidDevice) == .deviceNotFound)
    // 실측(`grant notifications`·`grant bogus`, exit 1) stderr 의 앞 세 줄만 옮겼다 (뒤 줄은 뺐다).
    let notPermitted = PushOutput.prefix + "(domain=NSPOSIXErrorDomain, code=1):\n"
      + "Simulator device failed to complete the requested operation.\n"
      + "Operation not permitted\n"
    #expect(SimctlErrorClassifier.bootedDeviceCommandError(exitCode: 1, stderr: notPermitted) == .commandFailed)
    #expect(
      SimctlErrorClassifier.bootedDeviceCommandError(
        exitCode: 117,
        // 첫 줄은 실측(번들 생략, exit 117), 사용법 줄은 합성 (실측 사용법 원문은 옮기지 않았다).
        stderr: "Bundle identifier is required for grant actions\n"
          + "Usage: simctl privacy <device> <action> <service> [<bundle identifier>]\n"
      ) == .commandFailed
    )
  }
}
