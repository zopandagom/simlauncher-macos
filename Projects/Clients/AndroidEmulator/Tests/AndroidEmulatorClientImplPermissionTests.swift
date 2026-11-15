import AndroidEmulatorInterface
import CommandInterface
import CommandTesting
import Core
import Foundation
import Synchronization
import Testing
@testable import AndroidEmulatorImpl

/// 런타임 권한 읽기·쓰기: 앱 작업과 같은 사전 확인 뒤에만 명령을 보내고, 쓰기 뒤 다시 읽어 판정한다. adb 는 흉내(`FakeADB.onApp`),
/// dumpsys 출력은 `PermissionDump` 픽스처(실측 줄)이고, 그 밖의 출력은 실측 원문이거나 그 자리에 `// 합성` 을 적은 만든 출력이다.
struct AndroidEmulatorClientImplPermissionTests {
  private static let pixel = AndroidEmulatorClientImplAppTests.pixel
  private static let contacts = PermissionDump.contacts
  private static let readSMS = AndroidRuntimePermission("android.permission.READ_SMS")!
  private static let readContacts = AndroidRuntimePermission("android.permission.READ_CONTACTS")!
  private static let dumpsys = ["-s", "emulator-5554", "shell", "dumpsys", "package", "com.google.android.contacts"]

  private static func change(_ verb: String, _ permission: AndroidRuntimePermission) -> [String] {
    ["-s", "emulator-5554", "shell", "pm", verb, "com.google.android.contacts", "'\(permission.rawValue)'"]
  }

  private static func clear(_ permission: AndroidRuntimePermission) -> [String] {
    self.change("clear-permission-flags", permission) + ["user-set", "user-fixed"]
  }

  private static func result(_ code: Int32, stdout: String = "", stderr: String = "") -> CommandResult {
    AndroidEmulatorClientImplAppTests.result(code, stdout: stdout, stderr: stderr)
  }

  /// 합성: 연락처 덤프(실측 줄)에서 READ_SMS·READ_CONTACTS 의 `granted=` 값만 바꾼 출력 (기본값이면 실측 그대로).
  private static func contactsDump(readSMS: Bool = false, readContacts: Bool = true) -> CommandResult {
    let text = PermissionDump.contactsText
      .replacingOccurrences(
        of: "android.permission.READ_SMS: granted=false",
        with: "android.permission.READ_SMS: granted=\(readSMS)"
      )
      .replacingOccurrences(
        of: "android.permission.READ_CONTACTS: granted=true",
        with: "android.permission.READ_CONTACTS: granted=\(readContacts)"
      )
    return Self.result(0, stdout: text)
  }

  private static func grants(readSMS: Bool = false, readContacts: Bool = true) -> [AndroidPermissionGrant] {
    [
      PermissionDump.grant("android.permission.READ_SMS", readSMS),
      PermissionDump.grant("android.permission.POST_NOTIFICATIONS", false),
      PermissionDump.grant("android.permission.READ_CALL_LOG", true),
      PermissionDump.grant("android.permission.READ_CONTACTS", readContacts),
    ]
  }

  /// 기기 안 두 권한의 지금 값.
  private final class DeviceState: Sendable {
    let values = Mutex((readSMS: false, readContacts: true))
  }

  /// grant·revoke 를 받아 값을 바꾸고 dumpsys 로 지금 값을 돌려주는 기기 흉내. `pm` 출력은 실측대로 비고 exit 0 이다.
  private static func device(_ harness: Harness, clear: CommandResult = Self.result(0)) {
    let state = DeviceState()
    harness.adb.onApp { arguments in
      switch arguments {
      case Self.dumpsys:
        let now = state.values.withLock { $0 }
        return Self.contactsDump(readSMS: now.readSMS, readContacts: now.readContacts)
      case Self.change("grant", Self.readSMS): state.values.withLock { $0.readSMS = true }
      case Self.change("revoke", Self.readSMS): state.values.withLock { $0.readSMS = false }
      case Self.change("grant", Self.readContacts): state.values.withLock { $0.readContacts = true }
      case Self.change("revoke", Self.readContacts): state.values.withLock { $0.readContacts = false }
      case Self.clear(Self.readSMS), Self.clear(Self.readContacts): return clear
      default: return Self.result(1, stderr: "unexpected\n")
      }
      return Self.result(0)
    }
  }

  @Test("사전 확인: 꺼짐·없는 기기·SDK 없음은 명령 없이 던진다")
  func precheck() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("Pixel")
    func errors(_ client: AndroidEmulatorClientImpl, _ id: AndroidVirtualDevice.ID) async -> [AndroidEmulatorError?] {
      await [
        thrownError { _ = try await client.runtimePermissions(of: Self.contacts, on: id) },
        thrownError { _ = try await client.setRuntimePermission(Self.readSMS, granted: true, of: Self.contacts, on: id)
        },
      ]
    }
    #expect(await errors(harness.client, Self.pixel) == [.deviceNotBooted, .deviceNotBooted])
    #expect(await errors(harness.client, AndroidVirtualDevice.ID("Missing")) == [.deviceNotFound, .deviceNotFound])
    #expect(AndroidEmulatorClientImplAppTests.appCalls(harness).isEmpty)

    let noSDK = try Harness(installSDK: false)
    defer { noSDK.cleanUp() }
    #expect(await errors(noSDK.client, Self.pixel) == [.sdkUnavailable, .sdkUnavailable])
  }

  @Test("읽기: dumpsys package <패키지> 한 번, 같은 환경·10초 한도, user 0 runtime 블록 순서 그대로")
  func read() async throws {
    let harness = try AndroidEmulatorClientImplAppTests.booted()
    defer { harness.cleanUp() }
    Self.device(harness)

    let permissions = try await harness.client.runtimePermissions(of: Self.contacts, on: Self.pixel)

    #expect(permissions == .runtime(Self.grants()))
    #expect(AndroidEmulatorClientImplAppTests.appCalls(harness) == [Self.dumpsys])
    let invocation = try #require(harness.command.invocations.last)
    #expect(invocation.environment == ["HOME": FileFacts.path(harness.home), "ADB_MDNS": "0"])
    #expect(invocation.timeout == .seconds(10))
  }

  @Test("읽기: 앱 없음(exit 0 Unable to find package)·끊김·그 밖 실패")
  func readFailures() async throws {
    let harness = try AndroidEmulatorClientImplAppTests.booted()
    defer { harness.cleanUp() }
    harness.adb.onApp { _ in Self.result(0, stdout: PermissionDump.notFoundText) }
    #expect(try await harness.client.runtimePermissions(of: Self.contacts, on: Self.pixel) == .appNotInstalled)

    harness.adb.onApp { _ in Self.result(1, stderr: "adb: device offline\n") }
    #expect(
      await thrownError { _ = try await harness.client.runtimePermissions(of: Self.contacts, on: Self.pixel) }
        == .deviceNotBooted
    )

    // 합성: 대상 패키지 블록이 없는 잘린 출력.
    harness.adb.onApp { _ in Self.result(0, stdout: "Packages:\n") }
    #expect(
      await thrownError { _ = try await harness.client.runtimePermissions(of: Self.contacts, on: Self.pixel) }
        == .appCommandFailed
    )
  }

  @Test("허용: grant → dumpsys 순서, 다시 읽은 값이 허용이면 applied(다시 읽은 목록). 플래그는 지우지 않는다")
  func grant() async throws {
    let harness = try AndroidEmulatorClientImplAppTests.booted()
    defer { harness.cleanUp() }
    Self.device(harness)

    let outcome = try await harness.client.setRuntimePermission(
      Self.readSMS,
      granted: true,
      of: Self.contacts,
      on: Self.pixel
    )

    #expect(outcome == .applied(Self.grants(readSMS: true)))
    #expect(AndroidEmulatorClientImplAppTests.appCalls(harness) == [Self.change("grant", Self.readSMS), Self.dumpsys])
  }

  @Test("거부: revoke → clear-permission-flags user-set user-fixed → dumpsys 순서, applied")
  func revoke() async throws {
    let harness = try AndroidEmulatorClientImplAppTests.booted()
    defer { harness.cleanUp() }
    Self.device(harness)

    let outcome = try await harness.client.setRuntimePermission(
      Self.readContacts,
      granted: false,
      of: Self.contacts,
      on: Self.pixel
    )

    #expect(outcome == .applied(Self.grants(readContacts: false)))
    #expect(
      AndroidEmulatorClientImplAppTests.appCalls(harness)
        == [Self.change("revoke", Self.readContacts), Self.clear(Self.readContacts), Self.dumpsys]
    )
  }

  @Test("적용 안 됨: exit 0 인데 값이 그대로(미선언 권한), 목록에 없는 권한, SecurityException exit 255 는 다시 읽어 notApplied")
  func notApplied() async throws {
    let harness = try AndroidEmulatorClientImplAppTests.booted()
    defer { harness.cleanUp() }
    // grant 는 출력 없이 exit 0 인데 값을 바꾸지 않는다.
    harness.adb.onApp { arguments in arguments == Self.dumpsys ? Self.contactsDump() : Self.result(0) }
    #expect(
      try await harness.client.setRuntimePermission(Self.readSMS, granted: true, of: Self.contacts, on: Self.pixel)
        == .notApplied(Self.grants())
    )

    let camera = try #require(AndroidRuntimePermission("android.permission.CAMERA"))
    #expect(
      try await harness.client.setRuntimePermission(camera, granted: true, of: Self.contacts, on: Self.pixel)
        == .notApplied(Self.grants())
    )

    // 실측 원문(지도에 INTERNET grant, exit 255)의 앞 세 줄 (스택 줄은 뺐다). 판정은 종료 코드 255 와
    // `java.lang.SecurityException` 줄 머리만 보므로, 요청한 패키지·권한과 문구 속 이름이 달라도 된다.
    let security = """

    Exception occurred while executing 'grant':
    java.lang.SecurityException: Permission android.permission.INTERNET requested by package \
    com.google.android.apps.maps is not a changeable permission type

    """
    harness.adb.onApp { arguments in
      arguments == Self.dumpsys ? Self.contactsDump() : Self.result(255, stderr: security)
    }
    #expect(
      try await harness.client.setRuntimePermission(Self.readSMS, granted: true, of: Self.contacts, on: Self.pixel)
        == .notApplied(Self.grants())
    )
    #expect(Array(AndroidEmulatorClientImplAppTests.appCalls(harness).suffix(2)) == [
      Self.change("grant", Self.readSMS),
      Self.dumpsys,
    ])
  }

  @Test("앱 없음: grant·revoke 의 package not found 면 다시 읽지 않고, 다시 읽기의 Unable to find package 도 appNotInstalled")
  func appNotInstalled() async throws {
    let harness = try AndroidEmulatorClientImplAppTests.booted()
    defer { harness.cleanUp() }
    harness.adb.onApp { _ in
      Self.result(1, stdout: "Failure [package not found]\n", stderr: "Error: package not found\n")
    }
    #expect(
      try await harness.client.setRuntimePermission(Self.readSMS, granted: false, of: Self.contacts, on: Self.pixel)
        == .appNotInstalled
    )
    #expect(AndroidEmulatorClientImplAppTests.appCalls(harness) == [Self.change("revoke", Self.readSMS)])

    harness.adb.onApp { arguments in
      arguments == Self.dumpsys ? Self.result(0, stdout: PermissionDump.notFoundText) : Self.result(0)
    }
    #expect(
      try await harness.client.setRuntimePermission(Self.readSMS, granted: true, of: Self.contacts, on: Self.pixel)
        == .appNotInstalled
    )
  }

  @Test("거부: 플래그 지우기의 그 밖 실패는 무시하고 다시 읽는다, 끊김이면 던지고 다시 읽지 않는다")
  func clearFailures() async throws {
    let harness = try AndroidEmulatorClientImplAppTests.booted()
    defer { harness.cleanUp() }
    Self.device(
      harness,
      // 합성: 예외 머리 줄만 있는 실패 (clear-permission-flags 실패는 실측에서 보지 못했다).
      clear: Self.result(255, stderr: "Exception occurred while executing 'clear-permission-flags':\n")
    )
    #expect(
      try await harness.client.setRuntimePermission(
        Self.readContacts,
        granted: false,
        of: Self.contacts,
        on: Self.pixel
      )
        == .applied(Self.grants(readContacts: false))
    )
    #expect(AndroidEmulatorClientImplAppTests.appCalls(harness).last == Self.dumpsys)

    let offline = try AndroidEmulatorClientImplAppTests.booted()
    defer { offline.cleanUp() }
    Self.device(offline, clear: Self.result(1, stderr: "adb: device offline\n"))
    #expect(
      await thrownError {
        _ = try await offline.client.setRuntimePermission(
          Self.readContacts,
          granted: false,
          of: Self.contacts,
          on: Self.pixel
        )
      } == .deviceNotBooted
    )
    #expect(
      AndroidEmulatorClientImplAppTests.appCalls(offline)
        == [Self.change("revoke", Self.readContacts), Self.clear(Self.readContacts)]
    )
  }

  @Test("쓰기 실패: 끊김은 deviceNotBooted, 그 밖 exit ≠ 0 은 appCommandFailed (다시 읽지 않는다)")
  func changeFailures() async throws {
    let harness = try AndroidEmulatorClientImplAppTests.booted()
    defer { harness.cleanUp() }
    harness.adb.onApp { _ in Self.result(1, stderr: "adb: device offline\n") }
    #expect(
      await thrownError {
        _ = try await harness.client.setRuntimePermission(
          Self.readSMS,
          granted: true,
          of: Self.contacts,
          on: Self.pixel
        )
      } == .deviceNotBooted
    )

    // 합성: 예외 머리 줄만 있고 SecurityException·IllegalArgumentException 줄이 없는 exit 255.
    harness.adb.onApp { _ in Self.result(255, stderr: "Exception occurred while executing 'grant':\n") }
    #expect(
      await thrownError {
        _ = try await harness.client.setRuntimePermission(
          Self.readSMS,
          granted: true,
          of: Self.contacts,
          on: Self.pixel
        )
      } == .appCommandFailed
    )
    #expect(!AndroidEmulatorClientImplAppTests.appCalls(harness).contains(Self.dumpsys))
  }
}
