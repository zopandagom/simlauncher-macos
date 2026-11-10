import Core
import Foundation
import SimulatorInterface
import Testing
@testable import SimulatorImpl

/// `simctl listapps` 출력(OpenStep plist) 해석. 픽스처는 실제 출력의 키·값 모양을 따라 직접 만든 것이다 (경로·사용자 이름 없음).
struct SimctlAppListDecoderTests {
  private static func sample() throws -> [InstalledApp] {
    try SimctlAppListDecoder.apps(from: Fixture.data("listapps-sample", withExtension: "txt"))
  }

  private static func app(_ raw: String, in apps: [InstalledApp]) throws -> InstalledApp {
    let id = try #require(AppBundleID(raw))
    return try #require(apps.first { $0.bundleID == id })
  }

  @Test("User 앱만 표시 이름 자연 순서 → 번들 ID 순으로 읽는다 (System·형식 밖 키·사전 아닌 값·종류 없음은 뺀다)")
  func userAppsInOrder() throws {
    let apps = try Self.sample()

    #expect(apps.map(\.bundleID.rawValue) == [
      "com.example.app2",
      "com.example.lower",
      "com.example.app10",
      "com.example.beta",
      "com.example.noname",
      "com.example.twin.a",
      "com.example.twin.b",
    ])
  }

  @Test("이름은 CFBundleDisplayName → CFBundleName → 번들 ID 순으로 비지 않은 값")
  func displayName() throws {
    let apps = try Self.sample()

    #expect(try Self.app("com.example.beta", in: apps).displayName == "Beta")
    #expect(try Self.app("com.example.app2", in: apps).displayName == "App2")
    #expect(try Self.app("com.example.noname", in: apps).displayName == "com.example.noname")
  }

  @Test("버전·빌드는 있으면 읽고, 없거나 빈 값이면 nil")
  func versionAndBuild() throws {
    let apps = try Self.sample()

    let beta = try Self.app("com.example.beta", in: apps)
    #expect(beta.version == "2.1")
    #expect(beta.build == "45")
    let app10 = try Self.app("com.example.app10", in: apps)
    #expect(app10.version == "1.0")
    #expect(app10.build == nil)
    let app2 = try Self.app("com.example.app2", in: apps)
    #expect(app2.version == nil)
    #expect(app2.build == "7")
    let twin = try Self.app("com.example.twin.a", in: apps)
    #expect(twin.version == nil)
    #expect(twin.build == nil)
  }

  @Test("같은 표시 이름의 두 앱은 둘 다 남고 번들 ID 순이다")
  func sameDisplayName() throws {
    let twins = try Self.sample().filter { $0.displayName == "Twin" }

    #expect(twins.map(\.bundleID.rawValue) == ["com.example.twin.a", "com.example.twin.b"])
  }

  @Test("이름은 대소문자와 상관없이 숫자를 자연 순서로 비교한다")
  func naturalOrder() throws {
    let names = try Self.sample().map(\.displayName)

    #expect(Array(names.prefix(4)) == ["App2", "app3", "App10", "Beta"])
  }

  @Test("SimLauncher 레이아웃 러너는 User 앱이어도 빼고, 다른 UI 테스트 러너는 남긴다")
  func excludesLayoutRunner() throws {
    let text = """
    {
        "\(IOSLayoutRunner.appBundleID)" =     {
            ApplicationType = User;
            CFBundleDisplayName = "SimLauncherLayout-Runner";
        };
        "com.example.uitests.xctrunner" =     {
            ApplicationType = User;
            CFBundleDisplayName = "ExampleUITests-Runner";
        };
    }
    """

    let apps = try SimctlAppListDecoder.apps(from: Data(text.utf8))

    #expect(apps.map(\.bundleID.rawValue) == ["com.example.uitests.xctrunner"])
  }

  @Test("빈 사전은 빈 목록")
  func emptyDictionary() throws {
    #expect(try SimctlAppListDecoder.apps(from: Data("{}".utf8)).isEmpty)
  }

  @Test(
    "plist 가 아니거나 최상위가 사전이 아니면 unexpectedOutput",
    arguments: ["( a, b )", "{ a = ", "", "plain", "\"com.example.app\""]
  )
  func unexpectedOutput(text: String) {
    #expect(throws: SimulatorError.unexpectedOutput) {
      try SimctlAppListDecoder.apps(from: Data(text.utf8))
    }
  }
}
