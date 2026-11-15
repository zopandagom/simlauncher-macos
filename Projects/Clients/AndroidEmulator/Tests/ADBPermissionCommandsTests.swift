import AndroidEmulatorInterface
import CommandInterface
import Core
import Foundation
import Testing
@testable import AndroidEmulatorImpl

/// `dumpsys package` 출력 픽스처. TC-B 실측(API 37) 덤프(연락처 95 KB·지도 261 KB·샘플 4 KB)의 줄을 그대로 옮겨 줄였다
/// (들여쓰기·절 순서·`flags=[ … ]` 형식 그대로, 줄 사이의 다른 줄만 뺐다). 테스트 안에서 이 픽스처를 바꾸거나 새로 만든 출력에는
/// 그 자리에 `합성` 이라고 적었다.
enum PermissionDump {
  static let contacts = AndroidPackageName("com.google.android.contacts")!
  static let maps = AndroidPackageName("com.google.android.apps.maps")!
  static let sample = AndroidPackageName("com.zopandagom.simlauncher.sampleapp")!

  /// 공유 uid 가 아닌 앱: 패키지 블록의 `User 0:` 아래 `runtime permissions:`. `install permissions:`(4칸)는 읽지 않는다.
  static let contactsText = """
  Activity Resolver Table:
    Full MIME Types:
        vnd.android.cursor.dir/raw_contact:
          39c41f0 com.google.android.contacts/com.android.contacts.activities.PeopleActivity filter 5efe0c6
  Domain verification status:

  Permissions:
    Permission [com.google.android.contacts.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION] (9f27b28):
      sourcePackage=com.google.android.contacts
      flags=0x0

  Packages:
    Package [com.google.android.contacts] (7314bb1):
      appId=10180
      pccId=-1
      pkg=Package{f35896 com.google.android.contacts}
      requested permissions:
        android.permission.WRITE_SETTINGS
        android.permission.READ_SMS
        android.permission.READ_CONTACTS
      install permissions:
        android.permission.WRITE_SETTINGS: granted=true
        android.permission.WAKE_LOCK: granted=true
      User 0: ceDataInode=344474 deDataInode=90574 pccCeDataInode=0 pccDeDataInode=0 installed=true hidden=false \
  suspended=false appLockEnabled=false distractionFlags=0 stopped=true notLaunched=false enabled=0 instant=false \
  virtual=false quarantined=false
        installReason=0
        dataDir=/data/user/0/com.google.android.contacts
        overlay paths:
          /product/overlay/EmulationPixel9ProFold/EmulationPixel9ProFoldOverlay.apk
        gids=[3003]
        runtime permissions:
          android.permission.READ_SMS: granted=false, flags=[ USER_SENSITIVE_WHEN_GRANTED|USER_SENSITIVE_WHEN_DENIED|\
  RESTRICTION_UPGRADE_EXEMPT]
          android.permission.POST_NOTIFICATIONS: granted=false, flags=[ USER_SENSITIVE_WHEN_GRANTED|\
  USER_SENSITIVE_WHEN_DENIED]
          android.permission.READ_CALL_LOG: granted=true, flags=[ GRANTED_BY_DEFAULT|USER_SENSITIVE_WHEN_GRANTED|\
  USER_SENSITIVE_WHEN_DENIED|RESTRICTION_SYSTEM_EXEMPT|RESTRICTION_UPGRADE_EXEMPT]
          android.permission.READ_CONTACTS: granted=true, flags=[ GRANTED_BY_DEFAULT|USER_SENSITIVE_WHEN_GRANTED|\
  USER_SENSITIVE_WHEN_DENIED]

  Queries:
    system apps queryable: false
    queryable via interaction:
      User 0:
    queryable via uses-library:

  Dexopt state:
    [com.google.android.contacts]

  """

  /// 공유 uid 앱: 패키지 블록에는 runtime 블록이 없고 `Shared users:` → `SharedUser [...]` → `User 0: `(끝 공백) 아래에 있다.
  /// `Permissions:` 절이 여러 번 나온다. 실측 덤프는 runtime 권한이 모두 거부다
  /// (이 배치에서 허용 값을 읽는 확인은 `sharedUserGranted` 가 테스트 안에서 한 줄을 바꿔 한다).
  static let mapsText = """
  Activity Resolver Table:
    Non-Data Actions:
  Permissions:
    Permission [com.google.android.apps.maps.permission.ASSISTANT_GRPC_SYNC] (1bae8e0):
      sourcePackage=com.google.android.apps.maps
  Permissions:
    Permission [com.google.android.apps.maps.permission.TIMELINE_POST_VISIT_BADGE] (75c5a5e):
      sourcePackage=com.google.android.apps.maps

  Packages:
    Package [com.google.android.apps.maps] (cef2b42):
      appId=10176
      pccId=-1
      sharedUser=SharedUserSetting{2054b28 com.google.android.apps.maps/10176}
      pkg=Package{2176041 com.google.android.apps.maps}
      install permissions:
        android.permission.WAKE_LOCK: granted=true
      User 0: ceDataInode=344447 deDataInode=90550 pccCeDataInode=0 pccDeDataInode=0 installed=true hidden=false \
  suspended=false appLockEnabled=false distractionFlags=0 stopped=true notLaunched=false enabled=1 instant=false \
  virtual=false quarantined=false
        installReason=0
        dataDir=/data/user/0/com.google.android.apps.maps
        lastDisabledCaller: com.google.android.partnersetup

  Queries:
    queryable via interaction:
      User 0:
    queryable via uses-library:

  Shared users:
    SharedUser [com.google.android.apps.maps] (2054b28):
      appId=10176
      Packages
        PackageSetting{cef2b42 com.google.android.apps.maps/10176}
      install permissions:
        android.permission.DOWNLOAD_WITHOUT_NOTIFICATION: granted=true
        com.google.android.gms.permission.AD_ID: granted=true
      User 0: \("")
        gids=[3003]
        runtime permissions:
          android.permission.POST_NOTIFICATIONS: granted=false, flags=[ USER_SENSITIVE_WHEN_GRANTED|\
  USER_SENSITIVE_WHEN_DENIED]
          android.permission.ACCESS_FINE_LOCATION: granted=false, flags=[ USER_SENSITIVE_WHEN_GRANTED|\
  USER_SENSITIVE_WHEN_DENIED]
          android.permission.BLUETOOTH_CONNECT: granted=false, flags=[ USER_SENSITIVE_WHEN_GRANTED|\
  USER_SENSITIVE_WHEN_DENIED]
          android.permission.CAMERA: granted=false, flags=[ USER_SENSITIVE_WHEN_GRANTED|\
  USER_SENSITIVE_WHEN_DENIED]
          android.permission.ACCESS_BACKGROUND_LOCATION: granted=false, flags=[ USER_SENSITIVE_WHEN_GRANTED|\
  USER_SENSITIVE_WHEN_DENIED|RESTRICTION_UPGRADE_EXEMPT]

  Dexopt state:
    [com.google.android.apps.maps]

  """

  /// 권한을 선언하지 않은 앱: `requested permissions:` 절이 없고 `runtime permissions:` 머리 줄 바로 뒤가 빈 줄이다.
  static let sampleText = """
  Activity Resolver Table:
    Non-Data Actions:
  Domain verification status:

  Key Set Manager:
    [com.zopandagom.simlauncher.sampleapp]
        Signing KeySets: 66

  Packages:
    Package [com.zopandagom.simlauncher.sampleapp] (3f27b19):
      appId=10231
      pccId=-1
      apexModuleName=null
      User 0: ceDataInode=360642 deDataInode=98805 pccCeDataInode=0 pccDeDataInode=0 installed=true hidden=false \
  suspended=false appLockEnabled=false distractionFlags=0 stopped=false notLaunched=false enabled=0 instant=false \
  virtual=false quarantined=false
        installReason=0
        dataDir=/data/user/0/com.zopandagom.simlauncher.sampleapp
        legacy overlay paths:
          /product/overlay/NavigationBarModeGestural/NavigationBarModeGesturalOverlay.apk
        runtime permissions:

  Queries:
    system apps queryable: false
    queryable via interaction:
      User 0:
        com.google.android.inputmethod.latin:
          com.zopandagom.simlauncher.sampleapp

  Dexopt state:
    [com.zopandagom.simlauncher.sampleapp]

  """

  /// 미설치 패키지 (stdout 한 줄, exit 0, 실측).
  static let notFoundText = "Unable to find package: com.google.android.contacts\n"

  static func grant(_ name: String, _ isGranted: Bool) -> AndroidPermissionGrant {
    AndroidPermissionGrant(permission: AndroidRuntimePermission(name)!, isGranted: isGranted)
  }

  static let contactsGrants = [
    grant("android.permission.READ_SMS", false),
    grant("android.permission.POST_NOTIFICATIONS", false),
    grant("android.permission.READ_CALL_LOG", true),
    grant("android.permission.READ_CONTACTS", true),
  ]

  static let mapsGrants = [
    grant("android.permission.POST_NOTIFICATIONS", false),
    grant("android.permission.ACCESS_FINE_LOCATION", false),
    grant("android.permission.BLUETOOTH_CONNECT", false),
    grant("android.permission.CAMERA", false),
    grant("android.permission.ACCESS_BACKGROUND_LOCATION", false),
  ]
}

/// 런타임 권한 adb 인자(정확한 배열)와 출력 해석. 기대 배열은 실제 기기로 확인한 명령이다 (API 37).
struct ADBPermissionCommandsTests {
  private static let serial = "emulator-5554"
  private static let camera = AndroidRuntimePermission("android.permission.CAMERA")!

  private static func result(_ code: Int32, stdout: String = "", stderr: String = "") -> CommandResult {
    CommandResult(exitCode: code, stdout: Data(stdout.utf8), stderr: Data(stderr.utf8))
  }

  private static func parse(
    _ stdout: String,
    _ package: AndroidPackageName = PermissionDump.contacts,
    code: Int32 = 0
  ) -> Result<AndroidAppPermissions, AndroidEmulatorError> {
    ADBPermissionCommands.parseRuntimePermissions(self.result(code, stdout: stdout), package: package)
  }

  // MARK: - 인자

  @Test("인자: dumpsys package, grant·revoke(권한만 작은따옴표), clear-permission-flags user-set user-fixed")
  func arguments() {
    let maps = PermissionDump.maps
    #expect(
      ADBPermissionCommands.dumpsysPackageArguments(serial: Self.serial, package: maps)
        == ["-s", "emulator-5554", "shell", "dumpsys", "package", "com.google.android.apps.maps"]
    )
    #expect(
      ADBPermissionCommands.grantArguments(serial: Self.serial, package: maps, permission: Self.camera)
        == [
          "-s",
          "emulator-5554",
          "shell",
          "pm",
          "grant",
          "com.google.android.apps.maps",
          "'android.permission.CAMERA'",
        ]
    )
    #expect(
      ADBPermissionCommands.revokeArguments(serial: Self.serial, package: maps, permission: Self.camera)
        == [
          "-s",
          "emulator-5554",
          "shell",
          "pm",
          "revoke",
          "com.google.android.apps.maps",
          "'android.permission.CAMERA'",
        ]
    )
    #expect(
      ADBPermissionCommands.clearFlagsArguments(serial: Self.serial, package: maps, permission: Self.camera)
        == [
          "-s", "emulator-5554", "shell", "pm", "clear-permission-flags", "com.google.android.apps.maps",
          "'android.permission.CAMERA'", "user-set", "user-fixed",
        ]
    )
  }

  // MARK: - dumpsys 해석

  @Test("연락처형: 패키지 블록의 User 0 runtime 블록 순서 그대로, install permissions·flags 는 보지 않는다")
  func contactsLayout() {
    #expect(Self.parse(PermissionDump.contactsText) == .success(.runtime(PermissionDump.contactsGrants)))
  }

  @Test("지도형(SharedUser): Shared users 절의 User 0 블록, Queries 의 User 0 은 무시")
  func sharedUserLayout() {
    #expect(
      Self.parse(PermissionDump.mapsText, PermissionDump.maps) == .success(.runtime(PermissionDump.mapsGrants))
    )
  }

  @Test("지도형(SharedUser) 블록의 허용 값도 읽는다")
  func sharedUserGranted() {
    // 실측 지도 덤프는 모두 거부라, CAMERA 한 줄만 허용으로 바꾼 합성 출력.
    let text = PermissionDump.mapsText.replacingOccurrences(
      of: "android.permission.CAMERA: granted=false, flags=[ USER_SENSITIVE_WHEN_GRANTED|",
      with: "android.permission.CAMERA: granted=true, flags=[ USER_SET|USER_SENSITIVE_WHEN_GRANTED|"
    )
    let expected = PermissionDump.mapsGrants.map {
      $0.permission.rawValue == "android.permission.CAMERA" ? PermissionDump.grant($0.permission.rawValue, true) : $0
    }
    #expect(text != PermissionDump.mapsText)
    #expect(Self.parse(text, PermissionDump.maps) == .success(.runtime(expected)))
  }

  @Test("샘플형: 머리 줄만 있고 비었으면 빈 목록")
  func emptyBlock() {
    #expect(Self.parse(PermissionDump.sampleText, PermissionDump.sample) == .success(.runtime([])))
  }

  @Test("Unable to find package: <그 패키지> 줄은 appNotInstalled (exit 0)")
  func notFound() {
    #expect(Self.parse(PermissionDump.notFoundText) == .success(.appNotInstalled))
    // 합성: 다른 패키지 이름이면 그 줄로 보지 않는다 (Packages 절도 없어 잘린 출력).
    #expect(Self.parse("Unable to find package: com.example.other\n") == .failure(.appCommandFailed))
  }

  @Test("Packages 절에 그 패키지 블록이 없으면 appCommandFailed (잘린 출력·다른 패키지)")
  func missingPackageBlock() {
    // 합성: 빈 출력, 실측 덤프를 다른 패키지로 읽기, Packages 절 앞에서 자른 출력.
    #expect(Self.parse("") == .failure(.appCommandFailed))
    #expect(Self.parse(PermissionDump.contactsText, PermissionDump.maps) == .failure(.appCommandFailed))
    let truncated = PermissionDump.contactsText.components(separatedBy: "Packages:\n")[0]
    #expect(Self.parse(truncated) == .failure(.appCommandFailed))
  }

  @Test("User 0 아래 runtime permissions 머리 줄이 하나도 없으면 appCommandFailed")
  func missingHeader() {
    // 합성: 샘플 픽스처에서 머리 줄을 지운 출력, User 0 을 User 10 으로 바꾼 출력.
    let text = PermissionDump.sampleText.replacingOccurrences(of: "      runtime permissions:\n", with: "")
    #expect(Self.parse(text, PermissionDump.sample) == .failure(.appCommandFailed))
    // User 10 아래에만 있으면 없는 것과 같다.
    let otherUser = PermissionDump.sampleText.replacingOccurrences(
      of: "    User 0: ceDataInode",
      with: "    User 10: ceDataInode"
    )
    #expect(Self.parse(otherUser, PermissionDump.sample) == .failure(.appCommandFailed))
  }

  @Test("User 10 블록은 무시하고 User 0 블록만 읽는다")
  func ignoresOtherUsers() {
    // 합성: 연락처 픽스처 앞에 User 10 블록을 끼운 출력 (실측은 user 0 만).
    let text = PermissionDump.contactsText.replacingOccurrences(
      of: "    User 0: ceDataInode",
      with: """
          User 10: ceDataInode=1 installed=true
            runtime permissions:
              android.permission.CAMERA: granted=true, flags=[ ]
          User 0: ceDataInode
      """
    )
    #expect(Self.parse(text) == .success(.runtime(PermissionDump.contactsGrants)))
  }

  @Test("형식 밖 이름·granted 이상값 줄은 건너뛰고, 블록은 빈 줄이나 얕은 줄에서 끝난다")
  func skipsMalformedLines() {
    // 합성: 샘플 픽스처의 빈 블록 자리에 형식 밖 줄을 섞은 블록을 넣은 출력.
    let block = """
          runtime permissions:
            android.permission.CAMERA: granted=true, flags=[ USER_SET]
            bad name;rm: granted=true, flags=[ ]
            android.permission.RECORD_AUDIO: granted=maybe, flags=[ ]
            android.permission.READ_CONTACTS: granted=false
            android..EMPTY: granted=true
          gids=[3003]
            android.permission.AFTER_BLOCK: granted=true

    """
    let text = PermissionDump.sampleText.replacingOccurrences(of: "      runtime permissions:\n", with: block)
    #expect(
      Self.parse(text, PermissionDump.sample) == .success(.runtime([
        PermissionDump.grant("android.permission.CAMERA", true),
        PermissionDump.grant("android.permission.READ_CONTACTS", false),
      ]))
    )
  }

  @Test("같은 이름이 두 블록에 있으면 뒤의 값을 앞 자리에 둔다")
  func duplicateLaterWins() {
    // 합성: 패키지 블록과 Shared users 블록 둘 다 있는 출력 (실측에서는 한쪽뿐).
    let text = PermissionDump.mapsText.replacingOccurrences(
      of: "      lastDisabledCaller: com.google.android.partnersetup\n",
      with: """
            lastDisabledCaller: com.google.android.partnersetup
            runtime permissions:
              android.permission.CAMERA: granted=true, flags=[ ]
              android.permission.READ_SMS: granted=true, flags=[ ]

      """
    )
    // 앞(패키지 블록) CAMERA 는 허용, 뒤(Shared users 블록)는 거부 → 뒤의 거부가 앞 자리에 온다.
    let expected = [
      PermissionDump.grant("android.permission.CAMERA", false),
      PermissionDump.grant("android.permission.READ_SMS", true),
    ]
      + PermissionDump.mapsGrants.filter { $0.permission.rawValue != "android.permission.CAMERA" }
    #expect(Self.parse(text, PermissionDump.maps) == .success(.runtime(expected)))
  }

  @Test("줄 끝 CRLF 도 읽는다")
  func crlf() {
    // 합성: 연락처 픽스처의 줄 끝을 CRLF 로 바꾼 출력.
    let text = PermissionDump.contactsText.replacingOccurrences(of: "\n", with: "\r\n")
    #expect(Self.parse(text) == .success(.runtime(PermissionDump.contactsGrants)))
  }

  @Test("종료 코드 ≠ 0: 켜는 중·끊김 출력이면 deviceNotBooted, 그 밖 appCommandFailed")
  func failures() {
    let offline = ADBPermissionCommands.parseRuntimePermissions(
      Self.result(1, stderr: "adb: device offline\n"),
      package: PermissionDump.contacts
    )
    #expect(offline == .failure(.deviceNotBooted))
    // 합성: 켜는 중 문구가 없는 종료 코드 ≠ 0.
    #expect(Self.parse(PermissionDump.contactsText, code: 1) == .failure(.appCommandFailed))
  }

  @Test("부팅 중 exit 0: Can't find service 는 deviceNotBooted, Permission Denial 은 appCommandFailed (실측 원문)")
  func bootingWithExitZero() {
    let noService = ADBPermissionCommands.parseRuntimePermissions(
      Self.result(0, stderr: "Can't find service: package\n"),
      package: PermissionDump.contacts
    )
    #expect(noService == .failure(.deviceNotBooted))
    let denial = ADBPermissionCommands.parseRuntimePermissions(
      Self.result(
        0,
        stdout: "Permission Denial: can't dump PackageManager from from pid=701, uid=2000 due to missing "
          + "android.permission.DUMP permission\n"
      ),
      package: PermissionDump.contacts
    )
    #expect(denial == .failure(.appCommandFailed))
  }

  @Test("부팅 중 exit 0: Can't find service 는 서비스 이름·stdout/stderr 와 상관없이 deviceNotBooted (합성)")
  func bootingAnyService() {
    // 합성: 다른 서비스 이름을 stdout 에.
    let other = ADBPermissionCommands.parseRuntimePermissions(
      Self.result(0, stdout: "Can't find service: activity\n"),
      package: PermissionDump.contacts
    )
    #expect(other == .failure(.deviceNotBooted))
  }

  // MARK: - grant·revoke·clear 해석

  @Test("변경 해석: 성공(출력 없음 exit 0), package not found exit 1, 예외 exit 255, 끊김, 그 밖")
  func parseChange() {
    #expect(ADBPermissionCommands.parseChange(Self.result(0)) == .success(.ran))
    #expect(
      ADBPermissionCommands.parseChange(
        Self.result(1, stdout: "Failure [package not found]\n", stderr: "Error: package not found\n")
      ) == .success(.appNotInstalled)
    )
    // 합성: stderr 줄만으로도 판정한다 (실측은 stdout·stderr 두 줄이 함께 나온다).
    #expect(
      ADBPermissionCommands
        .parseChange(Self.result(1, stderr: "Error: package not found\n")) == .success(.appNotInstalled)
    )
    // 앞 세 줄은 실측 원문(지도에 INTERNET grant), `\tat` 스택 줄은 합성 (실측 스택은 옮기지 않았다).
    let security = """

    Exception occurred while executing 'grant':
    java.lang.SecurityException: Permission android.permission.INTERNET requested by package \
    com.google.android.apps.maps is not a changeable permission type
    \tat com.android.server.pm.permission.PermissionManagerServiceImpl.grantRuntimePermissionInternal(\
    PermissionManagerServiceImpl.java:1457)

    """
    #expect(ADBPermissionCommands.parseChange(Self.result(255, stderr: security)) == .success(.ran))
    // 셋째 줄까지는 실측 원문(없는 권한 FOO), `\tat` 스택 줄은 합성.
    let unknown = """

    Exception occurred while executing 'grant':
    java.lang.IllegalArgumentException: Unknown permission android.permission.FOO
    \tat com.android.server.pm.permission.PermissionManagerServiceImpl.grantRuntimePermissionInternal(\
    PermissionManagerServiceImpl.java:1420)

    """
    #expect(ADBPermissionCommands.parseChange(Self.result(255, stderr: unknown)) == .success(.ran))
    #expect(ADBPermissionCommands
      .parseChange(Self.result(1, stderr: "adb: device offline\n")) == .failure(.deviceNotBooted))
    // 합성: 예외 머리 줄만 있는 exit 255, 예외 줄이 있어도 종료 코드가 255 가 아닌 출력.
    #expect(
      ADBPermissionCommands.parseChange(Self.result(255, stderr: "Exception occurred while executing 'grant':\n"))
        == .failure(.appCommandFailed)
    )
    #expect(ADBPermissionCommands
      .parseChange(Self.result(1, stderr: "java.lang.SecurityException: x\n")) == .failure(.appCommandFailed))
  }
}

/// 권한 이름 검증.
struct ADBPermissionNameTests {
  // MARK: - 권한 이름

  @Test(
    "권한 이름: ASCII 영숫자·_ 조각을 . 로 이은 2조각 이상, 1~255자",
    arguments: [
      ("android.permission.CAMERA", true),
      ("com.google.android.gms.permission.AD_ID", true),
      ("a.b", true),
      ("a_1.B_2", true),
      ("CAMERA", false),
      ("", false),
      ("android..CAMERA", false),
      (".android.CAMERA", false),
      ("android.CAMERA.", false),
      ("android.permission.CAMERA'", false),
      ("android.permission.CA MERA", false),
      ("android.permission.CAMERA;id", false),
      ("android.permission.카메라", false),
      ("android-x.CAMERA", false),
    ]
  )
  func permissionName(_ raw: String, _ valid: Bool) {
    #expect((AndroidRuntimePermission(raw) != nil) == valid)
  }

  @Test("권한 이름 길이 경계: 255자 통과, 256자 거절, 비교는 rawValue 순")
  func permissionLength() throws {
    let head = "a."
    #expect(AndroidRuntimePermission(head + String(repeating: "b", count: 253)) != nil)
    #expect(AndroidRuntimePermission(head + String(repeating: "b", count: 254)) == nil)
    #expect(try #require(AndroidRuntimePermission("a.A")) < AndroidRuntimePermission("a.B")!)
  }
}
