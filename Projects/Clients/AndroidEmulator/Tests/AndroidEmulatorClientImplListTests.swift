import AndroidEmulatorInterface
import CommandTesting
import Core
import Foundation
import Testing
@testable import AndroidEmulatorImpl

/// `fetchDevices()`: 임시 홈의 `.android/avd` 와 임시 SDK, 잠금은 테스트가 `flock` 으로 잡고 adb 는 흉내.
struct AndroidEmulatorClientImplListTests {
  // MARK: - 파일

  @Test("Studio 형식 ini(path·path.rel·target): 쓸 수 있음·꺼짐·표시 이름·이미지·기기 모양, 명령 없음")
  func studioDevice() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("Pixel_9", displayName: "테스트 폰")

    let inventory = try await harness.client.fetchDevices()
    #expect(inventory.devices == [
      AndroidVirtualDevice(
        id: AndroidVirtualDevice.ID("Pixel_9"),
        displayName: "테스트 폰",
        systemImage: Harness.image,
        formFactor: .phone,
        state: .shutdown,
        availability: .available
      ),
    ])
    #expect(inventory.creationOptions.images == [Harness.image])
    #expect(harness.command.invocations.isEmpty)
  }

  @Test("path 없이 path.rel 만 있으면 ~/.android/<path.rel>")
  func pathRelOnly() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("Rel", pointer: "path.rel=avd/Rel.avd\ntarget=android-37.0\n")

    #expect(try await harness.device("Rel")?.availability == .available)
  }

  @Test("상대 path 는 무시하고 path.rel 을 쓴다. path.rel 의 .. 과 절대 경로는 거절한다 (Y7)")
  func pathRules() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("Relative", pointer: "path=avd/Nowhere.avd\npath.rel=avd/Relative.avd\n")
    let folder = try harness.addDevice("Escape", pointer: "path.rel=avd/../avd/Escape.avd\n")
    try harness.addDevice(
      "Absolute",
      pointer: "path.rel=\(harness.deviceFolder("Absolute").path(percentEncoded: false))\n"
    )
    try harness.addDevice("RelativeOnly", pointer: "path=avd/RelativeOnly.avd\n")

    #expect(FileTree.exists(folder))
    #expect(try await harness.device("Relative")?.availability == .available)
    #expect(try await harness.device("Escape")?.availability == .unavailable(.folderMissing))
    #expect(try await harness.device("Absolute")?.availability == .unavailable(.folderMissing))
    #expect(try await harness.device("RelativeOnly")?.availability == .unavailable(.folderMissing))
  }

  @Test("config 없음 → configUnreadable, 이미지 미설치 → systemImageMissing(ref), x86_64 → unsupportedABI")
  func unavailableReasons() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("NoConfig", config: "")
    try harness.addDevice(
      "Missing",
      config: Harness.config(sysdir: "system-images/android-35/google_apis/arm64-v8a/")
    )
    try harness.addDevice(
      "Intel",
      config: Harness.config(sysdir: "system-images/android-37.0/google_apis/x86_64/", cpuArch: "x86_64")
    )

    #expect(try await harness.device("NoConfig")?.availability == .unavailable(.configUnreadable))
    let missing = AndroidSystemImageRef(apiFolder: "android-35", tag: "google_apis", abi: "arm64-v8a")
    #expect(try await harness.device("Missing")?.availability == .unavailable(.systemImageMissing(missing)))
    #expect(try await harness.device("Intel")?.availability == .unavailable(.unsupportedABI("x86_64")))
  }

  @Test("공백·한글 이름의 ini 도 목록에 보이고 unsupportedName")
  func unsupportedNames() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("My Phone")
    try harness.addDevice("한글")

    #expect(try await harness.device("My Phone")?.availability == .unavailable(.unsupportedName))
    #expect(try await harness.device("한글")?.availability == .unavailable(.unsupportedName))
  }

  @Test(".ini 가 디렉터리이거나 링크면 건너뛴다, 확장자만 있는 .ini 도 뺀다")
  func skippedPointers() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let folder = try harness.addDevice("Real")
    try FileTree.directory(harness.avdFolder, "Folder.ini")
    try FileTree.link(
      harness.avdFolder,
      "Linked.ini",
      to: harness.avdFolder.appending(path: "Real.ini").path(percentEncoded: false)
    )
    try FileTree.file(harness.avdFolder, ".ini", contents: "path=\(folder.path(percentEncoded: false))\n")

    let names = try await harness.client.fetchDevices().devices.map(\.id.rawValue)
    #expect(names == ["Real"])
  }

  @Test("avd 폴더가 없으면 빈 목록이고 만들지 않는다")
  func noAVDFolder() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }

    #expect(try await harness.client.fetchDevices().devices.isEmpty)
    #expect(!FileTree.exists(harness.home, ".android"))
  }

  @Test("avd 폴더가 있는데 읽지 못하면 avdFolderUnavailable")
  func unreadableAVDFolder() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("Pixel")
    chmod(harness.avdFolder.path(percentEncoded: false), 0)
    defer { chmod(harness.avdFolder.path(percentEncoded: false), 0o755) }

    #expect(await thrownError { _ = try await harness.client.fetchDevices() } == .avdFolderUnavailable)
  }

  @Test("SDK 위치가 쓸 수 없거나 emulator·adb 가 없으면 sdkUnavailable")
  func sdkUnavailable() async throws {
    let invalid = try Harness(sdkChoice: .invalidSetting)
    defer { invalid.cleanUp() }
    #expect(await thrownError { _ = try await invalid.client.fetchDevices() } == .sdkUnavailable)

    let empty = try Harness(installSDK: false)
    defer { empty.cleanUp() }
    try FileTree.file(empty.sdk, "emulator/emulator", mode: 0o755)
    #expect(await thrownError { _ = try await empty.client.fetchDevices() } == .sdkUnavailable)

    try FileTree.file(empty.sdk, "platform-tools/adb", mode: 0o644)
    #expect(await thrownError { _ = try await empty.client.fetchDevices() } == .sdkUnavailable)
  }

  @Test("만들기 선택지: system.img 가 있는 호스트 abi 이미지만, API 내림차순")
  func creationOptions() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let older = try #require(AndroidSystemImageRef(apiFolder: "android-36", tag: "google_apis", abi: "arm64-v8a"))
    try Harness.installImage(older, in: harness.sdk)
    try Harness.installImage(
      #require(AndroidSystemImageRef(apiFolder: "android-37.0", tag: "google_apis", abi: "x86_64")),
      in: harness.sdk
    )
    try FileTree.directory(harness.sdk, "system-images/android-38/google_apis/arm64-v8a")
    try FileTree.file(harness.sdk, "system-images/android-39/google_apis/arm64-v8a/other.img")

    #expect(try await harness.client.fetchDevices().creationOptions.images == [Harness.image, older])
  }

  // MARK: - 실행 중 판정

  @Test("잠금 파일이 없거나 잡혀 있지 않으면 꺼짐이고 adb 를 부르지 않는다")
  func unlockedDevicesSkipADB() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("NoLock")
    let folder = try harness.addDevice("Unlocked")
    try FileTree.file(folder, AVDLock.fileName, contents: "")
    harness.adb.set("emulator-5554", FakeADB.Emulator(name: "Unlocked"))

    #expect(AVDLock.isHeld(folder: harness.deviceFolder("NoLock")) == nil)
    #expect(AVDLock.isHeld(folder: folder) == false)
    let states = try await harness.client.fetchDevices().devices.map(\.state)
    #expect(states == [.shutdown, .shutdown])
    #expect(harness.command.invocations.isEmpty)
  }

  @Test("잠금이 잡혀 있으면 WRLCK, 풀면 UNLCK")
  func lockQuery() throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let folder = try harness.addDevice("Pixel")

    harness.locks.hold(folder)
    #expect(AVDLock.isHeld(folder: folder) == true)
    harness.locks.release(folder)
    #expect(AVDLock.isHeld(folder: folder) == false)
  }

  @Test("잠금 + adb: 완료면 켜짐, device 인데 미완료·offline·serial 없음은 켜는 중, adb 실패는 켜짐")
  func runningStates() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    for name in ["Booted", "Booting", "Offline", "NoSerial"] {
      try harness.locks.hold(harness.addDevice(name))
    }
    try harness.addDevice("Off")
    harness.adb.set("emulator-5554", FakeADB.Emulator(name: "Booted"))
    harness.adb.set("emulator-5556", FakeADB.Emulator(name: "Booting", bootCompleted: false))
    harness.adb.set("emulator-5558", FakeADB.Emulator(name: "Offline", isOnline: false))

    var states = try await Self.states(harness)
    #expect(states == [
      "Booted": .booted,
      "Booting": .booting,
      "Offline": .booting,
      "NoSerial": .booting,
      "Off": .shutdown,
    ])

    harness.adb.setDevicesFail(true)
    states = try await Self.states(harness)
    #expect(states == [
      "Booted": .booted,
      "Booting": .booted,
      "Offline": .booted,
      "NoSerial": .booted,
      "Off": .shutdown,
    ])
  }

  @Test("잠금이 없어도 adb 에 그 이름이 보이면 adb 를 따른다 (다른 기기의 잠금으로 adb 를 부른 경우)")
  func adbWithoutLock() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.locks.hold(harness.addDevice("Locked"))
    try harness.addDevice("Elsewhere")
    harness.adb.set("emulator-5554", FakeADB.Emulator(name: "Locked"))
    harness.adb.set("emulator-5556", FakeADB.Emulator(name: "Elsewhere"))

    #expect(try await Self.states(harness)["Elsewhere"] == .booted)
  }

  @Test("adb 는 runCancellable 로 HOME·ADB_MDNS=0 환경과 시간 제한을 주고 실행한다")
  func adbInvocation() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.locks.hold(harness.addDevice("Pixel"))
    harness.adb.set("emulator-5554", FakeADB.Emulator(name: "Pixel"))

    _ = try await harness.client.fetchDevices()
    let invocations = harness.command.invocations
    #expect(harness.adbCalls == [
      ["devices"],
      ["-s", "emulator-5554", "emu", "avd", "name"],
      ["-s", "emulator-5554", "shell", "getprop", "sys.boot_completed"],
    ])
    for invocation in invocations {
      #expect(invocation.executable.path(percentEncoded: false) == FileFacts.path(harness.sdk) + "/platform-tools/adb")
      #expect(invocation.environment == ["HOME": FileFacts.path(harness.home), "ADB_MDNS": "0"])
      #expect(invocation.isCancellable)
      #expect(invocation.timeout == Harness.timing.adbTimeout)
    }
  }

  static func states(_ harness: Harness) async throws -> [String: AndroidVirtualDevice.State] {
    let devices = try await harness.client.fetchDevices().devices
    return Dictionary(uniqueKeysWithValues: devices.map { ($0.id.rawValue, $0.state) })
  }
}
