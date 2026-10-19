import Core

/// 테스트·Example·Preview 가 함께 쓰는 샘플 목록. UDID 는 `00000000-0000-0000-0000-00000000000N`.
/// 기기 종류는 `SampleDeviceType.all`, 런타임마다 만들 수 있는 종류(`supportedDeviceTypeIDs`)가 정해져 있다.
public extension DeviceInventory {
  /// iOS 27.0(iPhone 꺼짐·iPhone 켜짐·iPad 꺼짐), iOS 26.0(iPhone 꺼짐), watchOS 27.0(Watch, 화면에 안 보임),
  /// 설치되지 않은 iOS 25.0 의 쓸 수 없는 iPhone.
  static let sample = DeviceInventory(
    devices: [
      VirtualDevice(
        id: SampleID.iPhoneOff,
        name: "iPhone 17",
        family: .phone,
        state: .shutdown,
        availability: .available,
        runtime: SampleRuntime.iOS27
      ),
      VirtualDevice(
        id: SampleID.iPhoneOn,
        name: "iPhone 17 Pro",
        family: .phone,
        state: .booted,
        availability: .available,
        runtime: SampleRuntime.iOS27
      ),
      VirtualDevice(
        id: SampleID.iPadOff,
        name: "iPad (A16)",
        family: .tablet,
        state: .shutdown,
        availability: .available,
        runtime: SampleRuntime.iOS27
      ),
      VirtualDevice(
        id: SampleID.iPhoneIOS26,
        name: "iPhone 16",
        family: .phone,
        state: .shutdown,
        availability: .available,
        runtime: SampleRuntime.iOS26
      ),
      VirtualDevice(
        id: SampleID.watch,
        name: "Apple Watch Series 11 (46mm)",
        family: .watch,
        state: .shutdown,
        availability: .available,
        runtime: SampleRuntime.watchOS27
      ),
      VirtualDevice(
        id: SampleID.unavailableIPhone,
        name: "iPhone 15",
        family: .phone,
        state: .shutdown,
        availability: .unavailable(.runtimeNotInstalled),
        runtime: SampleRuntime.iOS25NotInstalled
      ),
    ],
    runtimes: [SampleRuntime.iOS27, SampleRuntime.iOS26, SampleRuntime.watchOS27],
    deviceTypes: SampleDeviceType.all
  )

  /// 런타임도 기기도 기기 종류도 없다 (`DeviceListEmptyReason.noIOSRuntime`).
  static let noRuntime = DeviceInventory(devices: [], runtimes: [], deviceTypes: [])

  /// 쓸 수 있는 iOS 런타임은 있지만 기기가 없다 (`DeviceListEmptyReason.noDevices`).
  static let noDevices = DeviceInventory(
    devices: [],
    runtimes: [SampleRuntime.iOS27],
    deviceTypes: SampleDeviceType.all
  )

  /// 쓸 수 있는 iOS 런타임은 있지만 기기 종류 목록이 비어, 지원 ID 가 이름 있는 종류와 겹치지 않는다
  /// (`DeviceListEmptyReason.noCreatableDeviceType`).
  static let noCreatableDeviceType = DeviceInventory(devices: [], runtimes: [SampleRuntime.iOS27], deviceTypes: [])
}

/// `DeviceInventory.sample` 기기의 UDID.
public enum SampleID {
  /// iOS 27.0 iPhone 17, 꺼짐.
  public static let iPhoneOff = VirtualDevice.ID("00000000-0000-0000-0000-000000000001")
  /// iOS 27.0 iPhone 17 Pro, 켜짐.
  public static let iPhoneOn = VirtualDevice.ID("00000000-0000-0000-0000-000000000002")
  /// iOS 27.0 iPad (A16), 꺼짐.
  public static let iPadOff = VirtualDevice.ID("00000000-0000-0000-0000-000000000003")
  /// iOS 26.0 iPhone 16, 꺼짐.
  public static let iPhoneIOS26 = VirtualDevice.ID("00000000-0000-0000-0000-000000000004")
  /// watchOS 27.0 Watch (화면에 안 보임).
  public static let watch = VirtualDevice.ID("00000000-0000-0000-0000-000000000005")
  /// 설치되지 않은 iOS 25.0 의 iPhone 15 (쓸 수 없음).
  public static let unavailableIPhone = VirtualDevice.ID("00000000-0000-0000-0000-000000000006")
}

/// `DeviceInventory` 샘플의 런타임.
public enum SampleRuntime {
  public static let iOS27 = DeviceRuntime(
    id: DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.iOS-27-0"),
    platform: .iOS,
    version: OSVersion(major: 27),
    name: "iOS 27.0",
    isAvailable: true,
    supportedDeviceTypeIDs: [
      SampleDeviceType.iPhone17Pro.id,
      SampleDeviceType.iPhone17.id,
      SampleDeviceType.iPadA16.id,
    ]
  )
  public static let iOS26 = DeviceRuntime(
    id: DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.iOS-26-0"),
    platform: .iOS,
    version: OSVersion(major: 26),
    name: "iOS 26.0",
    isAvailable: true,
    supportedDeviceTypeIDs: [
      SampleDeviceType.iPhone17.id,
      SampleDeviceType.iPhone16.id,
      SampleDeviceType.iPadA16.id,
    ]
  )
  public static let watchOS27 = DeviceRuntime(
    id: DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.watchOS-27-0"),
    platform: .watchOS,
    version: OSVersion(major: 27),
    name: "watchOS 27.0",
    isAvailable: true,
    supportedDeviceTypeIDs: [SampleDeviceType.watchSeries11.id]
  )
  /// `runtimes` 에 없는(설치되지 않은) 런타임. 기기의 런타임 식별자에서 만든 값이라 쓸 수 없다.
  public static let iOS25NotInstalled = DeviceRuntime(
    id: DeviceRuntime.ID("com.apple.CoreSimulator.SimRuntime.iOS-25-0"),
    platform: .iOS,
    version: OSVersion(major: 25),
    name: "iOS 25.0",
    isAvailable: false,
    supportedDeviceTypeIDs: []
  )
}

/// `DeviceInventory` 샘플의 기기 종류.
public enum SampleDeviceType {
  public static let iPhone17Pro = DeviceType(
    id: DeviceType.ID("com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"),
    name: "iPhone 17 Pro",
    family: .phone
  )
  public static let iPhone17 = DeviceType(
    id: DeviceType.ID("com.apple.CoreSimulator.SimDeviceType.iPhone-17"),
    name: "iPhone 17",
    family: .phone
  )
  public static let iPhone16 = DeviceType(
    id: DeviceType.ID("com.apple.CoreSimulator.SimDeviceType.iPhone-16"),
    name: "iPhone 16",
    family: .phone
  )
  public static let iPadA16 = DeviceType(
    id: DeviceType.ID("com.apple.CoreSimulator.SimDeviceType.iPad-A16"),
    name: "iPad (A16)",
    family: .tablet
  )
  public static let watchSeries11 = DeviceType(
    id: DeviceType.ID("com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-11-46mm"),
    name: "Apple Watch Series 11 (46mm)",
    family: .watch
  )
  public static let all = [iPhone17Pro, iPhone17, iPhone16, iPadA16, watchSeries11]
}
