import Foundation
import Testing
@testable import AndroidEmulatorImpl

/// adb 출력 해석과 emulator·adb 실행 인자·환경 (정확히 비교).
struct ADBCommandTests {
  @Test("adb devices: 헤더·* daemon 줄·빈 줄은 건너뛰고 emulator- serial 만, device 만 online")
  func parseDevices() {
    let output = """
    * daemon not running; starting now at tcp:5037
    * daemon started successfully
    List of devices attached
    emulator-5554\tdevice
    emulator-5556\toffline
    emulator-5558\tunauthorized
    R5CT1234ABC\tdevice

    """
    let devices = ADBCommand.parseDevices(Data(output.utf8))
    #expect(devices.map(\.serial) == ["emulator-5554", "emulator-5556", "emulator-5558"])
    #expect(devices.map(\.isOnline) == [true, false, false])
  }

  @Test("adb devices: 빈 목록과 CRLF")
  func parseEmptyDevices() {
    #expect(ADBCommand.parseDevices(Data("List of devices attached\n\n".utf8)).isEmpty)
    #expect(ADBCommand.parseDevices(Data()).isEmpty)
    let crlf = ADBCommand.parseDevices(Data("List of devices attached\r\nemulator-5554\tdevice\r\n".utf8))
    #expect(crlf.map(\.serial) == ["emulator-5554"])
    #expect(crlf.map(\.isOnline) == [true])
  }

  @Test("emu avd name: 이름 다음 OK 줄이 있어야 이름, 아니면 nil")
  func parseAVDName() {
    #expect(ADBCommand.parseAVDName(Data("Pixel_9\r\nOK\r\n".utf8)) == "Pixel_9")
    #expect(ADBCommand.parseAVDName(Data("Pixel_9\nOK\n".utf8)) == "Pixel_9")
    #expect(ADBCommand.parseAVDName(Data("Pixel_9\r\n".utf8)) == nil)
    #expect(ADBCommand.parseAVDName(Data("OK\r\n".utf8)) == nil)
    #expect(ADBCommand.parseAVDName(Data("KO: unknown command\r\nOK\r\n".utf8)) == nil)
    #expect(ADBCommand.parseAVDName(Data()) == nil)
  }

  @Test("getprop sys.boot_completed: 1 만 완료, 빈 값·0 은 아님")
  func parseBootCompleted() {
    #expect(ADBCommand.parseBootCompleted(Data("1\r\n".utf8)))
    #expect(ADBCommand.parseBootCompleted(Data("1".utf8)))
    #expect(!ADBCommand.parseBootCompleted(Data("\r\n".utf8)))
    #expect(!ADBCommand.parseBootCompleted(Data()))
    #expect(!ADBCommand.parseBootCompleted(Data("0\n".utf8)))
  }

  @Test("adb 환경은 HOME·ADB_MDNS=0 만, emulator 인자·환경은 정해진 값만")
  func argumentsAndEnvironment() {
    let home = URL(filePath: "/Users/tester/", directoryHint: .isDirectory)
    #expect(ADBCommand.environment(home: home) == ["HOME": "/Users/tester", "ADB_MDNS": "0"])
    #expect(EmulatorLaunch.arguments(name: "Pixel_9") == [
      "-avd",
      "Pixel_9",
      "-no-metrics",
      "-crash-report-mode",
      "disabled",
    ])
    #expect(EmulatorLaunch.environment(home: home) == [
      "HOME": "/Users/tester",
      "ANDROID_EMULATOR_WAIT_TIME_BEFORE_KILL": "120",
    ])
  }
}
