import Foundation
import Testing
@testable import SimulatorImpl

struct SimctlCommandTests {
  @Test("명령 경로와 인자")
  func arguments() {
    #expect(SimctlCommand.xcrun.path(percentEncoded: false) == "/usr/bin/xcrun")
    #expect(SimctlCommand.xcodeSelect.path(percentEncoded: false) == "/usr/bin/xcode-select")
    #expect(SimctlCommand.open.path(percentEncoded: false) == "/usr/bin/open")
    #expect(SimctlCommand.list() == ["simctl", "list", "-j"])
    #expect(SimctlCommand.boot(udid: "A") == ["simctl", "boot", "A"])
    #expect(SimctlCommand.shutdown(udid: "A") == ["simctl", "shutdown", "A"])
    #expect(SimctlCommand.printDeveloperDirectory() == ["-p"])
  }

  @Test("UUID 형식이 아니면 UDID 로 넘기지 않는다", arguments: ["-h", "iPhone 17", "", "booted", "0000-0000"])
  func rejectsNonUDID(raw: String) {
    #expect(SimctlCommand.validatedUDID(raw) == nil)
  }

  @Test("UDID 는 대문자로 맞춘다")
  func uppercasesUDID() {
    #expect(
      SimctlCommand.validatedUDID("0a1b2c3d-0000-4000-8000-00000000abcd") == "0A1B2C3D-0000-4000-8000-00000000ABCD"
    )
    #expect(
      SimctlCommand.validatedUDID("00000000-0000-0000-0000-000000000001") == "00000000-0000-0000-0000-000000000001"
    )
  }

  @Test("개발자 디렉터리가 있으면 DEVELOPER_DIR 로 넣고 나머지 환경은 그대로 둔다")
  func environmentWithDirectory() {
    let environment = SimctlCommand.environment(
      base: ["PATH": "/usr/bin", "DEVELOPER_DIR": "/old"],
      developerDirectory: URL(filePath: "/Applications/Xcode.app/Contents/Developer")
    )
    #expect(environment == ["PATH": "/usr/bin", "DEVELOPER_DIR": "/Applications/Xcode.app/Contents/Developer"])
  }

  @Test("개발자 디렉터리가 없으면 물려받은 DEVELOPER_DIR 를 지운다")
  func environmentWithoutDirectory() {
    let environment = SimctlCommand.environment(
      base: ["PATH": "/usr/bin", "DEVELOPER_DIR": "/old"],
      developerDirectory: nil
    )
    #expect(environment == ["PATH": "/usr/bin"])
  }
}
