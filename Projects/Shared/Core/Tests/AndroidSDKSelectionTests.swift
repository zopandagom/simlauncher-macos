import Foundation
import Testing
@testable import Core

struct AndroidSDKSelectionTests: AndroidSelectionTesting {
  // MARK: - 호스트

  @Test("호스트: arm64 → aarch64·arm64-v8a, x86_64 → x64·x86_64")
  func host() {
    #expect(AndroidHostArchitecture(.arm64) == .aarch64)
    #expect(AndroidHostArchitecture(.x86_64) == .x64)
    #expect(AndroidHostArchitecture.aarch64.archiveHostArch == "aarch64")
    #expect(AndroidHostArchitecture.aarch64.systemImageABI == "arm64-v8a")
    #expect(AndroidHostArchitecture.x64.archiveHostArch == "x64")
    #expect(AndroidHostArchitecture.x64.systemImageABI == "x86_64")
  }

  // MARK: - platform-tools

  @Test("platform-tools: stable·macosx archive 중 가장 높은 revision, host-arch 없는 archive 허용", arguments: [
    AndroidHostArchitecture.aarch64, .x64,
  ])
  func platformToolsHighest(host: AndroidHostArchitecture) throws {
    let plan = try Self.plan(host: host, missing: [.platformTools])

    #expect(plan.packages.map(\.component) == [.platformTools])
    #expect(plan.packages.first?.revision == .v("37.0.1"))
    #expect(plan.packages.first?.archive.fileName == "pt-37-darwin.zip")
    #expect(plan.packages.first?.url.url.absoluteString == "https://dl.google.com/android/repository/pt-37-darwin.zip")
  }

  @Test("platform-tools: linux·windows archive 만 있으면 noCompatiblePackage")
  func platformToolsOtherOS() {
    let tools = [Fixture.tool("platform-tools", .v("37.0.1"), archives: [
      Fixture.archive("l.zip", hostOS: "linux"), Fixture.archive("w.zip", hostOS: "windows"), Fixture.archive(
        "none.zip",
        hostOS: nil
      ),
    ])]
    #expect(Self
      .problem(tools: tools + Self.emulators, missing: [.platformTools]) == .noCompatiblePackage(.platformTools))
  }

  @Test("obsolete·미리보기 revision 은 고르지 않는다")
  func skipsObsoleteAndPreview() throws {
    let tools = [
      Fixture.tool("platform-tools", .v("37.0.0"), archives: [Fixture.archive("ok.zip")]),
      Fixture.tool("platform-tools", .v("39.0.0"), obsolete: true, archives: [Fixture.archive("obsolete.zip")]),
      Fixture.tool(
        "platform-tools",
        AndroidRevision(major: 40, preview: 1),
        archives: [Fixture.archive("preview.zip")]
      ),
    ]
    let plan = try Self.plan(tools: tools, missing: [.platformTools])
    #expect(plan.packages.first?.archive.fileName == "ok.zip")
  }

  // MARK: - emulator

  @Test("emulator: 같은 path 가 dev(37.3.5)·stable(37.2.12)에 있으면 stable, host-arch 가 같은 archive", arguments: [
    (AndroidHostArchitecture.aarch64, "emu-aarch64.zip"), (.x64, "emu-x64.zip"),
  ])
  func emulatorStable(host: AndroidHostArchitecture, fileName: String) throws {
    let plan = try Self.plan(host: host, missing: [.emulator])

    #expect(plan.packages.first?.revision == .v("37.2.12"))
    #expect(plan.packages.first?.archive.fileName == fileName)
  }

  @Test("emulator: aarch64 에 x64 archive 만 있으면 고르지 않는다")
  func emulatorArchMismatch() {
    let tools = [Fixture.tool("emulator", .v("37.2.12"), archives: [Fixture.archive("emu-x64.zip", arch: "x64")])]
    #expect(Self.problem(tools: Self.platformTools + tools, missing: [.emulator]) == .noCompatiblePackage(.emulator))
  }

  @Test("host-arch 가 같은 archive 를 host-arch 없는 archive 보다 먼저 고른다")
  func prefersExactArch() throws {
    let tools = [Fixture.tool("emulator", .v("1.0.0"), archives: [
      Fixture.archive("any.zip"), Fixture.archive("exact.zip", arch: "aarch64"),
    ])]
    #expect(try Self.plan(tools: tools, missing: [.emulator]).packages.first?.archive.fileName == "exact.zip")
  }

  // MARK: - 시스템 이미지

  @Test("시스템 이미지: 호스트 abi 의 숫자 API 중 가장 높은 것 (37.0 > 36.1 > 36)", arguments: [
    (AndroidHostArchitecture.aarch64, "system-images;android-37.0;google_apis;arm64-v8a"),
    (.x64, "system-images;android-37.0;google_apis;x86_64"),
  ])
  func imageHighestAPI(host: AndroidHostArchitecture, path: String) throws {
    let plan = try Self.plan(host: host, missing: [.systemImage])

    #expect(plan.packages.map(\.path.raw) == [path])
    #expect(plan.packages.first?.url.url.absoluteString.hasPrefix(
      "https://dl.google.com/android/repository/sys-img/google_apis/"
    ) == true)
  }

  @Test("API 비교: 37.0 > 36.1 > 36 (문서 순서와 관계없이)")
  func apiOrder() throws {
    let images = [Fixture.image(api: "36"), Fixture.image(api: "36.1"), Fixture.image(api: "37.0")].shuffled()
    #expect(try Self.plan(images: images, missing: [.systemImage]).packages.first?.path.raw
      == "system-images;android-37.0;google_apis;arm64-v8a")
    let lower = [Fixture.image(api: "36"), Fixture.image(api: "36.1")]
    #expect(try Self.plan(images: lower, missing: [.systemImage]).packages.first?.path.raw
      == "system-images;android-36.1;google_apis;arm64-v8a")
  }

  @Test("tag 가 정확히 [google_apis] 하나가 아니거나, codename 이 있거나, base-extension 이 true 가 아니거나, 36x·canary·obsolete 면 제외")
  func imageExclusions() throws {
    let excluded = [
      Fixture.image(api: "39", tags: ["google_apis", "page_size_16kb"], pathTag: "google_apis_ps16k"),
      Fixture.image(api: "39", tags: ["google_apis_playstore"]),
      Fixture.image(api: "39", codename: "CANARY", pathTag: "google_apis_canary"),
      Fixture.image(api: "39", baseExtension: false, pathTag: "google_apis_ext"),
      Fixture.image(api: "39", baseExtension: nil, pathTag: "google_apis_noext"),
      Fixture.image(api: "36x", pathTag: "google_apis_36x"),
      Fixture.image(api: "39", channel: .canary, pathTag: "google_apis_c"),
      Fixture.image(api: "39", obsolete: true, pathTag: "google_apis_o"),
    ]
    let plan = try Self.plan(images: excluded + [Fixture.image(api: "30")], missing: [.systemImage])
    #expect(plan.packages.first?.path.raw == "system-images;android-30;google_apis;arm64-v8a")
    #expect(Self.problem(images: excluded, missing: [.systemImage]) == .noCompatiblePackage(.systemImage))
  }

  @Test("같은 path 가 둘이면 높은 revision")
  func duplicatePathHigherRevision() throws {
    let images = [
      Fixture.image(api: "24", revision: .v("27"), archives: [Fixture.archive("r27.zip", hostOS: nil)]),
      Fixture.image(api: "24", revision: .v("29"), archives: [Fixture.archive("r29.zip", hostOS: nil)]),
      Fixture.image(api: "24", revision: .v("28"), archives: [Fixture.archive("r28.zip", hostOS: nil)]),
    ]
    let plan = try Self.plan(images: images, missing: [.systemImage])
    #expect(plan.packages.first?.revision == .v("29"))
    #expect(plan.packages.first?.archive.fileName == "r29.zip")
  }

  @Test("시스템 이미지 archive: host-os 없음·macosx 허용, linux 는 제외")
  func imageArchiveOS() throws {
    let images = [
      Fixture.image(api: "37.0", archives: [Fixture.archive("linux.zip", hostOS: "linux")]),
      Fixture.image(api: "36", archives: [Fixture.archive("mac.zip", hostOS: "macosx")]),
    ]
    #expect(try Self.plan(images: images, missing: [.systemImage]).packages.first?.archive.fileName == "mac.zip")
  }
}
