import Foundation
import Testing
@testable import Core

struct AndroidAVDConfigTests {
  private static let image = AndroidSystemImageRef(apiFolder: "android-37.0", tag: "google_apis", abi: "arm64-v8a")!

  @Test("<이름>.ini 는 encoding·path(끝 / 없음)·target 세 줄")
  func pointerFile() {
    let folder = URL(filePath: "/Users/u/.android/avd/Pixel_9.avd/", directoryHint: .isDirectory)

    let data = AndroidAVDConfig.pointerFile(folder: folder, name: AndroidVirtualDevice.ID("Pixel_9"), image: Self.image)

    #expect(String(bytes: data, encoding: .utf8) == """
    avd.ini.encoding=UTF-8
    path=/Users/u/.android/avd/Pixel_9.avd
    target=android-37.0

    """)
  }

  @Test("폴더 경로의 공백·한글은 퍼센트 인코딩하지 않는다")
  func pointerFileUnicodePath() throws {
    let folder = URL(filePath: "/Users/u/내 폴더/a b.avd", directoryHint: .isDirectory)

    let data = AndroidAVDConfig.pointerFile(folder: folder, name: AndroidVirtualDevice.ID("a"), image: Self.image)
    let pairs = try #require(AVDIniFile.parse(data))

    #expect(AVDIniFile.value(for: "path", in: pairs) == "/Users/u/내 폴더/a b.avd")
  }

  @Test("config.ini 는 실측 키를 정해진 순서로 쓴다")
  func configFile() throws {
    let profile = try #require(AndroidDeviceProfile.profile(.phone))

    let data = AndroidAVDConfig.configFile(displayName: "테스트 폰", image: Self.image, profile: profile, host: .aarch64)

    #expect(String(bytes: data, encoding: .utf8) == """
    avd.ini.encoding=UTF-8
    avd.ini.displayname=테스트 폰
    image.sysdir.1=system-images/android-37.0/google_apis/arm64-v8a/
    abi.type=arm64-v8a
    hw.cpu.arch=arm64
    tag.id=google_apis
    hw.lcd.width=1080
    hw.lcd.height=2400
    hw.lcd.density=420
    hw.keyboard=yes

    """)
  }

  @Test("폴더블 config 는 앱 키 10개 뒤에 폴더블 키 14개를 이 순서로 쓴다")
  func foldableConfigFile() throws {
    let profile = try #require(AndroidDeviceProfile.profile(.foldable))

    let data = AndroidAVDConfig.configFile(displayName: "테스트 폴더블", image: Self.image, profile: profile, host: .aarch64)

    #expect(String(bytes: data, encoding: .utf8) == """
    avd.ini.encoding=UTF-8
    avd.ini.displayname=테스트 폴더블
    image.sysdir.1=system-images/android-37.0/google_apis/arm64-v8a/
    abi.type=arm64-v8a
    hw.cpu.arch=arm64
    tag.id=google_apis
    hw.lcd.width=2076
    hw.lcd.height=2152
    hw.lcd.density=390
    hw.keyboard=yes
    hw.device.name=pixel_9_pro_fold
    hw.sensor.hinge=yes
    hw.sensor.hinge.count=1
    hw.sensor.hinge.type=1
    hw.sensor.hinge.sub_type=1
    hw.sensor.hinge.ranges=0-180
    hw.sensor.hinge.defaults=180
    hw.sensor.hinge.areas=1038-0-0-2152
    hw.sensor.posture_list=1, 2, 3
    hw.sensor.hinge_angles_posture_definitions=0-30, 30-150, 150-180
    hw.displayRegion.0.1.xOffset=0
    hw.displayRegion.0.1.yOffset=0
    hw.displayRegion.0.1.width=1080
    hw.displayRegion.0.1.height=2424

    """)
  }

  @Test("폴더블이 아닌 프로필의 config 는 키 10개 그대로", arguments: [
    AndroidDeviceProfile.ID.phone, .smallPhone, .tablet,
  ])
  func nonFoldableConfigKeys(id: AndroidDeviceProfile.ID) throws {
    let profile = try #require(AndroidDeviceProfile.profile(id))

    let data = AndroidAVDConfig.configFile(displayName: "a", image: Self.image, profile: profile, host: .aarch64)
    let pairs = try #require(AVDIniFile.parse(data))

    #expect(pairs.count == 10)
    #expect(!pairs.contains { pair in
      ["hw.device.", "hw.sensor.", "hw.displayRegion."].contains { pair.key.hasPrefix($0) }
    })
  }

  @Test("DeviceName 규칙을 통과한 표시 이름은 줄을 더하지 않고 그대로 다시 읽힌다", arguments: [
    "테스트 폰", "a=b", " # 주석 아님", "👩‍💻 폰", String(repeating: "가", count: DeviceName.maxLength),
  ])
  func displayNameRoundTrip(raw: String) throws {
    #expect(DeviceName.problem(in: raw) == nil)
    let name = DeviceName.normalized(raw)
    let profile = try #require(AndroidDeviceProfile.profile(.tablet))

    let data = AndroidAVDConfig.configFile(displayName: name, image: Self.image, profile: profile, host: .aarch64)
    let pairs = try #require(AVDIniFile.parse(data))

    #expect(pairs.count == 10)
    #expect(AVDIniFile.value(for: "avd.ini.displayname", in: pairs) == name)
  }

  @Test("만든 config 는 판정에서 쓸 수 있고 기기 모양이 프로필과 같다", arguments: AndroidDeviceProfile.all)
  func createdConfigIsAvailable(profile: AndroidDeviceProfile) {
    let data = AndroidAVDConfig.configFile(displayName: "a", image: Self.image, profile: profile, host: .aarch64)
    let facts = AndroidAVDFacts(
      name: "a",
      folderExists: true,
      config: AVDIniFile.parse(data),
      imageInstalled: true,
      lockHeld: nil
    )

    let device = AndroidDeviceJudge.device(facts, host: .aarch64, adb: nil)

    #expect(device.availability == .available)
    #expect(device.formFactor == profile.formFactor)
    #expect(device.systemImage == Self.image)
  }

  @Test("hw.cpu.arch 는 Apple 실리콘 arm64, Intel x86_64")
  func cpuArch() {
    #expect(AndroidAVDConfig.cpuArch(.aarch64) == "arm64")
    #expect(AndroidAVDConfig.cpuArch(.x64) == "x86_64")
  }

  @Test("초기화 목록은 사용자 데이터·스냅샷만 (설정·sdcard 는 남긴다)")
  func resetList() {
    #expect(AndroidAVDReset.fileNames == [
      "userdata-qemu.img",
      "userdata-qemu.img.qcow2",
      "cache.img",
      "cache.img.qcow2",
      "encryptionkey.img",
      "encryptionkey.img.qcow2",
      "emulator-user.ini",
      "modem_simulator/modem_nvram.json",
      "bootcompleted.ini",
    ])
    #expect(AndroidAVDReset.directoryNames == ["snapshots"])
    let kept = ["config.ini", "AVD.conf", "hardware-qemu.ini", "sdcard.img"]
    #expect(kept.allSatisfy { !AndroidAVDReset.fileNames.contains($0) })
  }
}
