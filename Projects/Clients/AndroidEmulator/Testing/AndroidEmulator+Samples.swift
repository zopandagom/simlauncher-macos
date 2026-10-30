import AndroidEmulatorInterface
import Core
import Foundation

/// 테스트·Example 이 함께 쓰는 Android 기기 값. 실제 파일을 가리키지 않는다.
public extension AndroidSystemImageRef {
  /// `system-images/android-37.0/google_apis/arm64-v8a/` (설계 실측 이미지).
  static let sample = AndroidSystemImageRef(apiFolder: "android-37.0", tag: "google_apis", abi: "arm64-v8a")!

  /// `system-images/android-36/google_apis_playstore/arm64-v8a/`.
  static let olderSample = AndroidSystemImageRef(
    apiFolder: "android-36",
    tag: "google_apis_playstore",
    abi: "arm64-v8a"
  )!
}

public extension AndroidDeviceCreationOptions {
  /// Apple 실리콘, 이미지 두 개 (`sample`·`olderSample`).
  static let sample = AndroidDeviceCreationOptions(
    installedImages: [.sample, .olderSample],
    host: .aarch64
  )

  /// 만들 수 있는 이미지가 없다.
  static let emptySample = AndroidDeviceCreationOptions(installedImages: [], host: .aarch64)
}

public extension AndroidVirtualDevice {
  /// 꺼진 휴대전화 "테스트 폰" (`Android_Device`).
  static let phoneSample = AndroidVirtualDevice(
    id: ID("Android_Device"),
    displayName: "테스트 폰",
    systemImage: .sample,
    formFactor: .phone,
    state: .shutdown,
    availability: .available
  )

  /// 켜진 태블릿 "Pixel Tablet" (`Pixel_Tablet`).
  static let bootedTabletSample = AndroidVirtualDevice(
    id: ID("Pixel_Tablet"),
    displayName: "Pixel Tablet",
    systemImage: .sample,
    formFactor: .tablet,
    state: .booted,
    availability: .available
  )

  /// 앱 밖에서 켜는 중인 휴대전화 "Studio Phone" (`Studio_Phone`).
  static let bootingSample = AndroidVirtualDevice(
    id: ID("Studio_Phone"),
    displayName: "Studio Phone",
    systemImage: .olderSample,
    formFactor: .phone,
    state: .booting,
    availability: .available
  )

  /// 이름에 공백이 있어 켤 수 없는 Studio 기기 "My Phone" (`My Phone`).
  static let unsupportedNameSample = AndroidVirtualDevice(
    id: ID("My Phone"),
    displayName: "My Phone",
    systemImage: .sample,
    formFactor: .phone,
    state: .shutdown,
    availability: .unavailable(.unsupportedName)
  )

  /// 시스템 이미지가 지금 SDK 에 없는 기기 "Old Phone" (`Old_Phone`, API 35).
  static let missingImageSample = AndroidVirtualDevice(
    id: ID("Old_Phone"),
    displayName: "Old Phone",
    systemImage: AndroidSystemImageRef(apiFolder: "android-35", tag: "google_apis", abi: "arm64-v8a"),
    formFactor: .phone,
    state: .shutdown,
    availability: .unavailable(
      .systemImageMissing(AndroidSystemImageRef(apiFolder: "android-35", tag: "google_apis", abi: "arm64-v8a"))
    )
  )
}

public extension AndroidDeviceInventory {
  /// 꺼진 휴대전화·켜진 태블릿·쓸 수 없는 기기 둘, 선택지 `sample`.
  static let sample = AndroidDeviceInventory(
    devices: [.phoneSample, .bootedTabletSample, .unsupportedNameSample, .missingImageSample],
    creationOptions: .sample
  )

  /// 기기 없음, 선택지 `sample`.
  static let emptySample = AndroidDeviceInventory(devices: [], creationOptions: .sample)
}

public extension AndroidDeviceTraits {
  /// 설계 실측 기기: API 37, `arm64-v8a` 만 (32비트 ABI 없음).
  static let sample = AndroidDeviceTraits(apiLevel: 37, abis: ["arm64-v8a"])
}
