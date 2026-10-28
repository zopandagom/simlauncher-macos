import Foundation
import Testing
@testable import Core

struct AndroidSDKSelectionPlanTests: AndroidSelectionTesting {
  // MARK: - emulator 의존

  @Test("이미지의 emulator min-revision 이 이번에 설치할 emulator 보다 높으면 다음 API 로 내려간다")
  func emulatorDependencyFromPlan() throws {
    let images = [
      Fixture.image(api: "37.0", emulator: .v("37.3.0")),
      Fixture.image(api: "36.1", emulator: .v("37.2.11")),
    ]
    let plan = try Self.plan(images: images)
    #expect(plan.packages.map(\.revision) == [.v("37.0.1"), .v("37.2.12"), .v("1")])
    #expect(plan.packages.last?.path.raw == "system-images;android-36.1;google_apis;arm64-v8a")
  }

  @Test("emulator 를 설치하지 않으면 설치된 revision 과 비교하고, 모르면 의존을 만족한 것으로 본다")
  func emulatorDependencyFromInstalled() throws {
    let images = [Fixture.image(api: "37.0", emulator: .v("37.3.0")), Fixture.image(api: "36")]
    #expect(try Self.plan(images: images, missing: [.systemImage], installedEmulator: .v("37.2.0")).packages.first?.path
      .raw
      == "system-images;android-36;google_apis;arm64-v8a")
    #expect(try Self.plan(images: images, missing: [.systemImage], installedEmulator: .v("37.3.0")).packages.first?.path
      .raw
      == "system-images;android-37.0;google_apis;arm64-v8a")
    #expect(try Self.plan(images: images, missing: [.systemImage], installedEmulator: nil).packages.first?.path.raw
      == "system-images;android-37.0;google_apis;arm64-v8a")
  }

  @Test("의존을 만족하는 이미지가 없으면 noCompatiblePackage(.systemImage)")
  func emulatorDependencyNone() {
    let images = [Fixture.image(api: "37.0", emulator: .v("99.0.0"))]
    #expect(Self.problem(images: images, missing: [.systemImage], installedEmulator: .v("37.2.12"))
      == .noCompatiblePackage(.systemImage))
  }

  // MARK: - 계획

  @Test("missing 에 없는 구성 요소는 계획에서 빠지고, 순서는 platform-tools → emulator → 시스템 이미지")
  func missingFilters() throws {
    #expect(try Self.plan(missing: [.systemImage, .platformTools]).packages.map(\.component) == [
      .platformTools,
      .systemImage,
    ])
    #expect(try Self.plan(missing: []).isEmpty)
    let all = try Self.plan()
    #expect(all.packages.map(\.component) == [.platformTools, .emulator, .systemImage])
    #expect(all.root == Fixture.root)
    #expect(all.sdkVolumeName == "Macintosh HD")
    #expect(all.sameVolumeAsDownloads)
    #expect(all.downloadBytes == 300)
    #expect(all.estimatedInstallBytes == 900)
  }

  @Test("첫 문제 하나: 구성 요소 순서로")
  func firstProblem() {
    #expect(Self.problem(tools: [], images: []) == .noCompatiblePackage(.platformTools))
    #expect(Self.problem(tools: Self.platformTools, images: []) == .noCompatiblePackage(.emulator))
  }

  @Test("라이선스는 계획 패키지가 쓰는 것만, 지문 기준으로 중복을 빼고 처음 나온 순서")
  func licensesDeduplicated() throws {
    let plan = try Self.plan()
    #expect(plan.licenses == [Fixture.sdkLicense, Fixture.armLicense])
    #expect(try Self.plan(missing: [.emulator]).licenses == [Fixture.sdkLicense])
  }

  @Test("각 패키지의 원문은 그 패키지가 있는 XML 의 것: 두 XML 의 같은 id 원문이 다르면 둘 다 보인다")
  func licensePerRepository() throws {
    let imageCopy = AndroidLicense(id: "android-sdk-license", text: "SDK license (sys-img copy)")
    let result = Fixture.plan(
      tools: Self.platformTools + Self.emulators,
      images: Self.images,
      imageLicenses: [imageCopy, Fixture.armLicense],
      host: .x64
    )
    let plan = try result.get()
    #expect(plan.packages.map(\.license) == [Fixture.sdkLicense, Fixture.sdkLicense, imageCopy])
    #expect(plan.licenses == [Fixture.sdkLicense, imageCopy])

    let same = try Fixture.plan(tools: Self.platformTools + Self.emulators, images: Self.images, host: .x64).get()
    #expect(same.licenses == [Fixture.sdkLicense])
  }

  @Test("uses-license 가 없거나 그 원문이 그 XML 에 없으면 licenseMissing")
  func licenseMissing() {
    let noRef = [Fixture.tool("platform-tools", .v("1.0.0"), license: nil, archives: [Fixture.archive("a.zip")])]
    #expect(Self.problem(tools: noRef + Self.emulators, missing: [.platformTools]) == .licenseMissing(.platformTools))
    #expect(Self.problem(imageLicenses: [Fixture.sdkLicense], missing: [.systemImage]) == .licenseMissing(.systemImage))
  }

  // MARK: - archive 주소

  @Test("archive url: 파일 이름 하나만 받아 XML 폴더 기준 https 주소를 만든다")
  func archiveURL() throws {
    let base = Fixture.repositoryBase
    #expect(AndroidSDKSelection.archiveURL(fileName: "platform-tools_r37.0.1-darwin.zip", base: base)?.url
      .absoluteString
      == "https://dl.google.com/android/repository/platform-tools_r37.0.1-darwin.zip")
    #expect(try AndroidSDKSelection
      .archiveURL(fileName: "_a.zip", base: #require(DownloadURL("https://x.example/dir")))?.url.absoluteString
      == "https://x.example/dir/_a.zip")
    for bad in ["../x.zip", "a/b.zip", "https://evil/x.zip", "/x.zip", "", ".x.zip", "a b.zip", "x.zip?q", "-x.zip"] {
      #expect(AndroidSDKSelection.archiveURL(fileName: bad, base: base) == nil, "\(bad)")
    }
  }

  @Test("이름이 규칙에 맞지 않는 archive 는 거절하고 다른 archive·패키지를 본다")
  func rejectsBadArchiveNames() throws {
    let tools = [
      Fixture.tool("platform-tools", .v("38.0.0"), archives: [Fixture.archive("../evil.zip")]),
      Fixture.tool(
        "platform-tools",
        .v("37.0.0"),
        archives: [Fixture.archive("https://evil/x.zip"), Fixture.archive("ok.zip")]
      ),
    ]
    #expect(try Self.plan(tools: tools, missing: [.platformTools]).packages.first?.archive.fileName == "ok.zip")
  }

  @Test("픽스처 XML 두 개로 aarch64 계획: platform-tools 37.0.1·emulator 37.2.12·android-37.0 arm64 rev 8, 라이선스 둘")
  func fixturePlan() throws {
    let input = try AndroidSDKSelection.Input(
      repository: Fixture.repository("android-repository"),
      repositoryBase: Fixture.repositoryBase,
      systemImages: Fixture.repository("android-sys-img"),
      systemImagesBase: Fixture.systemImagesBase,
      host: .aarch64,
      missing: Set(AndroidSDKComponent.allCases),
      installedEmulator: nil
    )
    let plan = try AndroidSDKSelection.plan(
      input,
      root: Fixture.root,
      sdkVolumeName: nil,
      sameVolumeAsDownloads: false
    ).get()

    #expect(plan.packages.map(\.archive.fileName) == [
      "platform-tools_r37.0.1-darwin.zip",
      "emulator-darwin_aarch64-16428233.zip",
      "arm64-v8a-37.0_r08.zip",
    ])
    #expect(plan.packages.last?.url.url.absoluteString
      == "https://dl.google.com/android/repository/sys-img/google_apis/arm64-v8a-37.0_r08.zip")
    #expect(plan.licenses.map(\.id) == ["android-sdk-license", "android-sdk-arm-dbt-license"])
    #expect(plan.downloadBytes == 16_110_554 + 416_112_708 + 2_104_098_168)
  }
}
