import Foundation

/// 새 AVD 를 만들 때 쓰는 두 파일의 내용. 실측으로 켜진 키만 쓴다 (`path.rel` 은 미실측이라 쓰지 않는다).
/// 폴더블 키도 켜서 접기·펼치기를 확인한 것이다
/// (Studio 기기 정의에서 기본값인 `hw.sensor.hinge.fold_to_displayRegion.0.1_at_posture` 만 뺐다).
public enum AndroidAVDConfig {
  /// `<이름>.ini`: `avd.ini.encoding=UTF-8`, `path=<폴더 절대 경로>`, `target=android-<api>`.
  /// emulator 는 `path` 로 기기 폴더를 찾는다.
  public static func pointerFile(folder: URL, name: AndroidVirtualDevice.ID, image: AndroidSystemImageRef) -> Data {
    var path = folder.path(percentEncoded: false)
    while path.count > 1, path.hasSuffix("/") {
      path.removeLast()
    }
    return AVDIniFile.render([
      ("avd.ini.encoding", "UTF-8"),
      ("path", path),
      ("target", image.apiFolder),
    ])
  }

  /// config.ini (이 순서). 화면 크기 키가 없으면 320x480@160 이 되고, `hw.cpu.arch` 가 없으면 emulator 가 켜지지 않고,
  /// `hw.keyboard` 기본값은 꺼짐이라 Mac 키보드 입력이 안 된다 (모두 실측).
  /// 표시 이름은 `DeviceName.normalized` 를 거쳐 `DeviceName.problem` 이 없는 값을 넘긴다 (줄 바꿈이 들어가지 않는다).
  /// 폴더블이면 이 10개 뒤에 `foldPairs` 를 붙인다 (다른 프로필은 10개 그대로).
  public static func configFile(
    displayName: String,
    image: AndroidSystemImageRef,
    profile: AndroidDeviceProfile,
    host: AndroidHostArchitecture
  ) -> Data {
    var pairs: [(key: String, value: String)] = [
      ("avd.ini.encoding", "UTF-8"),
      ("avd.ini.displayname", displayName),
      ("image.sysdir.1", image.sysdirValue),
      ("abi.type", image.abi),
      ("hw.cpu.arch", self.cpuArch(host)),
      ("tag.id", image.tag),
      ("hw.lcd.width", String(profile.width)),
      ("hw.lcd.height", String(profile.height)),
      ("hw.lcd.density", String(profile.density)),
      ("hw.keyboard", "yes"),
    ]
    if let fold = profile.fold {
      pairs += self.foldPairs(fold)
    }
    return AVDIniFile.render(pairs)
  }

  /// 폴더블 키 14개 (이 순서). `hw.device.name`·posture 두 키·hinge 세부 키 묶음 중 하나라도 빠지면 접히지 않는다 (실측).
  /// hinge 세부·영역 오프셋 키를 하나씩 빼 보지는 않았다.
  private static func foldPairs(_ fold: AndroidDeviceProfile.Fold) -> [(key: String, value: String)] {
    [
      ("hw.device.name", fold.emulatorDeviceName),
      ("hw.sensor.hinge", "yes"),
      ("hw.sensor.hinge.count", "1"),
      ("hw.sensor.hinge.type", "1"),
      ("hw.sensor.hinge.sub_type", "1"),
      ("hw.sensor.hinge.ranges", "0-180"),
      ("hw.sensor.hinge.defaults", "180"),
      ("hw.sensor.hinge.areas", fold.hingeArea),
      ("hw.sensor.posture_list", "1, 2, 3"),
      ("hw.sensor.hinge_angles_posture_definitions", "0-30, 30-150, 150-180"),
      ("hw.displayRegion.0.1.xOffset", "0"),
      ("hw.displayRegion.0.1.yOffset", "0"),
      ("hw.displayRegion.0.1.width", String(fold.outerWidth)),
      ("hw.displayRegion.0.1.height", String(fold.outerHeight)),
    ]
  }

  /// `hw.cpu.arch` 값: Apple 실리콘 `arm64` (실측), Intel `x86_64` (미실측).
  public static func cpuArch(_ host: AndroidHostArchitecture) -> String {
    switch host {
    case .aarch64: "arm64"
    case .x64: "x86_64"
    }
  }
}
