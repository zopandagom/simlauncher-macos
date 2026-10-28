import Foundation
import Testing
@testable import Core

struct AndroidDeviceCreationOptionsTests {
  @Test("호스트 abi 이미지만, API 내림차순(숫자 비교), 같은 API 는 태그 순서, 같은 값은 하나")
  func imagesForHost() {
    let options = AndroidDeviceCreationOptions(
      installedImages: [
        Self.image("35"),
        Self.image("37.0", tag: "google_apis_playstore"),
        Self.image("36", abi: "x86_64"),
        Self.image("36"),
        Self.image("37.0"),
        Self.image("9"),
        Self.image("36"),
      ],
      host: .aarch64
    )

    #expect(options.images == [
      Self.image("37.0"), Self.image("37.0", tag: "google_apis_playstore"), Self.image("36"), Self.image("35"),
      Self.image("9"),
    ])
    #expect(options.defaultImage == Self.image("37.0"))
    #expect(!options.isEmpty)
  }

  @Test("Intel 호스트는 x86_64 이미지만")
  func intelHost() {
    let options = AndroidDeviceCreationOptions(
      installedImages: [Self.image("37.0"), Self.image("35", abi: "x86_64")],
      host: .x64
    )

    #expect(options.images == [Self.image("35", abi: "x86_64")])
  }

  @Test("이미지가 없으면 비었고 기본값도 없다, 프로필은 늘 고정 3개")
  func empty() {
    let options = AndroidDeviceCreationOptions(installedImages: [Self.image("36", abi: "x86_64")], host: .aarch64)

    #expect(options.isEmpty)
    #expect(options.defaultImage == nil)
    #expect(options.profiles.map(\.id) == [.phone, .smallPhone, .tablet])
  }

  @Test("contains 는 목록의 이미지와 프로필 조합만 참")
  func contains() {
    let options = AndroidDeviceCreationOptions(installedImages: [Self.image("37.0")], host: .aarch64)

    #expect(options.contains(image: Self.image("37.0"), profile: .tablet))
    #expect(!options.contains(image: Self.image("36"), profile: .phone))
  }

  @Test("프로필 3개는 고정 순서와 실측 크기")
  func profiles() {
    let profiles = AndroidDeviceProfile.all

    #expect(profiles.map(\.id) == AndroidDeviceProfile.ID.allCases)
    #expect(profiles.map(\.width) == [1080, 720, 2560])
    #expect(profiles.map(\.height) == [2400, 1280, 1600])
    #expect(profiles.map(\.density) == [420, 320, 320])
    #expect(AndroidDeviceProfile.profile(.smallPhone)?.width == 720)
  }

  // MARK: - AndroidSystemImageRef

  @Test("image.sysdir.1 을 읽는다 (앞뒤 / 허용)", arguments: [
    "system-images/android-37.0/google_apis/arm64-v8a/",
    "system-images/android-37.0/google_apis/arm64-v8a",
    "/system-images/android-37.0/google_apis/arm64-v8a/",
  ])
  func parseSysdir(sysdir: String) throws {
    let image = try #require(AndroidSystemImageRef.parse(sysdir: sysdir))

    #expect(image.apiFolder == "android-37.0")
    #expect(image.tag == "google_apis")
    #expect(image.abi == "arm64-v8a")
    #expect(image.apiLabel == "37.0")
    #expect(image.sysdirValue == "system-images/android-37.0/google_apis/arm64-v8a/")
  }

  @Test("구성 요소가 4개가 아니거나, 규칙에 맞지 않거나, android- 로 시작하지 않으면 nil", arguments: [
    "",
    "system-images/android-37.0/google_apis",
    "system-images/android-37.0/google_apis/arm64-v8a/extra/",
    "images/android-37.0/google_apis/arm64-v8a/",
    "system-images/../google_apis/arm64-v8a/",
    "system-images/android-37.0/./arm64-v8a/",
    "system-images/android-37.0//arm64-v8a/",
    "system-images/37.0/google_apis/arm64-v8a/",
    "system-images/android-/google_apis/arm64-v8a/",
    "system-images/android-37.0/google;apis/arm64-v8a/",
    "//system-images/android-37.0/google_apis/arm64-v8a/",
  ])
  func parseInvalid(sysdir: String) {
    #expect(AndroidSystemImageRef.parse(sysdir: sysdir) == nil)
  }

  // MARK: - 도우미

  static func image(_ api: String, tag: String = "google_apis", abi: String = "arm64-v8a") -> AndroidSystemImageRef {
    AndroidSystemImageRef(apiFolder: "android-\(api)", tag: tag, abi: abi)!
  }
}
