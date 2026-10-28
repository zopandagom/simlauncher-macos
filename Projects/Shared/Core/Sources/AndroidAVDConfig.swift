import Foundation

/// 새 AVD 를 만들 때 쓰는 두 파일의 내용. 실측으로 켜진 키만 쓴다 (`path.rel` 은 미실측이라 쓰지 않는다).
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
  public static func configFile(
    displayName: String,
    image: AndroidSystemImageRef,
    profile: AndroidDeviceProfile,
    host: AndroidHostArchitecture
  ) -> Data {
    AVDIniFile.render([
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
    ])
  }

  /// `hw.cpu.arch` 값: Apple 실리콘 `arm64` (실측), Intel `x86_64` (미실측).
  public static func cpuArch(_ host: AndroidHostArchitecture) -> String {
    switch host {
    case .aarch64: "arm64"
    case .x64: "x86_64"
    }
  }
}
