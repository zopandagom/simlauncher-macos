import AndroidEmulatorInterface
import CommandInterface
import Core
import Foundation
import Testing
@testable import AndroidEmulatorImpl

struct ADBLayoutCommandsTests {
  static func result(_ code: Int32 = 0, stdout: String = "", stderr: String = "") -> CommandResult {
    CommandResult(exitCode: code, stdout: Data(stdout.utf8), stderr: Data(stderr.utf8))
  }

  /// 시그니처 + IHDR 머리(너비·높이) + 자리 채움. 크기 읽기에 필요한 앞 24바이트 이상.
  static func png(width: UInt32, height: UInt32) -> Data {
    var data = Data(ADBCaptureCommands.pngSignature)
    data.append(contentsOf: [0x00, 0x00, 0x00, 0x0D])
    data.append(contentsOf: Array("IHDR".utf8))
    for value in [width, height] {
      data.append(contentsOf: withUnsafeBytes(of: value.bigEndian, Array.init))
    }
    data.append(contentsOf: [0x08, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    return data
  }

  static let xml = """
  <?xml version='1.0' encoding='UTF-8' standalone='yes' ?><hierarchy rotation="0"><node index="0" text="" \
  class="android.widget.FrameLayout" package="com.android.settings" bounds="[0,0][1080,2400]" /></hierarchy>
  """

  // MARK: - 인자

  @Test("덤프·밀도 인자는 exec-out 과 고정 명령 (파일을 쓰지 않는다)")
  func arguments() {
    #expect(ADBLayoutCommands.dumpArguments(serial: "emulator-5554")
      == ["-s", "emulator-5554", "exec-out", "uiautomator", "dump", "/dev/tty"])
    #expect(ADBLayoutCommands.densityArguments(serial: "emulator-5554")
      == ["-s", "emulator-5554", "exec-out", "wm", "density"])
  }

  // MARK: - 밀도

  @Test("밀도: Physical 만 있으면 그 값, Override 가 있으면 Override (실측 출력)")
  func density() {
    #expect(ADBLayoutCommands.parseDensity(Data("Physical density: 390\n".utf8)) == 390)
    #expect(ADBLayoutCommands.parseDensity(Data("Physical density: 390\nOverride density: 300\n".utf8)) == 300)
    #expect(ADBLayoutCommands.parseDensity(Data("Physical density: 420\r\n".utf8)) == 420)
  }

  @Test("밀도: 빈 값·숫자 아님·0 이하는 nil, 깨진 Override 는 Physical 로")
  func densityInvalid() {
    #expect(ADBLayoutCommands.parseDensity(Data()) == nil)
    #expect(ADBLayoutCommands.parseDensity(Data("Physical density: abc\n".utf8)) == nil)
    #expect(ADBLayoutCommands.parseDensity(Data("Physical density: 0\n".utf8)) == nil)
    #expect(ADBLayoutCommands.parseDensity(Data("Physical density: -5\n".utf8)) == nil)
    #expect(ADBLayoutCommands.parseDensity(Data("Physical density: 420\nOverride density: x\n".utf8)) == 420)
    #expect(ADBLayoutCommands.parseDensity(Data("cmd: Can't find service: window\n".utf8)) == nil)
  }

  // MARK: - 덤프 판정

  @Test("성공: 첫 </hierarchy> 까지 자르고 꼬리 문구는 버린다")
  func dumpSuccess() throws {
    let output = Self.xml + "UI hierchary dumped to: /dev/tty\n"

    let data = try ADBLayoutCommands.classifyDump(Self.result(stdout: output)).get()

    #expect(String(bytes: data, encoding: .utf8) == Self.xml)
  }

  @Test("종료 코드가 0 이 아니어도 </hierarchy> 가 있으면 성공")
  func dumpSuccessNonZero() throws {
    let data = try ADBLayoutCommands.classifyDump(Self.result(1, stdout: Self.xml)).get()

    #expect(String(bytes: data, encoding: .utf8) == Self.xml)
  }

  @Test("</hierarchy> 가 꼬리 문구보다 앞에만 있으면 그 앞까지 (뒤 문구에 같은 글자가 있어도)")
  func dumpFirstEnd() throws {
    let output = Self.xml + "UI hierchary dumped to: /dev/tty\n</hierarchy>junk"

    let data = try ADBLayoutCommands.classifyDump(Self.result(stdout: output)).get()

    #expect(String(bytes: data, encoding: .utf8) == Self.xml)
  }

  @Test("종료 코드 0 실패 문구: idle 실패·null root·Killed (실측)")
  func dumpFailuresWithZeroExit() {
    #expect(ADBLayoutCommands.classifyDump(Self.result(stdout: "ERROR: could not get idle state.\n"))
      == .failure(.layoutNotIdle))
    #expect(ADBLayoutCommands.classifyDump(
      Self.result(stdout: "ERROR: null root node returned by UiTestAutomationBridge.\n")
    ) == .failure(.layoutDisplayOff))
    #expect(ADBLayoutCommands.classifyDump(Self.result(stdout: "Killed\n")) == .failure(.layoutBusy))
    #expect(ADBLayoutCommands.classifyDump(Self.result(137, stderr: "Killed")) == .failure(.layoutBusy))
  }

  @Test("종료 코드 ≠ 0 이고 끊김 문구면 deviceNotBooted")
  func dumpDisconnected() {
    #expect(ADBLayoutCommands.classifyDump(Self.result(1, stderr: "error: device offline\n"))
      == .failure(.deviceNotBooted))
    #expect(ADBLayoutCommands.classifyDump(Self.result(1, stderr: "error: device 'emulator-5554' not found\n"))
      == .failure(.deviceNotBooted))
    #expect(ADBLayoutCommands.classifyDump(Self.result(1, stderr: "error: no devices/emulators found\n"))
      == .failure(.deviceNotBooted))
  }

  @Test("그 밖은 layoutUnreadable (끊김 문구라도 종료 코드 0, 잘린 XML, 빈 출력)")
  func dumpUnreadable() {
    #expect(ADBLayoutCommands.classifyDump(Self.result()) == .failure(.layoutUnreadable))
    #expect(ADBLayoutCommands.classifyDump(Self.result(stdout: "error: device offline\n"))
      == .failure(.layoutUnreadable))
    #expect(ADBLayoutCommands.classifyDump(Self.result(stdout: "<?xml version='1.0' ?><hierarchy rotation=\"0\"><node"))
      == .failure(.layoutUnreadable))
    #expect(ADBLayoutCommands.classifyDump(Self.result(1, stderr: "something else\n")) == .failure(.layoutUnreadable))
    #expect(ADBLayoutCommands.classifyDump(Self.result(stdout: "Killed by user? no\n")) == .failure(.layoutUnreadable))
  }

  // MARK: - PNG 크기

  @Test("PNG 크기: IHDR 의 너비·높이 (big-endian)")
  func pngSize() {
    #expect(ADBLayoutCommands.pngPixelSize(Self.png(width: 1080, height: 2400)) == LayoutSize(
      width: 1080,
      height: 2400
    ))
    #expect(ADBLayoutCommands.pngPixelSize(Self.png(width: 2076, height: 2152)) == LayoutSize(
      width: 2076,
      height: 2152
    ))
  }

  @Test("PNG 크기: 짧은 데이터·PNG 아님·IHDR 아님·0 크기는 nil")
  func pngSizeInvalid() {
    let png = Self.png(width: 1080, height: 2400)
    #expect(ADBLayoutCommands.pngPixelSize(png.prefix(23)) == nil)
    #expect(ADBLayoutCommands.pngPixelSize(Data("not a png at all, not at all".utf8)) == nil)
    var notIHDR = png
    notIHDR[12] = 0x58
    #expect(ADBLayoutCommands.pngPixelSize(notIHDR) == nil)
    #expect(ADBLayoutCommands.pngPixelSize(Self.png(width: 0, height: 2400)) == nil)
    #expect(ADBLayoutCommands.pngPixelSize(Self.png(width: 1080, height: 0)) == nil)
  }
}
