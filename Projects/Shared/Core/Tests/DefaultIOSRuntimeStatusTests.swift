import Testing
@testable import Core

struct DefaultIOSRuntimeStatusTests {
  private static let defaultRuntime = DefaultIOSRuntime(version: OSVersion(major: 27, minor: 1), build: "24A94232")

  private static func image(
    _ id: String,
    platform: DevicePlatform = .iOS,
    version: OSVersion = OSVersion(major: 27, minor: 1),
    build: String = "24A94232",
    state: RuntimeImage.State = .ready
  ) -> RuntimeImage {
    RuntimeImage(
      id: RuntimeImage.ID(id),
      runtimeID: DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.iOS-\(version.major)-\(version.minor)"),
      platform: platform,
      version: version,
      build: build,
      state: state,
      sizeBytes: 8_000_000_000
    )
  }

  @Test("같은 major.minor 의 Ready iOS 이미지면 installed")
  func installed() {
    let image = Self.image("A")
    let status = DefaultIOSRuntimeStatus(defaultRuntime: Self.defaultRuntime, images: [image])
    #expect(status == .installed(image))
  }

  @Test("patch 가 달라도 installed")
  func patchDiffers() {
    let image = Self.image("A", version: OSVersion(major: 27, minor: 1, patch: 1))
    let status = DefaultIOSRuntimeStatus(defaultRuntime: Self.defaultRuntime, images: [image])
    #expect(status == .installed(image))
  }

  @Test("build 가 SDK 와 달라도 installed (xcodebuild 의 iOS 런타임 설치도 받지 않았다)")
  func buildDiffers() {
    let image = Self.image("A", build: "24A94425")
    let status = DefaultIOSRuntimeStatus(defaultRuntime: Self.defaultRuntime, images: [image])
    #expect(status == .installed(image))
  }

  @Test("다른 minor 만 있으면 notInstalled")
  func otherMinorOnly() {
    let image = Self.image("A", version: OSVersion(major: 27, minor: 0), build: "24A434")
    let status = DefaultIOSRuntimeStatus(defaultRuntime: Self.defaultRuntime, images: [image])
    #expect(status == .notInstalled)
  }

  @Test("같은 버전이어도 iOS 가 아니면 notInstalled")
  func otherPlatformOnly() {
    let image = Self.image("A", platform: .watchOS)
    let status = DefaultIOSRuntimeStatus(defaultRuntime: Self.defaultRuntime, images: [image])
    #expect(status == .notInstalled)
  }

  @Test("preparing 만 있으면 preparing, unusable 만 있으면 unusable")
  func preparingOrUnusableOnly() {
    let preparing = Self.image("A", state: .preparing)
    let unusable = Self.image("B", state: .unusable)
    #expect(DefaultIOSRuntimeStatus(defaultRuntime: Self.defaultRuntime, images: [preparing]) == .preparing(preparing))
    #expect(DefaultIOSRuntimeStatus(defaultRuntime: Self.defaultRuntime, images: [unusable]) == .unusable(unusable))
  }

  @Test("상태 우선순위는 ready > preparing > unusable (목록 순서와 상관없다)")
  func statePrecedence() {
    let ready = Self.image("C")
    let preparing = Self.image("A", state: .preparing)
    let unusable = Self.image("B", state: .unusable)

    let withReady = DefaultIOSRuntimeStatus(defaultRuntime: Self.defaultRuntime, images: [unusable, preparing, ready])
    let withoutReady = DefaultIOSRuntimeStatus(defaultRuntime: Self.defaultRuntime, images: [unusable, preparing])

    #expect(withReady == .installed(ready))
    #expect(withoutReady == .preparing(preparing))
  }

  @Test("removing·unknown 은 후보에서 빠져 notInstalled")
  func removingAndUnknownExcluded() {
    let images = [Self.image("A", state: .removing), Self.image("B", state: .unknown)]
    let status = DefaultIOSRuntimeStatus(defaultRuntime: Self.defaultRuntime, images: images)
    #expect(status == .notInstalled)
  }

  @Test("removing 이 있어도 다른 후보가 있으면 그 후보")
  func removingDoesNotHideOthers() {
    let unusable = Self.image("B", state: .unusable)
    let images = [Self.image("A", state: .removing), unusable]
    let status = DefaultIOSRuntimeStatus(defaultRuntime: Self.defaultRuntime, images: images)
    #expect(status == .unusable(unusable))
  }

  @Test("Ready 가 여럿이면 SDK build 와 같은 것을 고른다")
  func prefersMatchingBuild() {
    let other = Self.image("A", version: OSVersion(major: 27, minor: 1, patch: 1), build: "24A99999")
    let matching = Self.image("B", build: "24A94232")
    let status = DefaultIOSRuntimeStatus(defaultRuntime: Self.defaultRuntime, images: [other, matching])
    #expect(status == .installed(matching))
  }

  @Test("build 일치가 같으면 version 이 높은 것, 그다음 id 순")
  func prefersHigherVersionThenID() {
    let low = Self.image("A", build: "X1")
    let high = Self.image("B", version: OSVersion(major: 27, minor: 1, patch: 2), build: "X2")
    let sameAsHighLaterID = Self.image("D", version: OSVersion(major: 27, minor: 1, patch: 2), build: "X3")
    let sameAsHighEarlierID = Self.image("C", version: OSVersion(major: 27, minor: 1, patch: 2), build: "X4")

    let byVersion = DefaultIOSRuntimeStatus(defaultRuntime: Self.defaultRuntime, images: [low, high])
    let byID = DefaultIOSRuntimeStatus(
      defaultRuntime: Self.defaultRuntime,
      images: [sameAsHighLaterID, low, sameAsHighEarlierID]
    )

    #expect(byVersion == .installed(high))
    #expect(byID == .installed(sameAsHighEarlierID))
  }

  @Test("SDK build 를 모르면(nil) build 로 고르지 않고 version 순")
  func unknownDefaultBuild() {
    let defaultRuntime = DefaultIOSRuntime(version: OSVersion(major: 27, minor: 1), build: nil)
    let low = Self.image("A", build: "24A94232")
    let high = Self.image("B", version: OSVersion(major: 27, minor: 1, patch: 1), build: "24A99999")
    let status = DefaultIOSRuntimeStatus(defaultRuntime: defaultRuntime, images: [low, high])
    #expect(status == .installed(high))
  }

  @Test("빈 목록이면 notInstalled")
  func empty() {
    #expect(DefaultIOSRuntimeStatus(defaultRuntime: Self.defaultRuntime, images: []) == .notInstalled)
  }
}
