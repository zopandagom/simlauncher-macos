import AndroidSDKInterface
import Core
import DownloadInterface
import DownloadTesting
import Foundation
import Testing
@testable import AndroidSDKImpl

/// `fetchInstallPlan()`: XML 두 개를 Fake 로 받아 계획을 만든다.
struct AndroidSDKClientImplPlanTests {
  static let sha1 = String(repeating: "a", count: 40)

  static let repositoryXML = Data("""
  <sdk:sdk-repository xmlns:sdk="http://schemas.android.com/sdk/android/repo/repository2/03">
    <license id="android-sdk-license" type="text">SDK terms</license>
    <channel id="channel-0">stable</channel>
    <remotePackage path="platform-tools">
      <revision><major>37</major><minor>0</minor><micro>1</micro></revision>
      <display-name>Android SDK Platform-Tools</display-name>
      <uses-license ref="android-sdk-license"/>
      <channelRef ref="channel-0"/>
      <archives><archive><complete><size>10</size><checksum type="sha1">\(sha1)</checksum>\
  <url>pt.zip</url></complete><host-os>macosx</host-os></archive></archives>
    </remotePackage>
    <remotePackage path="emulator">
      <revision><major>37</major><minor>2</minor><micro>12</micro></revision>
      <display-name>Android Emulator</display-name>
      <uses-license ref="android-sdk-license"/>
      <channelRef ref="channel-0"/>
      <archives><archive><complete><size>20</size><checksum type="sha1">\(sha1)</checksum>\
  <url>emu.zip</url></complete><host-os>macosx</host-os><host-arch>aarch64</host-arch></archive></archives>
    </remotePackage>
  </sdk:sdk-repository>
  """.utf8)

  static let systemImagesXML = Data("""
  <sys-img:sdk-sys-img xmlns:sys-img="http://schemas.android.com/sdk/android/repo/sys-img2/03">
    <license id="android-sdk-arm-dbt-license" type="text">ARM terms</license>
    <channel id="channel-0">stable</channel>
    <remotePackage path="system-images;android-37.0;google_apis;arm64-v8a">
      <type-details><api-level>37.0</api-level><base-extension>true</base-extension>\
  <tag><id>google_apis</id></tag><abi>arm64-v8a</abi></type-details>
      <revision><major>8</major></revision>
      <display-name>Google APIs ARM 64 v8a System Image</display-name>
      <uses-license ref="android-sdk-arm-dbt-license"/>
      <channelRef ref="channel-0"/>
      <dependencies><dependency path="emulator"><min-revision><major>37</major><minor>2</minor><micro>11</micro>\
  </min-revision></dependency></dependencies>
      <archives><archive><complete><size>30</size><checksum type="sha1">\(sha1)</checksum>\
  <url>arm64-v8a-37.0_r08.zip</url></complete></archive></archives>
    </remotePackage>
  </sys-img:sdk-sys-img>
  """.utf8)

  static func harness(volume: @escaping @Sendable (URL) -> SDKVolume = { _ in
    SDKVolume(device: 1, name: "Macintosh HD", supportsSymbolicLinks: true)
  }) throws -> Harness {
    let harness = try Harness(volume: volume)
    harness.download.setFetchResult(.success(Self.repositoryXML), for: Harness.endpoints.repository)
    harness.download.setFetchResult(.success(Self.systemImagesXML), for: Harness.endpoints.systemImages)
    return harness
  }

  @Test("XML 두 개를 상한(maxByteCount)으로 받아 없는 구성 요소의 계획을 만든다, 받을 주소는 XML 폴더 기준")
  func buildsPlan() async throws {
    let harness = try Self.harness()
    defer { harness.directory.remove() }

    let plan = try await harness.planResult().get()

    #expect(Set(harness.download.calls) == [
      .fetchData(Harness.endpoints.repository.url, maxBytes: AndroidRepository.maxByteCount),
      .fetchData(Harness.endpoints.systemImages.url, maxBytes: AndroidRepository.maxByteCount),
    ])
    #expect(plan.root == harness.root)
    #expect(plan.packages.map(\.component) == [.platformTools, .emulator, .systemImage])
    #expect(plan.packages.map(\.url.url.absoluteString) == [
      "https://repo.example.com/android/pt.zip",
      "https://repo.example.com/android/emu.zip",
      "https://repo.example.com/android/sys-img/arm64-v8a-37.0_r08.zip",
    ])
    #expect(plan.licenses.map(\.text) == ["SDK terms", "ARM terms"])
    #expect(plan.sdkVolumeName == "Macintosh HD")
    #expect(plan.sameVolumeAsDownloads)
    #expect(harness.command.invocations.isEmpty)
  }

  @Test("다시 읽은 상태의 없는 구성 요소만, 설치된 emulator revision 으로 의존을 본다")
  func onlyMissing() async throws {
    let harness = try Self.harness()
    defer { harness.directory.remove() }
    try FileTree.installed(.platformTools, in: harness.sdk)
    try FileTree.installed(.emulator, in: harness.sdk)

    let plan = try await harness.planResult().get()

    #expect(plan.packages.map(\.component) == [.systemImage])
    #expect(plan.licenses.map(\.id) == ["android-sdk-arm-dbt-license"])
  }

  @Test("없는 것이 없으면 XML 을 받지 않고 빈 계획")
  func nothingMissing() async throws {
    let harness = try Self.harness()
    defer { harness.directory.remove() }
    for component in AndroidSDKComponent.allCases {
      try FileTree.installed(component, in: harness.sdk)
    }

    let plan = try await harness.planResult().get()

    #expect(plan.isEmpty)
    #expect(plan.root == harness.root)
    #expect(harness.download.calls.isEmpty)
  }

  @Test("다른 볼륨이면 sameVolumeAsDownloads false, 볼륨 이름은 SDK 쪽")
  func otherVolume() async throws {
    let downloadsMarker = "downloads"
    let harness = try Self.harness(volume: { url in
      url.path(percentEncoded: false).contains(downloadsMarker)
        ? SDKVolume(device: 1, name: "Macintosh HD", supportsSymbolicLinks: true)
        : SDKVolume(device: 2, name: "Tools", supportsSymbolicLinks: true)
    })
    defer { harness.directory.remove() }

    let plan = try await harness.planResult().get()

    #expect(!plan.sameVolumeAsDownloads)
    #expect(plan.sdkVolumeName == "Tools")
  }

  @Test("받기 실패는 repository 쪽을 먼저 옮기고, 한쪽만 실패해도 실패")
  func downloadFailures() async throws {
    let harness = try Self.harness()
    defer { harness.directory.remove() }

    harness.download.setFetchResult(.failure(.offline), for: Harness.endpoints.repository)
    harness.download.setFetchResult(.failure(.httpStatus(500)), for: Harness.endpoints.systemImages)
    #expect(await harness.planResult() == .failure(.download(.offline)))

    harness.download.setFetchResult(.success(Self.repositoryXML), for: Harness.endpoints.repository)
    #expect(await harness.planResult() == .failure(.download(.httpStatus(500))))

    harness.download.setFetchResult(.failure(.tooLarge), for: Harness.endpoints.systemImages)
    #expect(await harness.planResult() == .failure(.download(.tooLarge)))
  }

  @Test("받기 중 하나라도 cancelled 면 cancelled")
  func downloadCancelled() async throws {
    let harness = try Self.harness()
    defer { harness.directory.remove() }
    harness.download.setFetchResult(.failure(.offline), for: Harness.endpoints.repository)
    harness.download.setFetchResult(.failure(.cancelled), for: Harness.endpoints.systemImages)

    #expect(await harness.planResult() == .failure(.cancelled))
  }

  @Test("XML 을 읽지 못하면 repositoryUnreadable, 맞는 패키지가 없으면 noCompatiblePackage")
  func parseAndSelectionFailures() async throws {
    let harness = try Self.harness()
    defer { harness.directory.remove() }

    harness.download.setFetchResult(.success(Data("<html/>".utf8)), for: Harness.endpoints.systemImages)
    #expect(await harness.planResult() == .failure(.repositoryUnreadable))

    harness.download.setFetchResult(.success(Data("not xml".utf8)), for: Harness.endpoints.systemImages)
    #expect(await harness.planResult() == .failure(.repositoryUnreadable))

    harness.download.setFetchResult(.success(Data("<sdk-sys-img/>".utf8)), for: Harness.endpoints.systemImages)
    #expect(await harness.planResult() == .failure(.noCompatiblePackage(.systemImage)))

    let noLicense = try Data(#require(String(bytes: Self.systemImagesXML, encoding: .utf8))
      .replacingOccurrences(
        of: "<license id=\"android-sdk-arm-dbt-license\" type=\"text\">ARM terms</license>",
        with: ""
      )
      .utf8)
    harness.download.setFetchResult(.success(noLicense), for: Harness.endpoints.systemImages)
    #expect(await harness.planResult() == .failure(.noCompatiblePackage(.systemImage)))
  }

  @Test("위치를 쓸 수 없으면 받지 않고 sdkFolderUnavailable")
  func unusableLocation() async throws {
    let harness = try Self.harness()
    defer { harness.directory.remove() }

    harness.provider.set(.invalidSetting)
    #expect(await harness.planResult() == .failure(.sdkFolderUnavailable))

    harness.provider.set(.root(AndroidSDKRoot(url: harness.directory.child("gone"), isDefault: false)))
    #expect(await harness.planResult() == .failure(.sdkFolderUnavailable))

    try FileTree.directory(harness.sdk, "", mode: 0o555)
    harness.provider.set(.root(harness.root))
    #expect(await harness.planResult() == .failure(.sdkFolderUnavailable))
    #expect(harness.download.calls.isEmpty)
  }

  @Test("받는 중 Task 가 취소되면 cancelled")
  func cancelWhileFetching() async throws {
    let harness = try Self.harness()
    defer { harness.directory.remove() }
    harness.download.suspendFetches()
    let task = Task { await harness.planResult() }

    try await waitUntil { harness.download.suspendedFetchCount == 2 }
    task.cancel()

    #expect(await task.value == .failure(.cancelled))
  }

  @Test("돌려주기 직전에 Task 가 취소됐으면 결과(빈 계획 포함)와 관계없이 cancelled")
  func cancelBeforeReturn() async throws {
    let harness = try Self.harness()
    defer { harness.directory.remove() }

    for component in AndroidSDKComponent.allCases {
      try FileTree.installed(component, in: harness.sdk)
    }
    let cancelled = await Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return await harness.planResult()
    }.value
    #expect(cancelled == .failure(.cancelled))
  }
}
