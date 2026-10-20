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

  @Test("create 는 이름 앞에 -- 를 두고, delete·erase 는 -- 없이 UDID 만 넘긴다")
  func mutationArguments() {
    #expect(SimctlCommand.create(name: "iPhone", deviceTypeID: "T", runtimeID: "R") == [
      "simctl", "create", "--", "iPhone", "T", "R",
    ])
    #expect(SimctlCommand.create(name: "-h", deviceTypeID: "T", runtimeID: "R") == [
      "simctl", "create", "--", "-h", "T", "R",
    ])
    #expect(SimctlCommand.delete(udid: "A") == ["simctl", "delete", "A"])
    #expect(SimctlCommand.erase(udid: "A") == ["simctl", "erase", "A"])
  }

  @Test("install·launch·openurl 은 -- 없이 기기 뒤에 경로·번들 ID·링크를 넘긴다")
  func appArguments() {
    #expect(SimctlCommand.install(udid: "A", appPath: "/tmp/공백 경로/한글 앱.app") == [
      "simctl", "install", "A", "/tmp/공백 경로/한글 앱.app",
    ])
    #expect(SimctlCommand.launch(udid: "A", bundleID: "com.example.app") == [
      "simctl", "launch", "A", "com.example.app",
    ])
    #expect(SimctlCommand.openURL(udid: "A", url: "myapp://item/1") == ["simctl", "openurl", "A", "myapp://item/1"])
  }

  @Test("create stdout 의 UDID 를 읽고 대문자로 맞춘다")
  func createdUDID() {
    #expect(
      SimctlCommand.createdUDID(fromStdout: Data("B66201ED-154C-4F97-A6C7-C88F42E8D3A7\n".utf8))
        == "B66201ED-154C-4F97-A6C7-C88F42E8D3A7"
    )
    #expect(
      SimctlCommand.createdUDID(fromStdout: Data(" b66201ed-154c-4f97-a6c7-c88f42e8d3a7 \n".utf8))
        == "B66201ED-154C-4F97-A6C7-C88F42E8D3A7"
    )
  }

  @Test(
    "create stdout 이 UDID 하나가 아니면 nil",
    arguments: [
      "",
      "\n",
      "Unable to create a device for device type: iPhone 17\n",
      "B66201ED-154C-4F97-A6C7-C88F42E8D3A7\nB66201ED-154C-4F97-A6C7-C88F42E8D3A8\n",
    ]
  )
  func createdUDIDRejects(stdout: String) {
    #expect(SimctlCommand.createdUDID(fromStdout: Data(stdout.utf8)) == nil)
    #expect(SimctlCommand.createdUDID(fromStdout: Data([0xFF, 0xFE])) == nil)
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
