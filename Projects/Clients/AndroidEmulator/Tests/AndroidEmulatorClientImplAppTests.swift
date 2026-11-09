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

  /// 목록 읽기(`devices`·`emu avd name`·`sys.boot_completed`)를 뺀 adb 호출.
  static func appCalls(_ harness: Harness) -> [[String]] {
    harness.adbCalls.filter { arguments in
      arguments != ["devices"]
        && Array(arguments.dropFirst(2)) != ["emu", "avd", "name"]
        && Array(arguments.dropFirst(2)) != ["shell", "getprop", "sys.boot_completed"]
    }
  }

  /// 다섯 메서드(실행은 `launchWithLogcat`)를 차례로 불러 던진 에러를 모은다.
  static func allErrors(_ client: AndroidEmulatorClientImpl, _ id: AndroidVirtualDevice.ID) async throws
    -> [AndroidEmulatorError?]
  {
    let link = try #require(DeepLink("https://example.com"))
    return await [
      thrownError { _ = try await client.deviceTraits(id) },
      thrownError { try await client.install(Self.apk, on: id) },
      thrownError { _ = try await client.launchWithLogcat(Self.package, on: id) { _ in } },
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
