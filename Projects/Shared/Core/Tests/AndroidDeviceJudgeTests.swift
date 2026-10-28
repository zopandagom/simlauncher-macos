import Foundation
import Testing
@testable import Core

struct AndroidDeviceJudgeTests {
  // MARK: - availability

  @Test("모든 사실이 맞으면 쓸 수 있다")
  func available() {
    #expect(AndroidDeviceJudge.availability(Self.facts(), host: .aarch64) == .available)
  }

  @Test("이름이 규칙에 맞지 않으면 다른 사실보다 먼저 unsupportedName")
  func unsupportedNameFirst() {
    let facts = Self.facts(name: "테스트 폰", folderExists: false, config: nil)

    #expect(AndroidDeviceJudge.availability(facts, host: .aarch64) == .unavailable(.unsupportedName))
  }

  @Test("폴더가 없으면 config 보다 먼저 folderMissing")
  func folderMissing() {
    let facts = Self.facts(folderExists: false, config: nil)

    #expect(AndroidDeviceJudge.availability(facts, host: .aarch64) == .unavailable(.folderMissing))
  }

  @Test("config 를 읽지 못하면 configUnreadable")
  func configUnreadable() {
    let facts = Self.facts(config: nil)

    #expect(AndroidDeviceJudge.availability(facts, host: .aarch64) == .unavailable(.configUnreadable))
  }

  @Test("이미지 경로 키가 없거나 형식이 틀리면 systemImageMissing(nil)", arguments: [
    nil, "system-images/android-37.0/google_apis", "images/android-37.0/google_apis/arm64-v8a/",
    "system-images/../google_apis/arm64-v8a/",
  ] as [String?])
  func sysdirMissing(sysdir: String?) {
    let facts = Self.facts(config: Self.config(sysdir: sysdir))

    #expect(AndroidDeviceJudge.availability(facts, host: .aarch64) == .unavailable(.systemImageMissing(nil)))
  }

  @Test("이미지 abi 가 호스트와 다르면 cpu.arch·설치 여부보다 먼저 unsupportedABI(이미지 abi)")
  func imageABIMismatch() {
    let facts = Self.facts(
      config: Self.config(sysdir: "system-images/android-35/google_apis/x86_64/", cpuArch: "x86_64"),
      imageInstalled: false
    )

    #expect(AndroidDeviceJudge.availability(facts, host: .aarch64) == .unavailable(.unsupportedABI("x86_64")))
  }

  @Test("hw.cpu.arch 가 없으면 configUnreadable")
  func cpuArchMissing() {
    let facts = Self.facts(config: Self.config(cpuArch: nil), imageInstalled: false)

    #expect(AndroidDeviceJudge.availability(facts, host: .aarch64) == .unavailable(.configUnreadable))
  }

  @Test("hw.cpu.arch 가 호스트 값과 다르면 설치 여부보다 먼저 unsupportedABI(그 값)")
  func cpuArchMismatch() {
    let facts = Self.facts(config: Self.config(cpuArch: "x86_64"), imageInstalled: false)

    #expect(AndroidDeviceJudge.availability(facts, host: .aarch64) == .unavailable(.unsupportedABI("x86_64")))
  }

  @Test("이미지가 설치되어 있지 않으면 systemImageMissing(그 이미지)")
  func imageNotInstalled() {
    let facts = Self.facts(imageInstalled: false)

    #expect(
      AndroidDeviceJudge.availability(facts, host: .aarch64)
        == .unavailable(.systemImageMissing(AndroidSystemImageRef(
          apiFolder: "android-37.0",
          tag: "google_apis",
          abi: "arm64-v8a"
        )))
    )
  }

  @Test("abi.type 은 판정에 쓰지 않는다")
  func ignoresABIType() {
    var config = Self.config()
    config.append(("abi.type", "x86_64"))

    #expect(AndroidDeviceJudge.availability(Self.facts(config: config), host: .aarch64) == .available)
  }

  @Test("Intel 호스트는 x86_64 이미지와 hw.cpu.arch=x86_64 를 쓸 수 있다")
  func intelHost() {
    let facts = Self.facts(config: Self.config(
      sysdir: "system-images/android-35/google_apis/x86_64/",
      cpuArch: "x86_64"
    ))

    #expect(AndroidDeviceJudge.availability(facts, host: .x64) == .available)
  }

  // MARK: - state

  @Test("잠금이 없거나 모르고 adb 에도 없으면 꺼짐")
  func shutdown() {
    #expect(AndroidDeviceJudge.state(lockHeld: nil, adb: nil) == .shutdown)
    #expect(AndroidDeviceJudge.state(lockHeld: false, adb: nil) == .shutdown)
  }

  @Test("잠금이 있고 adb 가 실패(nil)하면 켜짐")
  func lockAdbFailed() {
    #expect(AndroidDeviceJudge.state(lockHeld: true, adb: nil) == .booted)
  }

  @Test("잠금이 있고 adb 는 성공했는데 serial 이 없거나 offline 이면 켜는 중")
  func lockOffline() {
    #expect(AndroidDeviceJudge.state(lockHeld: true, adb: .offline) == .booting)
  }

  @Test("잠금이 있고 device 인데 boot_completed 가 1 이 아니면 켜는 중, 1 이면 켜짐")
  func lockBootCompleted() {
    #expect(AndroidDeviceJudge.state(lockHeld: true, adb: .booting) == .booting)
    #expect(AndroidDeviceJudge.state(lockHeld: true, adb: .booted) == .booted)
  }

  @Test("잠금이 없거나 모르는데 adb 에 그 이름이 있으면 adb 를 따른다", arguments: [false, nil] as [Bool?])
  func noLockFollowsAdb(lockHeld: Bool?) {
    #expect(AndroidDeviceJudge.state(lockHeld: lockHeld, adb: .offline) == .booting)
    #expect(AndroidDeviceJudge.state(lockHeld: lockHeld, adb: .booting) == .booting)
    #expect(AndroidDeviceJudge.state(lockHeld: lockHeld, adb: .booted) == .booted)
  }

  // MARK: - device

  @Test("표시 이름·이미지·기기 모양·상태·쓸 수 있는지를 모아 기기를 만든다")
  func device() {
    var config = Self.config()
    config.insert(("avd.ini.displayname", "테스트 폰"), at: 0)

    let device = AndroidDeviceJudge.device(Self.facts(config: config, lockHeld: true), host: .aarch64, adb: .booting)

    #expect(device.id == AndroidVirtualDevice.ID("Pixel_9"))
    #expect(device.displayName == "테스트 폰")
    #expect(device.systemImage == AndroidSystemImageRef(
      apiFolder: "android-37.0",
      tag: "google_apis",
      abi: "arm64-v8a"
    ))
    #expect(device.formFactor == .phone)
    #expect(device.state == .booting)
    #expect(device.availability == .available)
  }

  @Test("표시 이름이 없거나 비면 AVD 이름, config 가 없으면 이미지·기기 모양은 nil")
  func deviceFallbacks() {
    var config = Self.config()
    config.insert(("avd.ini.displayname", ""), at: 0)

    let empty = AndroidDeviceJudge.device(Self.facts(config: config), host: .aarch64, adb: nil)
    let missing = AndroidDeviceJudge.device(Self.facts(config: nil), host: .aarch64, adb: nil)

    #expect(empty.displayName == "Pixel_9")
    #expect(missing.displayName == "Pixel_9")
    #expect(missing.systemImage == nil)
    #expect(missing.formFactor == nil)
    #expect(missing.state == .shutdown)
    #expect(missing.availability == .unavailable(.configUnreadable))
  }

  @Test("짧은 변이 600dp 이상이면 태블릿, 화면 키가 하나라도 없거나 양의 정수가 아니면 nil")
  func formFactor() {
    func formFactor(_ width: String?, _ height: String?, _ density: String?) -> AndroidVirtualDevice.FormFactor? {
      var pairs: [(key: String, value: String)] = []
      for (key, value) in [("hw.lcd.width", width), ("hw.lcd.height", height), ("hw.lcd.density", density)] {
        if let value {
          pairs.append((key, value))
        }
      }
      return AndroidDeviceJudge.formFactor(pairs)
    }

    #expect(formFactor("2560", "1600", "320") == .tablet)
    #expect(formFactor("1080", "2400", "420") == .phone)
    #expect(formFactor("1200", "1920", "320") == .tablet)
    #expect(formFactor("1199", "1920", "320") == .phone)
    #expect(formFactor("1080", "2400", nil) == nil)
    #expect(formFactor("1080", "2400", "0") == nil)
    #expect(formFactor("wide", "2400", "420") == nil)
  }

  @Test("내장 프로필의 기기 모양은 휴대전화 둘·태블릿 하나")
  func profileFormFactors() {
    #expect(AndroidDeviceProfile.all.map(\.formFactor) == [.phone, .phone, .tablet])
  }

  // MARK: - 도우미

  static func config(
    sysdir: String? = "system-images/android-37.0/google_apis/arm64-v8a/",
    cpuArch: String? = "arm64"
  ) -> [(key: String, value: String)] {
    var pairs: [(key: String, value: String)] = [("avd.ini.encoding", "UTF-8")]
    if let sysdir {
      pairs.append(("image.sysdir.1", sysdir))
    }
    if let cpuArch {
      pairs.append(("hw.cpu.arch", cpuArch))
    }
    pairs += [("hw.lcd.width", "1080"), ("hw.lcd.height", "2400"), ("hw.lcd.density", "420")]
    return pairs
  }

  static func facts(
    name: String = "Pixel_9",
    folderExists: Bool = true,
    config: [(key: String, value: String)]? = Self.config(),
    imageInstalled: Bool = true,
    lockHeld: Bool? = nil
  ) -> AndroidAVDFacts {
    AndroidAVDFacts(
      name: name,
      folderExists: folderExists,
      config: config,
      imageInstalled: imageInstalled,
      lockHeld: lockHeld
    )
  }
}
