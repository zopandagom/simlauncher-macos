import AndroidEmulatorInterface
import CommandInterface
import CommandTesting
import Core
import Foundation
import Testing
@testable import AndroidEmulatorImpl

/// 켜진 기기의 앱 작업: 다시 읽기로 켜짐을 확인한 뒤에만 앱 명령을 보낸다. adb 는 흉내(`FakeADB.onApp`).
struct AndroidEmulatorClientImplAppTests {
  static let pixel = AndroidVirtualDevice.ID("Pixel")
  static let package = AndroidPackageName("org.videolan.vlc")!
  static let apk = URL(filePath: "/Users/tester/Downloads/app.apk")

  /// 잠금이 있고 adb 에 켜짐으로 보이는 `Pixel` (emulator-5554).
  static func booted() throws -> Harness {
    let harness = try Harness()
    try harness.locks.hold(harness.addDevice("Pixel"))
    harness.adb.set("emulator-5554", FakeADB.Emulator(name: "Pixel"))
    return harness
  }

  static func result(_ code: Int32, stdout: String = "", stderr: String = "") -> CommandResult {
    CommandResult(exitCode: code, stdout: Data(stdout.utf8), stderr: Data(stderr.utf8))
  }

  /// launcher 가 둘 이상일 때 `resolve-activity --brief` 출력 (실측).
  static let chooser = Self.result(
    0,
    stdout: "priority=0 preferredOrder=0 match=0x0 specificIndex=-1 isDefault=false\n" +
      "android/com.android.internal.app.ResolverActivity\n"
  )

  /// launcher 둘의 `query-activities --brief` 출력 (실측, 패키지만 바꿨다). 순서는 manifest 순서다.
  static let twoLaunchers = """
  2 activities found:
    Activity #0:
      priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=false
      org.videolan.vlc/android.app.Activity
    Activity #1:
      priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=false
      org.videolan.vlc/android.app.ListActivity

  """

  /// 목록 읽기(`devices`·`emu avd name`·`sys.boot_completed`)를 뺀 adb 호출.
  static func appCalls(_ harness: Harness) -> [[String]] {
    harness.adbCalls.filter { arguments in
      arguments != ["devices"]
        && Array(arguments.dropFirst(2)) != ["emu", "avd", "name"]
        && Array(arguments.dropFirst(2)) != ["shell", "getprop", "sys.boot_completed"]
    }
  }

  /// 다섯 메서드를 차례로 불러 던진 에러를 모은다.
  static func allErrors(_ client: AndroidEmulatorClientImpl, _ id: AndroidVirtualDevice.ID) async throws
    -> [AndroidEmulatorError?]
  {
    let link = try #require(DeepLink("https://example.com"))
    return await [
      thrownError { _ = try await client.deviceTraits(id) },
      thrownError { try await client.install(Self.apk, on: id) },
      thrownError { try await client.launch(Self.package, on: id) },
      thrownError { try await client.openURL(link, on: id) },
      thrownError { _ = try await client.installedPackages(on: id) },
    ]
  }

  // MARK: - 사전 확인

  @Test("꺼진 기기·켜는 중(boot_completed 아님)·잠금은 있는데 adb 에 아직 없음: 앱 명령 없이 deviceNotBooted")
  func rejectsNotBooted() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("Pixel")
    try harness.locks.hold(harness.addDevice("Booting"))
    harness.adb.set("emulator-5554", FakeADB.Emulator(name: "Booting", bootCompleted: false))
    try harness.locks.hold(harness.addDevice("Starting"))

    for name in ["Pixel", "Booting", "Starting"] {
      let errors = try await Self.allErrors(harness.client, AndroidVirtualDevice.ID(name))
      #expect(errors == Array(repeating: .deviceNotBooted, count: 5), "\(name)")
    }
    #expect(Self.appCalls(harness).isEmpty)
  }

  @Test("잠금이 있는데 adb devices 가 실패하면 adbUnavailable")
  func rejectsWhenADBFails() async throws {
    let harness = try Self.booted()
    defer { harness.cleanUp() }
    harness.adb.setDevicesFail(true)

    let errors = try await Self.allErrors(harness.client, Self.pixel)
    #expect(errors == Array(repeating: .adbUnavailable, count: 5))
    #expect(Self.appCalls(harness).isEmpty)
  }

  @Test("쓸 수 없는 기기는 deviceUnavailable, 없는 기기는 deviceNotFound, SDK 가 없으면 sdkUnavailable")
  func rejectsUnavailable() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.locks.hold(harness.addDevice("My Phone"))
    harness.adb.set("emulator-5554", FakeADB.Emulator(name: "My Phone"))

    let unavailable = try await Self.allErrors(harness.client, AndroidVirtualDevice.ID("My Phone"))
    #expect(unavailable == Array(repeating: .deviceUnavailable(.unsupportedName), count: 5))
    let missing = try await Self.allErrors(harness.client, Self.pixel)
    #expect(missing == Array(repeating: .deviceNotFound, count: 5))
    #expect(Self.appCalls(harness).isEmpty)

    let noSDK = try Harness(installSDK: false)
    defer { noSDK.cleanUp() }
    #expect(try await Self.allErrors(noSDK.client, Self.pixel) == Array(repeating: .sdkUnavailable, count: 5))
  }

  // MARK: - 값 읽기

  @Test("deviceTraits: getprop 두 번 (SDK 의 adb, HOME·ADB_MDNS=0, 10초 한도)")
  func deviceTraits() async throws {
    let harness = try Self.booted()
    defer { harness.cleanUp() }
    harness.adb.onApp { arguments in
      switch arguments.last {
      case "ro.build.version.sdk": Self.result(0, stdout: "37\r\n")
      case "ro.product.cpu.abilist": Self.result(0, stdout: "arm64-v8a\r\n")
      default: Self.result(1)
      }
    }

    #expect(try await harness.client.deviceTraits(Self.pixel) == AndroidDeviceTraits(apiLevel: 37, abis: ["arm64-v8a"]))
    #expect(Self.appCalls(harness) == [
      ["-s", "emulator-5554", "shell", "getprop", "ro.build.version.sdk"],
      ["-s", "emulator-5554", "shell", "getprop", "ro.product.cpu.abilist"],
    ])
    let invocation = try #require(harness.command.invocations.last)
    #expect(invocation.executable.path(percentEncoded: false) == FileFacts.path(harness.sdk) + "/platform-tools/adb")
    #expect(invocation.environment == ["HOME": FileFacts.path(harness.home), "ADB_MDNS": "0"])
    #expect(invocation.isCancellable)
    #expect(invocation.timeout == .seconds(10))
  }

  @Test("deviceTraits: 값을 읽지 못하면 deviceNotBooted")
  func deviceTraitsUnreadable() async throws {
    let harness = try Self.booted()
    defer { harness.cleanUp() }
    harness.adb.onApp { _ in Self.result(0, stdout: "\r\n") }

    #expect(await thrownError { _ = try await harness.client.deviceTraits(Self.pixel) } == .deviceNotBooted)
  }
}

extension AndroidEmulatorClientImplAppTests {
  // MARK: - 설치

  @Test("install: 옵션·경로 인자, 600초 한도, 같은 환경. Success 면 성공")
  func install() async throws {
    let harness = try Self.booted()
    defer { harness.cleanUp() }
    harness.adb.onApp { _ in Self.result(0, stdout: "Performing Streamed Install\r\nSuccess\r\n") }

    try await harness.client.install(Self.apk, on: Self.pixel)

    #expect(Self.appCalls(harness) == [
      ["-s", "emulator-5554", "install", "-r", "-t", "-d", "--no-incremental", "/Users/tester/Downloads/app.apk"],
    ])
    let invocation = try #require(harness.command.invocations.last)
    #expect(invocation.environment == ["HOME": FileFacts.path(harness.home), "ADB_MDNS": "0"])
    #expect(invocation.isCancellable)
    #expect(invocation.timeout == .seconds(600))
    #expect(AndroidEmulatorClientImpl.Timing.standard.installTimeout == .seconds(600))
  }

  @Test("install: 실패 코드는 installFailed, 시간 초과는 installTimedOut, 취소는 cancelled, 시작 실패는 adbUnavailable")
  func installFailures() async throws {
    let harness = try Self.booted()
    defer { harness.cleanUp() }
    let client = harness.client

    harness.adb.onApp { _ in
      Self.result(
        1,
        stderr: "adb: failed to install /x/a.apk: Failure [INSTALL_FAILED_OLDER_SDK: Requires newer sdk]\n"
      )
    }
    #expect(await thrownError { try await client.install(Self.apk, on: Self.pixel) } == .installFailed(.olderSDK))
    harness.adb.onApp { _ throws(CommandError) in throw .timedOut }
    #expect(await thrownError { try await client.install(Self.apk, on: Self.pixel) } == .installTimedOut)
    harness.adb.onApp { _ throws(CommandError) in throw .cancelled }
    #expect(await thrownError { try await client.install(Self.apk, on: Self.pixel) } == .cancelled)
    harness.adb.onApp { _ throws(CommandError) in throw .launchFailed }
    #expect(await thrownError { try await client.install(Self.apk, on: Self.pixel) } == .adbUnavailable)
  }

  @Test("앱 명령의 시간 초과는 installTimedOut 이 아니라 adbUnavailable")
  func appCommandTimeout() async throws {
    let harness = try Self.booted()
    defer { harness.cleanUp() }
    harness.adb.onApp { _ throws(CommandError) in throw .timedOut }

    #expect(await thrownError { _ = try await harness.client.installedPackages(on: Self.pixel) } == .adbUnavailable)
  }

  // MARK: - 실행

  @Test("launch: resolve 한 component 를 인용해 am start -n 으로 실행한다")
  func launch() async throws {
    let harness = try Self.booted()
    defer { harness.cleanUp() }
    harness.adb.onApp { arguments in
      if arguments.contains("resolve-activity") {
        return Self.result(0, stdout: "priority=0 preferredOrder=0\norg.videolan.vlc/.StartActivity\n")
      }
      return Self.result(0, stdout: "Starting: Intent { cmp=org.videolan.vlc/.StartActivity }\n")
    }

    try await harness.client.launch(Self.package, on: Self.pixel)

    #expect(Self.appCalls(harness) == [
      [
        "-s", "emulator-5554", "shell", "cmd", "package", "resolve-activity", "--brief",
        "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER", "org.videolan.vlc",
      ],
      ["-s", "emulator-5554", "shell", "am", "start", "-n", "'org.videolan.vlc/.StartActivity'"],
    ])
    #expect(!Self.appCalls(harness).contains { $0.contains("query-activities") })
    #expect(harness.command.invocations.last?.timeout == .seconds(10))
  }

  @Test("launch: 기기가 고르기 화면을 돌려주면(launcher 둘 이상) query-activities 의 첫 화면을 실행한다 (실측 출력)")
  func launchAmbiguous() async throws {
    let harness = try Self.booted()
    defer { harness.cleanUp() }
    harness.adb.onApp { arguments in
      if arguments.contains("resolve-activity") {
        return Self.chooser
      }
      if arguments.contains("query-activities") {
        return Self.result(0, stdout: Self.twoLaunchers)
      }
      return Self.result(0, stdout: "Starting: Intent { cmp=org.videolan.vlc/android.app.Activity }\n")
    }

    try await harness.client.launch(Self.package, on: Self.pixel)

    #expect(Self.appCalls(harness) == [
      [
        "-s", "emulator-5554", "shell", "cmd", "package", "resolve-activity", "--brief",
        "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER", "org.videolan.vlc",
      ],
      [
        "-s", "emulator-5554", "shell", "cmd", "package", "query-activities", "--brief",
        "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER", "org.videolan.vlc",
      ],
      ["-s", "emulator-5554", "shell", "am", "start", "-n", "'org.videolan.vlc/android.app.Activity'"],
    ])
  }

  @Test("launch: 고르기 화면 뒤 query 가 비면 pm path 로 가리고, 켜는 중이면 am start 없이 deviceNotBooted")
  func launchAmbiguousFailures() async throws {
    let harness = try Self.booted()
    defer { harness.cleanUp() }
    let client = harness.client
    for (code, expected) in [(Int32(1), AndroidLaunchFailure.notInstalled), (0, .noLauncherActivity)] {
      harness.adb.onApp { arguments in
        if arguments.contains("resolve-activity") {
          return Self.chooser
        }
        if arguments.contains("query-activities") {
          return Self.result(0, stdout: "No activities found\n")
        }
        return Self.result(code)
      }
      #expect(await thrownError { try await client.launch(Self.package, on: Self.pixel) } == .launchFailed(expected))
    }
    harness.adb.onApp { arguments in
      arguments.contains("resolve-activity")
        ? Self.chooser
        : Self.result(20, stderr: "cmd: Can't find service: package\n")
    }
    #expect(await thrownError { try await client.launch(Self.package, on: Self.pixel) } == .deviceNotBooted)

    let calls = Self.appCalls(harness)
    #expect(calls.count == 8)
    #expect(calls[2] == ["-s", "emulator-5554", "shell", "pm", "path", "org.videolan.vlc"])
    #expect(!calls.contains { $0.contains("am") })
  }

  @Test("launch: 화면이 없으면 pm path 로 가린다 (rc 1 → notInstalled, rc 0 → noLauncherActivity)")
  func launchWithoutActivity() async throws {
    let harness = try Self.booted()
    defer { harness.cleanUp() }
    let client = harness.client
    for (code, expected) in [(Int32(1), AndroidLaunchFailure.notInstalled), (0, .noLauncherActivity)] {
      harness.adb.onApp { arguments in
        arguments.contains("resolve-activity") ? Self.result(0, stdout: "No activity found\n") : Self.result(code)
      }
      #expect(await thrownError { try await client.launch(Self.package, on: Self.pixel) } == .launchFailed(expected))
    }
    let calls = Self.appCalls(harness)
    #expect(calls.count == 4)
    #expect(calls[1] == ["-s", "emulator-5554", "shell", "pm", "path", "org.videolan.vlc"])
    #expect(!calls.contains { $0.contains("am") })
  }

  @Test("launch: 실행 중 끊기면 deviceNotBooted")
  func launchDisconnected() async throws {
    let harness = try Self.booted()
    defer { harness.cleanUp() }
    harness.adb.onApp { arguments in
      arguments.contains("resolve-activity")
        ? Self.result(0, stdout: "org.videolan.vlc/.StartActivity\n")
        : Self.result(1, stderr: "adb: device 'emulator-5554' not found\n")
    }

    #expect(await thrownError { try await harness.client.launch(Self.package, on: Self.pixel) } == .deviceNotBooted)
  }

  // MARK: - 링크·앱 목록

  @Test("openURL: 링크를 인용해 VIEW 로 연다, 받을 앱이 없으면 urlNotHandled")
  func openURL() async throws {
    let harness = try Self.booted()
    defer { harness.cleanUp() }
    let link = try #require(DeepLink("https://example.com/a?b=1&c=2"))
    harness.adb.onApp { _ in Self.result(0, stdout: "Starting: Intent { act=android.intent.action.VIEW }\n") }

    try await harness.client.openURL(link, on: Self.pixel)
    #expect(Self.appCalls(harness) == [
      [
        "-s", "emulator-5554", "shell", "am", "start", "-a", "android.intent.action.VIEW",
        "-d", "'https://example.com/a?b=1&c=2'",
      ],
    ])

    harness.adb.onApp { _ in
      Self.result(
        1,
        stderr: "Error: Activity not started, unable to resolve Intent { act=android.intent.action.VIEW }\n"
      )
    }
    #expect(await thrownError { try await harness.client.openURL(link, on: Self.pixel) } == .urlNotHandled)
  }

  @Test("installedPackages: pm list packages -3 의 이름순")
  func installedPackages() async throws {
    let harness = try Self.booted()
    defer { harness.cleanUp() }
    harness.adb.onApp { _ in Self.result(0, stdout: "package:org.videolan.vlc\npackage:com.b.app\n") }

    let names = try await harness.client.installedPackages(on: Self.pixel)
    #expect(names.map(\.rawValue) == ["com.b.app", "org.videolan.vlc"])
    #expect(Self.appCalls(harness) == [["-s", "emulator-5554", "shell", "pm", "list", "packages", "-3"]])
  }
}
