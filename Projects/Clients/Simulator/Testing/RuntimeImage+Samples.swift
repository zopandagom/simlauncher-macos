import Core

/// 테스트·Example 이 함께 쓰는 런타임 이미지 샘플. 실측(Xcode 27.1 의 `simctl runtime list -j`)과 같은 구성이고
/// UUID 는 `00000000-0000-0000-0002-00000000000N` 으로 바꿨다.
public extension RuntimeImage {
  /// iOS 27.0 Ready, iOS 27.1 Ready, watchOS 27.0 Ready (`SimctlRuntimeListDecoder` 의 정렬 순서).
  static let samples: [RuntimeImage] = [
    SampleRuntimeImage.iOS27,
    SampleRuntimeImage.iOS27Point1,
    SampleRuntimeImage.watchOS27,
  ]
}

/// `RuntimeImage.samples` 의 이미지.
public enum SampleRuntimeImage {
  /// iOS 27.0 (24A434), Ready.
  public static let iOS27 = RuntimeImage(
    id: RuntimeImage.ID("00000000-0000-0000-0002-000000000001"),
    runtimeID: DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.iOS-27-0"),
    platform: .iOS,
    version: OSVersion(major: 27, minor: 0),
    build: "24A434",
    state: .ready,
    sizeBytes: 8_067_000_161
  )

  /// iOS 27.1 (24A94425), Ready. 기본 iOS 런타임 샘플(27.1, SDK build 24A94232)과 build 만 다르다 (실측과 같음).
  public static let iOS27Point1 = RuntimeImage(
    id: RuntimeImage.ID("00000000-0000-0000-0002-000000000002"),
    runtimeID: DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.iOS-27-1"),
    platform: .iOS,
    version: OSVersion(major: 27, minor: 1),
    build: "24A94425",
    state: .ready,
    sizeBytes: 7_874_743_137
  )

  /// watchOS 27.0 (24R362), Ready.
  public static let watchOS27 = RuntimeImage(
    id: RuntimeImage.ID("00000000-0000-0000-0002-000000000003"),
    runtimeID: DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.watchOS-27-0"),
    platform: .watchOS,
    version: OSVersion(major: 27, minor: 0),
    build: "24R362",
    state: .ready,
    sizeBytes: 3_814_435_665
  )
}
