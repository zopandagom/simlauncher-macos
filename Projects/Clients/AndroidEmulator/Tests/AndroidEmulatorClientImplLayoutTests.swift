import AndroidEmulatorInterface
import CommandInterface
import Core
import Foundation
import Synchronization
import Testing
@testable import AndroidEmulatorImpl

struct AndroidEmulatorClientImplLayoutTests {
  static let pixel = AndroidVirtualDevice.ID("Pixel")
  static let serial = "emulator-5554"
  static let png = ADBLayoutCommandsTests.png(width: 1080, height: 2400)
  static let xml = """
  <?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation="0">\
  <node index="0" text="" resource-id="" class="android.widget.FrameLayout" package="com.android.settings" \
  content-desc="" bounds="[0,0][1080,2400]"><node index="0" text="" resource-id="" class="android.widget.ImageButton" \
  package="com.android.settings" content-desc="Navigate up" bounds="[85,105][148,168]" /></node></hierarchy>
  """

  /// 잠금이 있고 adb 에 켜짐으로 보이는 `Pixel`(표시 이름 "Pixel 9 Pro").
  static func booted() throws -> (Harness, FakeLayoutADB) {
    let harness = try Harness()
    try harness.locks.hold(harness.addDevice("Pixel", displayName: "Pixel 9 Pro"))
    harness.adb.set(Self.serial, FakeADB.Emulator(name: "Pixel"))
    let layout = FakeLayoutADB()
    harness.adb.onApp { arguments throws(CommandError) in try layout.respond(arguments) }
    return (harness, layout)
  }

  static func layoutCalls(_ harness: Harness) -> [[String]] {
    AndroidEmulatorClientImplAppTests.appCalls(harness)
  }

  @Test("순서: 밀도 → 덤프(30초 한도) → 스크린샷(30초 한도), 노드·크기·밀도·다시 읽은 표시 이름으로 스냅샷")
  func snapshot() async throws {
    let (harness, _) = try Self.booted()
    defer { harness.cleanUp() }
    let before = Date()

    let snapshot = try await harness.client.layoutSnapshot(on: Self.pixel)

    #expect(Self.layoutCalls(harness) == [
      ["-s", Self.serial, "exec-out", "wm", "density"],
      ["-s", Self.serial, "exec-out", "uiautomator", "dump", "/dev/tty"],
      ["-s", Self.serial, "exec-out", "screencap -p 2>/dev/null"],
    ])
    let timeouts = harness.command.invocations.suffix(2).map(\.timeout)
    #expect(timeouts == [.seconds(30), .seconds(30)])
    #expect(snapshot.deviceName == "Pixel 9 Pro")
    #expect(snapshot.capturedAt >= before)
    #expect(snapshot.screenshotPNG == Self.png)
    #expect(snapshot.pixelSize == LayoutSize(width: 1080, height: 2400))
    #expect(snapshot.unit == .dp)
    #expect(snapshot.pixelsPerUnit == 2.625)
    #expect(snapshot.nodes.count == 2)
    #expect(snapshot.nodes[1].label == "Navigate up")
    #expect(snapshot.appIdentifier == "com.android.settings")
    #expect(!snapshot.isSystemScreen)
    #expect(await harness.client.layoutQueue.pendingDeviceCount == 0)
  }

  @Test("밀도를 읽지 못해도(실패·종료 코드 ≠ 0·해석 실패·시간 초과) 성공하고 pixelsPerUnit 은 nil")
  func densityFailure() async throws {
    let (harness, layout) = try Self.booted()
    defer { harness.cleanUp() }
    let failures: [Result<CommandResult, CommandError>] = [
      .success(ADBLayoutCommandsTests.result(1, stdout: "Physical density: 420\n")),
      .success(ADBLayoutCommandsTests.result(stdout: "")),
      .failure(.timedOut),
      .failure(.launchFailed),
    ]

    for failure in failures {
      layout.configure { $0.density = failure }
      let snapshot = try await harness.client.layoutSnapshot(on: Self.pixel)
      #expect(snapshot.pixelsPerUnit == nil)
      #expect(snapshot.nodes.count == 2)
    }
  }

  @Test("덤프 실패 분류: idle·화면 꺼짐·Killed·끊김·해석 실패, 시간 초과는 layoutTimedOut (스크린샷을 찍지 않는다)")
  func dumpFailures() async throws {
    let (harness, layout) = try Self.booted()
    defer { harness.cleanUp() }
    let cases: [(Result<CommandResult, CommandError>, AndroidEmulatorError)] = [
      (.success(ADBLayoutCommandsTests.result(stdout: "ERROR: could not get idle state.\n")), .layoutNotIdle),
      (
        .success(ADBLayoutCommandsTests.result(stdout: "ERROR: null root node returned by UiTestAutomationBridge.\n")),
        .layoutDisplayOff
      ),
      (.success(ADBLayoutCommandsTests.result(stdout: "Killed\n")), .layoutBusy),
      (.success(ADBLayoutCommandsTests.result(1, stderr: "error: device offline\n")), .deviceNotBooted),
      (.success(ADBLayoutCommandsTests.result(stdout: "<hierarchy><node></hierarchy>")), .layoutUnreadable),
      (.success(ADBLayoutCommandsTests.result(stdout: "garbage")), .layoutUnreadable),
      (.failure(.timedOut), .layoutTimedOut),
    ]

    for (dump, expected) in cases {
      layout.configure { $0.dump = dump }
      let error = await thrownError { _ = try await harness.client.layoutSnapshot(on: Self.pixel) }
      #expect(error == expected, "\(expected)")
      #expect(Self.layoutCalls(harness).last?.last == "/dev/tty", "\(expected)")
    }
  }

  @Test("스크린샷 실패(종료 코드 ≠ 0·PNG 아님·크기 없음·시간 초과)는 captureFailed")
  func screenshotFailures() async throws {
    let (harness, layout) = try Self.booted()
    defer { harness.cleanUp() }
    let failures: [Result<CommandResult, CommandError>] = [
      .success(CommandResult(exitCode: 1, stdout: Self.png, stderr: Data())),
      .success(ADBLayoutCommandsTests.result(stdout: "not png")),
      .success(CommandResult(exitCode: 0, stdout: Data(ADBCaptureCommands.pngSignature), stderr: Data())),
      .failure(.timedOut),
    ]

    for failure in failures {
      layout.configure { $0.screenshot = failure }
      let error = await thrownError { _ = try await harness.client.layoutSnapshot(on: Self.pixel) }
      #expect(error == .captureFailed)
    }
  }

  @Test("꺼진 기기는 명령 없이 deviceNotBooted, 없는 기기는 deviceNotFound")
  func notBooted() async throws {
    let (harness, _) = try Self.booted()
    defer { harness.cleanUp() }
    try harness.addDevice("Off")

    #expect(await thrownError { _ = try await harness.client.layoutSnapshot(on: .init("Off")) } == .deviceNotBooted)
    #expect(await thrownError { _ = try await harness.client.layoutSnapshot(on: .init("Missing")) } == .deviceNotFound)
    #expect(Self.layoutCalls(harness).isEmpty)
  }

  @Test("SDK 를 쓸 수 없으면 sdkUnavailable")
  func sdkUnavailable() async throws {
    let harness = try Harness(installSDK: false)
    defer { harness.cleanUp() }
    try harness.addDevice("Pixel")

    #expect(await thrownError { _ = try await harness.client.layoutSnapshot(on: Self.pixel) } == .sdkUnavailable)
  }

  @Test("bootedSerial 은 bootedDevice 의 serial 그대로")
  func bootedSerialMatches() async throws {
    let (harness, _) = try Self.booted()
    defer { harness.cleanUp() }
    let tools = try SDKTools.resolve(.root(AndroidSDKRoot(url: harness.sdk, isDefault: false)))

    let device = try await harness.client.bootedDevice(Self.pixel, tools: tools)
    let serial = try await harness.client.bootedSerial(Self.pixel, tools: tools)

    #expect(device.serial == Self.serial)
    #expect(serial == Self.serial)
    #expect(device.device.displayName == "Pixel 9 Pro")
  }
}

/// 기기 안 명령 흉내: 밀도·덤프·스크린샷에 정한 답을 준다.
final class FakeLayoutADB: Sendable {
  struct Config: Sendable {
    var density: Result<CommandResult, CommandError> = .success(ADBLayoutCommandsTests
      .result(stdout: "Physical density: 420\n"))
    var dump: Result<CommandResult, CommandError> = .success(ADBLayoutCommandsTests.result(
      stdout: AndroidEmulatorClientImplLayoutTests.xml + "UI hierchary dumped to: /dev/tty\n"
    ))
    var screenshot: Result<CommandResult, CommandError> = .success(
      CommandResult(exitCode: 0, stdout: AndroidEmulatorClientImplLayoutTests.png, stderr: Data())
    )
  }

  private let config = Mutex(Config())

  func configure(_ change: (inout Config) -> Void) {
    self.config.withLock { change(&$0) }
  }

  func respond(_ arguments: [String]) throws(CommandError) -> CommandResult {
    let config = self.config.withLock { $0 }
    switch Array(arguments.dropFirst(2)) {
    case ["exec-out", "wm", "density"]: return try config.density.get()
    case ["exec-out", "uiautomator", "dump", "/dev/tty"]: return try config.dump.get()
    case ["exec-out", "screencap -p 2>/dev/null"]: return try config.screenshot.get()
    default: return ADBLayoutCommandsTests.result(1)
    }
  }
}
