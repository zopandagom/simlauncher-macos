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
      foldableImages: [],
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
      foldableImages: [],
      host: .x64
    )

    #expect(options.images == [Self.image("35", abi: "x86_64")])
  }

  @Test("이미지가 없으면 비었고 기본값도 없다, 프로필은 늘 고정 4개")
  func empty() {
    let options = AndroidDeviceCreationOptions(
      installedImages: [Self.image("36", abi: "x86_64")],
      foldableImages: [],
      host: .aarch64
    )

    #expect(options.isEmpty)
    #expect(options.defaultImage == nil)
    #expect(options.profiles.map(\.id) == [.phone, .smallPhone, .tablet, .foldable])
  }

  @Test("contains 는 목록의 이미지와 프로필 조합만 참")
  func contains() {
    let options = AndroidDeviceCreationOptions(
      installedImages: [Self.image("37.0")],
      foldableImages: [],
      host: .aarch64
    )

    #expect(options.contains(image: Self.image("37.0"), profile: .tablet))
    #expect(!options.contains(image: Self.image("36"), profile: .phone))
  }

  @Test("프로필 4개는 고정 순서와 실측 크기, 폴더블만 접기 값이 있다")
  func profiles() {
    let profiles = AndroidDeviceProfile.all

    #expect(profiles.map(\.id) == [.phone, .smallPhone, .tablet, .foldable])
    #expect(profiles.map(\.id) == AndroidDeviceProfile.ID.allCases)
    #expect(profiles.map(\.width) == [1080, 720, 2560, 2076])
    #expect(profiles.map(\.height) == [2400, 1280, 1600, 2152])
    #expect(profiles.map(\.density) == [420, 320, 320, 390])
    #expect(AndroidDeviceProfile.profile(.smallPhone)?.width == 720)
    #expect(AndroidDeviceProfile.profile(.foldable)?.fold == AndroidDeviceProfile.Fold(
      emulatorDeviceName: "pixel_9_pro_fold",
      outerWidth: 1080,
      outerHeight: 2424,
      hingeArea: "1038-0-0-2152"
    ))
    #expect(profiles.filter { $0.id != .foldable }.allSatisfy { $0.fold == nil })
  }

  @Test("폴더블에 필요한 이미지 안 접기 설정 파일은 두 개")
  func requiredImageFiles() throws {
    let fold = try #require(AndroidDeviceProfile.profile(.foldable)?.fold)

    #expect(fold.requiredImageFiles == [
      "data/misc/pixel_9_pro_fold/devicestate/device_state_configuration.xml",
      "data/misc/pixel_9_pro_fold/displayconfig/display_layout_configuration.xml",
    ])
  }

  static let a37 = image("37.0")
  static let p37 = image("37.0", tag: "google_apis_playstore")
  static let a35 = image("35")
  static let x37 = image("37.0", abi: "x86_64")

  @Test("폴더블은 접기 설정 파일이 있는 이미지로만 만들 수 있다, 다른 프로필은 상관없다", arguments: [
    (a37, AndroidDeviceProfile.ID.foldable, true, false),
    (p37, .foldable, true, false),
    (a35, .foldable, false, true),
    (a35, .phone, true, false),
    (a35, .tablet, true, false),
  ])
  func foldableImageRule(
    image: AndroidSystemImageRef,
    profile: AndroidDeviceProfile.ID,
    contains: Bool,
    lacksFoldSettings: Bool
  ) {
    let options = AndroidDeviceCreationOptions(
      installedImages: [Self.a37, Self.p37, Self.a35],
      foldableImages: [Self.a37, Self.p37],
      host: .aarch64
    )

    #expect(options.contains(image: image, profile: profile) == contains)
    #expect(options.lacksFoldSettings(image: image, profile: profile) == lacksFoldSettings)
  }

  @Test("선택지에 없는 이미지는 폴더블 접기 문제가 아니라 이미지 문제다 (설치 목록에 없음·다른 abi)")
  func foldableImageNotInOptions() {
    let missing = AndroidDeviceCreationOptions(installedImages: [Self.a35], foldableImages: [Self.a37], host: .aarch64)
    let otherABI = AndroidDeviceCreationOptions(installedImages: [Self.x37], foldableImages: [Self.x37], host: .aarch64)

    #expect(!missing.contains(image: Self.a37, profile: .foldable))
    #expect(!missing.lacksFoldSettings(image: Self.a37, profile: .foldable))
    #expect(!otherABI.contains(image: Self.x37, profile: .foldable))
    #expect(!otherABI.lacksFoldSettings(image: Self.x37, profile: .foldable))
  }

  @Test("foldableImages 는 선택지 이미지에 있는 것만 남는다")
  func foldableImagesWithinImages() {
    let all = AndroidDeviceCreationOptions(
      installedImages: [Self.a37, Self.p37, Self.a35],
      foldableImages: [Self.a37, Self.p37],
      host: .aarch64
    )
    let missing = AndroidDeviceCreationOptions(installedImages: [Self.a35], foldableImages: [Self.a37], host: .aarch64)
    let otherABI = AndroidDeviceCreationOptions(installedImages: [Self.x37], foldableImages: [Self.x37], host: .aarch64)

    #expect(all.foldableImages == [Self.a37, Self.p37])
    #expect(missing.foldableImages.isEmpty)
    #expect(otherABI.foldableImages.isEmpty)
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
