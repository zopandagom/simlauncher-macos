import Foundation
import Testing
@testable import SimulatorImpl

struct SimctlConsoleCommandTests {
  @Test("launchWithConsole 은 --console-pty·--terminate-running-process 뒤에 기기·번들 ID 를 -- 없이 넘긴다")
  func arguments() {
    #expect(SimctlCommand.launchWithConsole(udid: "A", bundleID: "com.example.app") == [
      "simctl", "launch", "--console-pty", "--terminate-running-process", "A", "com.example.app",
    ])
  }

  @Test("콘솔 환경은 DEVELOPER_DIR 에 NSUnbufferedIO=YES·SIMCTL_CHILD_OS_ACTIVITY_DT_MODE=enable 을 더한다")
  func environment() {
    let developer = URL(filePath: "/X/Xcode.app/Contents/Developer")

    let environment = SimctlCommand.consoleEnvironment(base: ["PATH": "/usr/bin"], developerDirectory: developer)

    #expect(environment == [
      "PATH": "/usr/bin",
      "DEVELOPER_DIR": "/X/Xcode.app/Contents/Developer",
      "NSUnbufferedIO": "YES",
      "SIMCTL_CHILD_OS_ACTIVITY_DT_MODE": "enable",
    ])
  }

  @Test("개발자 디렉터리가 없으면 물려받은 DEVELOPER_DIR 를 지운다 (environment 와 같다)")
  func environmentWithoutDeveloperDirectory() {
    let environment = SimctlCommand.consoleEnvironment(base: ["DEVELOPER_DIR": "/old"], developerDirectory: nil)

    #expect(environment["DEVELOPER_DIR"] == nil)
    #expect(environment["NSUnbufferedIO"] == "YES")
  }
}
