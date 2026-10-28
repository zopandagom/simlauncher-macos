import Foundation

/// AVD 하나에 대해 Impl 이 모은 사실 (파일 읽기·잠금 조회 결과).
public struct AndroidAVDFacts: Sendable {
  /// AVD 이름 (`<이름>.ini` 의 이름).
  public let name: String
  /// `path`·`path.rel` 로 정한 기기 폴더가 있는지.
  public let folderExists: Bool
  /// config.ini. nil = 없음·읽지 못함·상한 초과.
  public let config: [(key: String, value: String)]?
  /// `<SDK>/<image.sysdir.1>/system.img` 가 일반 파일인지.
  public let imageInstalled: Bool
  /// `multiinstance.lock` 의 `F_GETLK`: true = WRLCK(실행 중), false = UNLCK, nil = 파일 없음·확인 실패.
  public let lockHeld: Bool?

  public init(
    name: String,
    folderExists: Bool,
    config: [(key: String, value: String)]?,
    imageInstalled: Bool,
    lockHeld: Bool?
  ) {
    self.name = name
    self.folderExists = folderExists
    self.config = config
    self.imageInstalled = imageInstalled
    self.lockHeld = lockHeld
  }
}

/// adb 로 본 그 AVD 의 상태.
public enum AndroidADBBootState: Hashable, Sendable {
  /// serial 이 offline 이거나, adb 는 성공했는데 그 이름의 serial 이 아직 없다 (켜진 뒤 1~4초).
  case offline
  /// serial 이 device 인데 `sys.boot_completed` 가 1 이 아니다.
  case booting
  /// `sys.boot_completed` = 1.
  case booted
}

/// Impl 이 모은 사실로 기기 하나를 판정한다.
public enum AndroidDeviceJudge {
  static let displayNameKey = "avd.ini.displayname"
  static let sysdirKey = "image.sysdir.1"
  static let cpuArchKey = "hw.cpu.arch"

  /// 우선순위: 이름(`AndroidAVDName.isValid`) → 폴더 없음 → config 읽지 못함 → 이미지 경로 키 없음·형식 틀림 →
  /// 이미지 abi 가 호스트와 다름 → `hw.cpu.arch` 없음(configUnreadable)·호스트 값과 다름(unsupportedABI) → 이미지 미설치 → available.
  /// `abi.type` 은 보지 않는다 (emulator 는 이미지 경로와 `hw.cpu.arch` 로 켠다).
  public static func availability(
    _ facts: AndroidAVDFacts,
    host: AndroidHostArchitecture
  ) -> AndroidVirtualDevice.Availability {
    guard AndroidAVDName.isValid(facts.name) else {
      return .unavailable(.unsupportedName)
    }
    guard facts.folderExists else {
      return .unavailable(.folderMissing)
    }
    guard let config = facts.config else {
      return .unavailable(.configUnreadable)
    }
    guard let image = self.systemImage(config) else {
      return .unavailable(.systemImageMissing(nil))
    }
    guard image.abi == host.systemImageABI else {
      return .unavailable(.unsupportedABI(image.abi))
    }
    guard let cpuArch = AVDIniFile.value(for: self.cpuArchKey, in: config) else {
      return .unavailable(.configUnreadable)
    }
    guard cpuArch == AndroidAVDConfig.cpuArch(host) else {
      return .unavailable(.unsupportedABI(cpuArch))
    }
    guard facts.imageInstalled else {
      return .unavailable(.systemImageMissing(image))
    }
    return .available
  }

  /// 잠금이 있으면 실행 중: adb 가 nil(확인 못 함)이면 켜짐, 완료면 켜짐, 그 밖은 켜는 중.
  /// 잠금이 없거나 모르면 adb 를 따른다 (adb 에 없으면 nil → 꺼짐. 다른 AVD 홈에서 켠 같은 이름은 드문 경우).
  public static func state(lockHeld: Bool?, adb: AndroidADBBootState?) -> AndroidVirtualDevice.State {
    switch (lockHeld, adb) {
    case (true, nil), (_, .booted): .booted
    case (_, .offline), (_, .booting): .booting
    case (false, nil), (nil, nil): .shutdown
    }
  }

  /// 사실과 adb 상태로 기기 하나를 만든다. 표시 이름은 `avd.ini.displayname`(비면 AVD 이름), 이미지는 `image.sysdir.1`,
  /// 기기 모양은 `hw.lcd.width`·`hw.lcd.height`·`hw.lcd.density` (하나라도 없거나 양의 정수가 아니면 nil).
  public static func device(
    _ facts: AndroidAVDFacts,
    host: AndroidHostArchitecture,
    adb: AndroidADBBootState?
  ) -> AndroidVirtualDevice {
    let config = facts.config ?? []
    let displayName = AVDIniFile.value(for: self.displayNameKey, in: config).flatMap { $0.isEmpty ? nil : $0 }
    return AndroidVirtualDevice(
      id: AndroidVirtualDevice.ID(facts.name),
      displayName: displayName ?? facts.name,
      systemImage: self.systemImage(config),
      formFactor: self.formFactor(config),
      state: self.state(lockHeld: facts.lockHeld, adb: adb),
      availability: self.availability(facts, host: host)
    )
  }

  static func systemImage(_ config: [(key: String, value: String)]) -> AndroidSystemImageRef? {
    AVDIniFile.value(for: self.sysdirKey, in: config).flatMap(AndroidSystemImageRef.parse(sysdir:))
  }

  static func formFactor(_ config: [(key: String, value: String)]) -> AndroidVirtualDevice.FormFactor? {
    let values = ["hw.lcd.width", "hw.lcd.height", "hw.lcd.density"].compactMap { key in
      AVDIniFile.value(for: key, in: config).flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
    }
    guard values.count == 3 else {
      return nil
    }
    return AndroidVirtualDevice.FormFactor(width: values[0], height: values[1], density: values[2])
  }
}
