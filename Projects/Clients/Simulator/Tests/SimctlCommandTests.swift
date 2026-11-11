import Foundation
import Testing
@testable import SimulatorImpl

struct SimctlCommandTests {
  /// 화면이 둘인 기기(iPhone Duo)에서 화면을 고르지 않았을 때의 stderr (실측 Xcode 27.2).
  static let chooseDisplay = "An error was encountered processing the command (domain=NSPOSIXErrorDomain, code=22):\n"
    + "Cannot choose between 2 displays. Specify one with --display:\n"
    + "    --display=3  LCD-1 (primary-1) 2007x2853\n"
    + "    --display=1  LCD (primary) 1398x2034\n"
    + "Invalid argument\n"

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

  @Test("실행 중 앱 목록은 기기 안 launchctl list, 앱 지우기는 기기·번들 ID 를 -- 없이 넘긴다")
  func layoutArguments() {
    #expect(SimctlCommand.spawnLaunchctlList(udid: "A") == ["simctl", "spawn", "A", "launchctl", "list"])
    #expect(SimctlCommand.uninstall(udid: "A", bundleID: "com.example.app") == [
      "simctl", "uninstall", "A", "com.example.app",
    ])
  }

  @Test("listapps 는 -- 없이 기기만 넘긴다")
  func listAppsArguments() {
    #expect(SimctlCommand.listApps(udid: "A") == ["simctl", "listapps", "A"])
  }

  @Test("screenshot 은 기기 뒤에 io screenshot 과 옵션, 마지막에 경로를 넘긴다")
  func screenshotArguments() {
    #expect(SimctlCommand.screenshot(udid: "A", path: "/P/한글 (1).png") == [
      "simctl", "io", "A", "screenshot", "--type=png", "--mask=ignored", "/P/한글 (1).png",
    ])
  }

  @Test("화면을 고를 때는 --display 를 경로·--force 앞에 넣는다")
  func displayArguments() {
    #expect(SimctlCommand.screenshot(udid: "A", path: "/P/a.png", display: SimctlCommand.displayOption) == [
      "simctl", "io", "A", "screenshot", "--type=png", "--mask=ignored", "--display=primary", "/P/a.png",
    ])
    #expect(SimctlCommand.recordVideo(udid: "A", path: "/M/a.mov", display: SimctlCommand.displayOption) == [
      "simctl", "io", "A", "recordVideo", "--codec=h264", "--mask=ignored", "--display=primary", "--force", "/M/a.mov",
    ])
  }

  @Test("화면 고르기 실패는 종료 코드 22 와 줄 머리 'Cannot choose between ' 이 함께일 때만이다")
  func needsDisplay() {
    #expect(SimctlCommand.needsDisplay(exitCode: 22, stderr: Self.chooseDisplay))
    #expect(SimctlCommand.needsDisplay(exitCode: 22, stderr: "  Cannot choose between 3 displays.\r\n"))
    #expect(!SimctlCommand.needsDisplay(exitCode: 1, stderr: Self.chooseDisplay))
    #expect(!SimctlCommand.needsDisplay(exitCode: 22, stderr: "Invalid argument\n"))
    // 경로(기기 이름)에 같은 글자가 줄 중간에 나와도 아니다.
    #expect(!SimctlCommand.needsDisplay(exitCode: 22, stderr: "Wrote to /P/Cannot choose between .png\n"))
  }

  @Test("recordVideo 는 기기 뒤에 io recordVideo 와 h264·사각 전체 화면·덮어쓰기 옵션, 마지막에 경로를 넘긴다")
  func recordVideoArguments() {
    #expect(SimctlCommand.recordVideo(udid: "A", path: "/M/한글 (1).mov") == [
      "simctl", "io", "A", "recordVideo", "--codec=h264", "--mask=ignored", "--force",
      "/M/한글 (1).mov",
    ])
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
