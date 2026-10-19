import Foundation
import Testing
@testable import SimulatorImpl

struct SimulatorAppLocatorTests {
  @Test("xcode-select 출력의 공백·개행을 자르고 개발자 디렉터리로 읽는다")
  func readsDeveloperDirectory() {
    let url = SimulatorAppLocator.developerDirectory(
      fromXcodeSelectOutput: Data("  /Applications/Xcode.app/Contents/Developer\n".utf8)
    )
    #expect(url?.path(percentEncoded: false) == "/Applications/Xcode.app/Contents/Developer/")
  }

  @Test("비었거나 절대 경로가 아니면 nil", arguments: ["", "\n", "   ", "Applications/Xcode.app", "xcode-select: error"])
  func rejectsInvalidOutput(output: String) {
    #expect(SimulatorAppLocator.developerDirectory(fromXcodeSelectOutput: Data(output.utf8)) == nil)
  }

  @Test("후보는 Developer/Applications/Simulator.app 다음 Contents/Applications/DeviceHub.app")
  func candidates() {
    let developer = URL(filePath: "/Applications/Xcode.app/Contents/Developer", directoryHint: .isDirectory)
    let paths = SimulatorAppLocator.candidates(developerDirectory: developer).map { $0.path(percentEncoded: false) }
    #expect(paths == [
      "/Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/",
      "/Applications/Xcode.app/Contents/Applications/DeviceHub.app/",
    ])
  }
}
