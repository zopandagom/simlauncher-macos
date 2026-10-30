import AndroidEmulatorInterface
import CommandInterface
import Core
import Foundation
import Testing
@testable import AndroidEmulatorImpl

/// 앱 작업 adb 인자(정확히 비교)와 출력 해석. 출력은 설계 실측 원문에서 사용자 경로만 바꿨다.
struct ADBAppCommandsTests {
  static let serial = "emulator-5554"
  static let package = AndroidPackageName("com.android.camera2")!
  static let apkPath = "/Users/tester/Downloads/app.apk"

  /// 성공이면 nil, 실패면 그 에러.
  static func failure(_ result: Result<Void, AndroidEmulatorError>) -> AndroidEmulatorError? {
    if case let .failure(error) = result {
      return error
    }
    return nil
  }

  static func result(_ code: Int32, stdout: String = "", stderr: String = "") -> CommandResult {
    CommandResult(exitCode: code, stdout: Data(stdout.utf8), stderr: Data(stderr.utf8))
  }

  /// `adb install` 실패 줄 (stderr, 경로 포함).
  static func installFailure(_ detail: String) -> CommandResult {
    self.result(
      1,
      stdout: "Performing Streamed Install\n",
      stderr: "adb: failed to install \(self.apkPath): \(detail)\n"
    )
  }

  // MARK: - 인자

  @Test("인자: getprop 두 번, install 옵션, resolve·query·pm path·list 는 인용 없이, am start 의 component·링크는 인용")
  func arguments() throws {
    let traits = ADBAppCommands.traitsArguments(serial: Self.serial)
    #expect(traits.apiLevel == ["-s", "emulator-5554", "shell", "getprop", "ro.build.version.sdk"])
    #expect(traits.abis == ["-s", "emulator-5554", "shell", "getprop", "ro.product.cpu.abilist"])

    let apk = URL(filePath: "/Users/tester/내 파일/it's app.apk")
    #expect(ADBAppCommands.installArguments(serial: Self.serial, apk: apk) == [
      "-s", "emulator-5554", "install", "-r", "-t", "-d", "--no-incremental", "/Users/tester/내 파일/it's app.apk",
    ])
    #expect(ADBAppCommands.resolveArguments(serial: Self.serial, package: Self.package) == [
      "-s", "emulator-5554", "shell", "cmd", "package", "resolve-activity", "--brief",
      "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER", "com.android.camera2",
    ])
    #expect(ADBAppCommands.launchersArguments(serial: Self.serial, package: Self.package) == [
      "-s", "emulator-5554", "shell", "cmd", "package", "query-activities", "--brief",
      "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER", "com.android.camera2",
    ])
    #expect(ADBAppCommands.packagePathArguments(serial: Self.serial, package: Self.package) == [
      "-s", "emulator-5554", "shell", "pm", "path", "com.android.camera2",
    ])
    #expect(ADBAppCommands.startArguments(serial: Self.serial, component: "org.videolan.vlc/.Start$Inner") == [
      "-s", "emulator-5554", "shell", "am", "start", "-n", "'org.videolan.vlc/.Start$Inner'",
    ])
    let link = try #require(DeepLink("https://e.com/x?q=it's&c=2;id"))
    #expect(ADBAppCommands.openURLArguments(serial: Self.serial, link: link) == [
      "-s", "emulator-5554", "shell", "am", "start", "-a", "android.intent.action.VIEW",
      "-d", #"'https://e.com/x?q=it'\''s&c=2;id'"#,
    ])
    #expect(ADBAppCommands.listPackagesArguments(serial: Self.serial) == [
      "-s", "emulator-5554", "shell", "pm", "list", "packages", "-3",
    ])
  }

  // MARK: - getprop

  @Test("getprop: 앞뒤 공백·CRLF 를 뺀 정수, 쉼표로 나눈 ABI (순서 그대로), 빈 값·숫자 아님·실패는 deviceNotBooted")
  func traits() throws {
    #expect(try ADBAppCommands.parseAPILevel(Self.result(0, stdout: "37\r\n")).get() == 37)
    #expect(try ADBAppCommands.parseABIs(Self.result(0, stdout: "arm64-v8a,armeabi-v7a\r\n")).get() == [
      "arm64-v8a", "armeabi-v7a",
    ])
    #expect(try ADBAppCommands.parseABIs(Self.result(0, stdout: "x86_64,,x86\n")).get() == ["x86_64", "x86"])

    for bad in [Self.result(0, stdout: "\r\n"), Self.result(0, stdout: "Baklava\n"), Self.result(1)] {
      #expect(throws: AndroidEmulatorError.deviceNotBooted) { try ADBAppCommands.parseAPILevel(bad).get() }
    }
    for bad in [Self.result(0, stdout: "\r\n"), Self.result(0, stdout: ",\n"), Self.result(1, stdout: "arm64-v8a")] {
      #expect(throws: AndroidEmulatorError.deviceNotBooted) { try ADBAppCommands.parseABIs(bad).get() }
    }
  }

  // MARK: - install

  @Test("install: 종료 코드 0 과 Success 줄이면 성공, 0 인데 Success 가 없으면 other(nil)")
  func installSuccess() {
    let success = Self.result(0, stdout: "Performing Streamed Install\r\nSuccess\r\n")
    #expect(Self.failure(ADBAppCommands.parseInstall(success)) == nil)
    #expect(Self.failure(ADBAppCommands.parseInstall(Self.result(0, stdout: "Performing Streamed Install\n")))
      == .installFailed(.other(nil)))
    #expect(Self.failure(ADBAppCommands.parseInstall(Self.result(1, stdout: "Success\n")))
      == .installFailed(.other(nil)))
  }

  @Test(
    "install: Failure [<코드> 를 표로 바꾼다 (실측 출력)",
    arguments: [
      (
        "Failure [INSTALL_FAILED_VERSION_DOWNGRADE: Downgrade detected: Update version code 1 is older than current 2]",
        AndroidInstallFailure.versionDowngrade
      ),
      (
        """
        Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE: Existing package dev.slm.probe signatures do not match newer \
        version; ignoring!]
        """,
        .updateIncompatible
      ),
      ("Failure [INSTALL_FAILED_OLDER_SDK: Requires newer sdk version #99 (current version is #37)]", .olderSDK),
      (
        """
        Failure [INSTALL_FAILED_NO_MATCHING_ABIS: INSTALL_FAILED_NO_MATCHING_ABIS: Failed to extract native \
        libraries, res=-113]
        """,
        .noMatchingABIs
      ),
      ("Failure [INSTALL_FAILED_TEST_ONLY: Failed to install test-only apk. Did you forget to add -t?]", .testOnly),
      (
        """
        Failure [INSTALL_PARSE_FAILED_NO_CERTIFICATES: Failed to collect certificates from \
        /data/app/vmdl123.tmp/base.apk: Attempt to get length of null array]
        """,
        .noCertificates
      ),
      (
        """
        Failure [INSTALL_PARSE_FAILED_NO_CERTIFICATES: Failed to collect certificates from \
        /data/app/vmdl1.tmp/base.apk using APK Signature Scheme v3: SHA-256 digest of contents did not verify]
        """,
        .noCertificates
      ),
      (
        """
        Failure [INSTALL_PARSE_FAILED_NOT_APK: Failed to parse /data/app/vmdl1.tmp/base.apk: Failed to load asset \
        path /data/app/vmdl1.tmp/base.apk]
        """,
        .notAPK
      ),
      (
        """
        Failure [INSTALL_FAILED_DEPRECATED_SDK_VERSION: App package must target at least SDK version 24, but found \
        22]
        """,
        .deprecatedSDK
      ),
      ("Failure [INSTALL_FAILED_SHARED_USER_INCOMPATIBLE: x]", .updateIncompatible),
      ("Failure [INSTALL_FAILED_INVALID_APK: x]", .notAPK),
      ("Failure [INSTALL_FAILED_INSUFFICIENT_STORAGE]", .insufficientStorage),
      ("Failure [INSTALL_FAILED_DUPLICATE_PERMISSION: x]", .conflict),
      ("Failure [INSTALL_FAILED_CONFLICTING_PROVIDER: x]", .conflict),
      ("Failure [INSTALL_FAILED_MISSING_SHARED_LIBRARY: x]", .missingSharedLibrary),
      ("Failure [INSTALL_FAILED_MISSING_SPLIT]", .missingSplit),
      ("Failure [INSTALL_FAILED_X]", .other("INSTALL_FAILED_X")),
      ("Failure [INSTALL_FAILED_ABORTED: User rejected permissions]", .other("INSTALL_FAILED_ABORTED")),
      ("Failure [-110]", .other(nil)),
      ("Failure [install_failed_lower: x]", .other(nil)),
      ("Failure []", .other(nil)),
    ]
  )
  func installFailureCodes(detail: String, expected: AndroidInstallFailure) {
    #expect(Self.failure(ADBAppCommands.parseInstall(Self.installFailure(detail))) == .installFailed(expected))
  }

  @Test("install: 경로에 Failure [ 가 있어도 adb 문구의 마지막 코드를 쓴다")
  func installFailureCodeAfterPath() {
    let result = Self.result(
      1,
      stderr: "adb: failed to install /Users/t/Failure [INSTALL_FAILED_OLDER_SDK]/a.apk: Failure " +
        "[INSTALL_FAILED_TEST_ONLY: x]\n"
    )
    #expect(Self.failure(ADBAppCommands.parseInstall(result)) == .installFailed(.testOnly))
  }

  @Test(
    "install: 켜는 중·끊김 adb 문구는 deviceNotBooted (실측)",
    arguments: [
      "adb: device offline",
      "adb: device 'emulator-5554' not found",
      "adb: failed to install /Users/tester/Downloads/app.apk: cmd: Can't find service: package",
      "adb: failed to install /Users/tester/Downloads/app.apk: Error: device is still booting.",
      "adb: failed to run abb_exec. Error: closed",
      "adb: failed to install /Users/tester/Downloads/app.apk: Error: device offline",
    ]
  )
  func installNotBooted(stderr: String) {
    #expect(Self.failure(ADBAppCommands.parseInstall(Self.result(1, stderr: stderr + "\n"))) == .deviceNotBooted)
  }

  @Test("install: 경로에 closed·not found 가 든 다른 실패는 deviceNotBooted 가 아니다, .apk 아님 문구는 notAPK")
  func installOtherFailures() {
    let missing = Self.result(
      1,
      stderr: "adb: failed to stat /Users/t/closed-beta/not found/Error closed/a.apk: No such file or directory\n"
    )
    #expect(Self.failure(ADBAppCommands.parseInstall(missing)) == .installFailed(.other(nil)))
    let device = Self.result(1, stderr: "adb: failed to stat /Users/t/adb: device 'x' not found.apk: No such file\n")
    #expect(Self.failure(ADBAppCommands.parseInstall(device)) == .installFailed(.other(nil)))
    let notAPK = Self.result(1, stderr: "adb: filename doesn't end .apk or .apex: /Users/t/app.aab\n")
    #expect(Self.failure(ADBAppCommands.parseInstall(notAPK)) == .installFailed(.notAPK))
    #expect(Self.failure(ADBAppCommands.parseInstall(Self.result(1))) == .installFailed(.other(nil)))
  }

  // MARK: - resolve·query·pm path

  @Test("resolve: <패키지>/ 로 시작하고 공백이 없으면 component, No activity found 면 none, 다른 패키지면 ambiguous, 그 밖은 실패")
  func resolve() throws {
    let alias = Self.result(
      0,
      stdout: "priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=false\n" +
        "com.android.camera2/com.android.camera.CameraLauncher\n"
    )
    #expect(try ADBAppCommands.parseResolve(alias, package: Self.package).get()
      == .component("com.android.camera2/com.android.camera.CameraLauncher"))
    let vlc = try #require(AndroidPackageName("org.videolan.vlc"))
    let short = Self.result(0, stdout: "priority=0 preferredOrder=0\r\norg.videolan.vlc/.StartActivity\r\n")
    #expect(try ADBAppCommands.parseResolve(short, package: vlc).get() == .component("org.videolan.vlc/.StartActivity"))
    #expect(try ADBAppCommands.parseResolve(Self.result(0, stdout: "No activity found\n"), package: Self.package).get()
      == ADBAppCommands.ResolvedLauncher.none)

    // launcher 가 둘 이상이면 기기의 고르기 화면 (실측). 접두어가 같은 다른 패키지도 그 패키지로 읽지 않는다.
    let chooser = Self.result(
      0,
      stdout: "priority=0 preferredOrder=0 match=0x0 specificIndex=-1 isDefault=false\n" +
        "android/com.android.internal.app.ResolverActivity\n"
    )
    #expect(try ADBAppCommands.parseResolve(chooser, package: Self.package).get() == .ambiguous)
    let other = Self.result(0, stdout: "priority=0\ncom.android.camera2x/.Main\n")
    #expect(try ADBAppCommands.parseResolve(other, package: Self.package).get() == .ambiguous)

    let spaced = Self.result(0, stdout: "com.android.camera2/.Main extra\n")
    #expect(throws: AndroidEmulatorError.appCommandFailed) {
      try ADBAppCommands.parseResolve(spaced, package: Self.package).get()
    }
    #expect(throws: AndroidEmulatorError.appCommandFailed) {
      try ADBAppCommands.parseResolve(Self.result(0), package: Self.package).get()
    }
    let booting = Self.result(20, stderr: "cmd: Can't find service: package\n")
    #expect(throws: AndroidEmulatorError.deviceNotBooted) {
      try ADBAppCommands.parseResolve(booting, package: Self.package).get()
    }
  }

  @Test("query: <패키지>/ component 줄을 순서대로, No activities found 면 빈 목록, 그 밖은 실패 (실측)")
  func launchers() throws {
    let found = [
      "2 activities found:",
      "  Activity #0:",
      "    priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=false",
      "    com.android.camera2/android.app.Activity",
      "  Activity #1:",
      "    priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=false",
      "    com.android.camera2/android.app.ListActivity",
    ]
    let expected = ["com.android.camera2/android.app.Activity", "com.android.camera2/android.app.ListActivity"]
    for separator in ["\n", "\r\n"] {
      let result = Self.result(0, stdout: found.joined(separator: separator) + separator)
      #expect(try ADBAppCommands.parseLaunchers(result, package: Self.package).get() == expected)
    }
    let none = Self.result(0, stdout: "No activities found\n")
    #expect(try ADBAppCommands.parseLaunchers(none, package: Self.package).get().isEmpty)

    let other = Self.result(0, stdout: "1 activities found:\n  Activity #0:\n    com.android.camera2x/.Main\n")
    #expect(throws: AndroidEmulatorError.appCommandFailed) {
      try ADBAppCommands.parseLaunchers(other, package: Self.package).get()
    }
    #expect(throws: AndroidEmulatorError.appCommandFailed) {
      try ADBAppCommands.parseLaunchers(Self.result(0), package: Self.package).get()
    }
    let booting = Self.result(20, stderr: "cmd: Can't find service: package\n")
    #expect(throws: AndroidEmulatorError.deviceNotBooted) {
      try ADBAppCommands.parseLaunchers(booting, package: Self.package).get()
    }
  }
}

extension ADBAppCommandsTests {
  // MARK: - pm path

  @Test("pm path: 0 설치됨, 1 없음, 끊김은 deviceNotBooted, 그 밖 appCommandFailed")
  func packagePath() throws {
    let installed = Self.result(0, stdout: "package:/data/app/~~x/com.android.camera2-1/base.apk\n")
    #expect(try ADBAppCommands.parsePackagePath(installed).get() == true)
    #expect(try ADBAppCommands.parsePackagePath(Self.result(1)).get() == false)
    #expect(throws: AndroidEmulatorError.deviceNotBooted) {
      try ADBAppCommands.parsePackagePath(Self.result(1, stderr: "adb: device 'emulator-5554' not found\n")).get()
    }
    #expect(throws: AndroidEmulatorError.appCommandFailed) {
      try ADBAppCommands.parsePackagePath(Self.result(255)).get()
    }
  }

  // MARK: - am start

  @Test("am start: 성공·이미 떠 있음은 성공, Error 줄·받을 앱 없음·켜는 중은 실패 (실측)")
  func start() {
    let started = Self.result(0, stdout: "Starting: Intent { cmp=org.videolan.vlc/.StartActivity }\n")
    #expect(Self.failure(ADBAppCommands.parseStart(started)) == nil)
    let delivered = Self.result(
      0,
      stdout: "Starting: Intent { cmp=x/.Main }\nWarning: Activity not started, intent has been delivered to " +
        "currently running top-most instance.\n"
    )
    #expect(Self.failure(ADBAppCommands.parseStart(delivered)) == nil)

    let missing = Self.result(
      1,
      stdout: "Starting: Intent { cmp=x/.Gone }\n",
      stderr: "Error type 3\nError: Activity class {x/x.Gone} does not exist.\n"
    )
    #expect(Self.failure(ADBAppCommands.parseStart(missing)) == .appCommandFailed)
    let unresolved = Self.result(
      1,
      stdout: "Starting: Intent { act=android.intent.action.VIEW dat=myapp://item/... }\n",
      stderr: "Error: Activity not started, unable to resolve Intent { act=android.intent.action.VIEW " +
        "dat=myapp://item/... flg=0x10000000 }\n"
    )
    #expect(Self.failure(ADBAppCommands.parseStart(unresolved)) == .urlNotHandled)
    let tooEarly = Self.result(
      255,
      stderr: "Exception occurred while executing 'start':\njava.lang.IllegalStateException: Too early to start " +
        "activity.\n\tat com.android.server.am.X.y(X.java:1)\n"
    )
    #expect(Self.failure(ADBAppCommands.parseStart(tooEarly)) == .deviceNotBooted)
    let noService = Self.result(20, stderr: "cmd: Can't find service: activity\n")
    #expect(Self.failure(ADBAppCommands.parseStart(noService)) == .deviceNotBooted)
    let gone = Self.result(1, stderr: "adb: device 'emulator-5554' not found\n")
    #expect(Self.failure(ADBAppCommands.parseStart(gone)) == .deviceNotBooted)
    let errorWithZero = Self.result(0, stderr: "Error: something\n")
    #expect(Self.failure(ADBAppCommands.parseStart(errorWithZero)) == .appCommandFailed)
  }

  // MARK: - pm list packages

  @Test("pm list packages -3: package: 줄만, 형식 틀린 이름은 건너뛰고 이름순·중복 없음, 실패는 분류")
  func packages() throws {
    let output = "package:org.videolan.vlc\r\npackage:com.b.app\ngarbage\npackage:not valid\npackage:\n" +
      "package:com.b.app\n"
    let names = try ADBAppCommands.parsePackages(Self.result(0, stdout: output)).get()
    #expect(names.map(\.rawValue) == ["com.b.app", "org.videolan.vlc"])
    #expect(try ADBAppCommands.parsePackages(Self.result(0)).get().isEmpty)
    #expect(throws: AndroidEmulatorError.deviceNotBooted) {
      try ADBAppCommands.parsePackages(Self.result(1, stderr: "adb: device offline\n")).get()
    }
    #expect(throws: AndroidEmulatorError.appCommandFailed) {
      try ADBAppCommands.parsePackages(Self.result(1)).get()
    }
  }
}
