/// AVD 초기화(사용자 데이터·스냅샷 지우기)로 지울 것. 켜지 않고 지우므로 iOS 초기화(`simctl erase`)와 같은 동작이고,
/// 다음 켜기에서 emulator 가 지운 이미지를 다시 만든다 (실측). `config.ini`·`AVD.conf`·`hardware-qemu.ini`·`sdcard.img`·그 밖은 남긴다.
public enum AndroidAVDReset {
  /// 기기 폴더 기준 상대 경로 (`/` 로 나눈 구성 요소). 있는 것만, 링크면 링크만 지운다.
  public static let fileNames: [String] = [
    "userdata-qemu.img",
    "userdata-qemu.img.qcow2",
    "cache.img",
    "cache.img.qcow2",
    "encryptionkey.img",
    "encryptionkey.img.qcow2",
    "emulator-user.ini",
    "modem_simulator/modem_nvram.json",
    "bootcompleted.ini",
  ]

  /// 통째로 지울 디렉터리 (기기 폴더 기준).
  public static let directoryNames: [String] = ["snapshots"]
}
