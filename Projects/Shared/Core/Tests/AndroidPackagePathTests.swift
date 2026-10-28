import Testing
@testable import Core

struct AndroidPackagePathTests {
  @Test("; 로 나눈 구성 요소")
  func components() {
    #expect(AndroidPackagePath("system-images;android-37.0;google_apis;arm64-v8a")?.components
      == ["system-images", "android-37.0", "google_apis", "arm64-v8a"])
    #expect(AndroidPackagePath("platform-tools")?.components == ["platform-tools"])
    #expect(AndroidPackagePath("platform-tools")?.raw == "platform-tools")
  }

  @Test("빈 구성 요소·.·..·/·NUL 이 들면 nil", arguments: [
    "", ";", "a;;b", "a;", ";a", ".", "a;.;b", "..", "system-images;..;x", "a/b", "/abs", "a\0b",
  ])
  func rejects(raw: String) {
    #expect(AndroidPackagePath(raw) == nil)
  }

  @Test("최종 경로는 SDK 루트 아래 구성 요소들")
  func destination() throws {
    let root = AndroidSDKRoot(url: .init(filePath: "/sdk", directoryHint: .isDirectory), isDefault: false)
    let path = try #require(AndroidPackagePath("system-images;android-37.0;google_apis;arm64-v8a"))
    #expect(root.destination(for: path).path(percentEncoded: false)
      == "/sdk/system-images/android-37.0/google_apis/arm64-v8a/")
    #expect(root.folder(for: .platformTools).path(percentEncoded: false) == "/sdk/platform-tools/")
    #expect(AndroidSDKComponent.allCases.map(\.folderName) == ["platform-tools", "emulator", "system-images"])
  }
}
