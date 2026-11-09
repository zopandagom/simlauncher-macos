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
  /// Apple 실리콘, 이미지 두 개 (`sample`·`olderSample`). 폴더블은 `sample` 로만 만들 수 있다 (`olderSample` 은 접기 설정이 없다).
  static let sample = AndroidDeviceCreationOptions(
    installedImages: [.sample, .olderSample],
    foldableImages: [.sample],
    host: .aarch64
  )

  /// 만들 수 있는 이미지가 없다.
  static let emptySample = AndroidDeviceCreationOptions(installedImages: [], foldableImages: [], host: .aarch64)
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

  /// Studio 로 만든 꺼진 폴더블 "Pixel 9 Pro Fold" (`Pixel_9_Pro_Fold`).
  static let foldableSample = AndroidVirtualDevice(
    id: ID("Pixel_9_Pro_Fold"),
    displayName: "Pixel 9 Pro Fold",
    systemImage: .sample,
    formFactor: .foldable,
    state: .shutdown,
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

  /// Android 도구를 쓸 수 없을 때 읽은 꺼진 휴대전화 "테스트 폰" (`Android_Device`, 잠금 없음). 삭제만 할 수 있다.
  static let sdkUnavailableShutdownSample = AndroidVirtualDevice(
    id: ID("Android_Device"),
    displayName: "테스트 폰",
    systemImage: .sample,
    formFactor: .phone,
    state: .shutdown,
    availability: .unavailable(.sdkUnavailable)
  )

  /// Android 도구를 쓸 수 없을 때 잠금으로 켜짐으로 읽은 태블릿 "Pixel Tablet" (`Pixel_Tablet`). 끄기·삭제 모두 막힌다.
  static let sdkUnavailableBootedSample = AndroidVirtualDevice(
    id: ID("Pixel_Tablet"),
    displayName: "Pixel Tablet",
    systemImage: .sample,
    formFactor: .tablet,
    state: .booted,
    availability: .unavailable(.sdkUnavailable)
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

  /// Android 도구를 쓸 수 없을 때의 목록 (`sdkAvailable == false`, 선택지 비어 있음).
  /// 기기는 `.unavailable(.sdkUnavailable)` 인 것을 넘긴다 (예: `sdkUnavailableShutdownSample`·`sdkUnavailableBootedSample`).
  static func sdkUnavailableSample(devices: [AndroidVirtualDevice]) -> AndroidDeviceInventory {
    AndroidDeviceInventory(devices: devices, creationOptions: .emptySample, sdkAvailable: false)
  }
}

public extension AndroidDeviceTraits {
  /// 설계 실측 기기: API 37, `arm64-v8a` 만 (32비트 ABI 없음).
  static let sample = AndroidDeviceTraits(apiLevel: 37, abis: ["arm64-v8a"])
}

public extension LayoutSnapshot {
  /// 작은 Android 레이아웃 스냅샷: 1080×2400 px, 밀도 420(2.625 px/dp), 루트 FrameLayout 과 "Navigate up" 버튼.
  /// 스크린샷은 1×1 PNG 자리 채우기다.
  static let androidLayoutSample = LayoutSnapshot(
    deviceName: "Pixel 9",
    capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
    screenshotPNG: Data([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00,
      0x00, 0x05, 0x00, 0x01, 0x7A, 0x5E, 0xAB, 0x3F, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
      0xAE, 0x42, 0x60, 0x82,
    ]),
    pixelSize: LayoutSize(width: 1080, height: 2400),
    unit: .dp,
    pixelsPerUnit: 2.625,
    nodes: [
      LayoutNode(
        id: 0,
        depth: 0,
        parentID: nil,
        frame: LayoutRect(x: 0, y: 0, width: 1080, height: 2400),
        type: "android.widget.FrameLayout"
      ),
      LayoutNode(
        id: 1,
        depth: 1,
        parentID: 0,
        frame: LayoutRect(x: 85, y: 105, width: 63, height: 63),
        type: "android.widget.ImageButton",
        label: "Navigate up"
      ),
    ],
    appIdentifier: "com.android.settings",
    isSystemScreen: false
  )
}
