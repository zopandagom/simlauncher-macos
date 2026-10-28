import AndroidEmulatorInterface
import CommandTesting
import Core
import Foundation
import Testing
@testable import AndroidEmulatorImpl

/// `erase`: 임시 홈의 기기 폴더에서 목록의 파일만 지운다. 만들기·삭제는 `AndroidEmulatorClientImplFileTests`.
struct AndroidEmulatorClientImplEraseTests {
  @Test("초기화: 목록의 파일·snapshots 만 지우고 config.ini·AVD.conf·hardware-qemu.ini·sdcard.img 는 남긴다")
  func eraseRemovesListedFiles() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let folder = try harness.addDevice("Pixel")
    for name in AndroidAVDReset.fileNames + [
      "AVD.conf",
      "hardware-qemu.ini",
      "sdcard.img",
      "snapshots/default_boot/ram.bin",
    ] {
      try FileTree.file(folder, name)
    }

    try await harness.client.erase(AndroidVirtualDevice.ID("Pixel"))

    #expect(FileTree.names(folder) == ["AVD.conf", "config.ini", "hardware-qemu.ini", "modem_simulator", "sdcard.img"])
    #expect(FileTree.names(folder.appending(path: "modem_simulator")).isEmpty)
    #expect(harness.command.invocations.isEmpty)
  }

  @Test("초기화: 목록 항목이 링크면 링크만 지우고, 중간 구성 요소가 링크면 그 아래는 건너뛴다")
  func eraseDoesNotFollowLinks() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let folder = try harness.addDevice("Pixel")
    let outside = harness.directory.url.appending(path: "outside", directoryHint: .isDirectory)
    try FileTree.file(outside, "userdata.img")
    try FileTree.file(outside, "modem/modem_nvram.json")
    try FileTree.link(folder, "userdata-qemu.img", to: FileFacts.path(outside) + "/userdata.img")
    try FileTree.link(folder, "modem_simulator", to: FileFacts.path(outside) + "/modem")

    try await harness.client.erase(AndroidVirtualDevice.ID("Pixel"))

    #expect(!FileTree.exists(folder, "userdata-qemu.img"))
    #expect(FileTree.exists(folder, "modem_simulator"))
    #expect(FileTree.exists(outside, "userdata.img"))
    #expect(FileTree.exists(outside, "modem/modem_nvram.json"))
  }

  @Test("초기화: 기기 폴더가 링크이거나 .avd 로 끝나지 않으면 unsafeDeviceFolder 이고 아무것도 지우지 않는다")
  func eraseRejectsUnsafeFolder() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let real = harness.directory.url.appending(path: "elsewhere/Real.avd", directoryHint: .isDirectory)
    try FileTree.file(real, "config.ini", contents: Harness.config(sysdir: Harness.image.sysdirValue))
    try FileTree.file(real, "cache.img")
    try FileTree.link(harness.avdFolder, "Linked.avd", to: FileFacts.path(real))
    let linkedFolder = harness.deviceFolder("Linked")
    try FileTree.file(harness.avdFolder, "Linked.ini", contents: "path=\(FileFacts.path(linkedFolder))\n")
    let plain = harness.directory.url.appending(path: "plain", directoryHint: .isDirectory)
    try FileTree.file(plain, "config.ini", contents: Harness.config(sysdir: Harness.image.sysdirValue))
    try FileTree.file(plain, "cache.img")
    try FileTree.file(harness.avdFolder, "Plain.ini", contents: "path=\(FileFacts.path(plain))\n")

    let linked = await thrownError { try await harness.client.erase(AndroidVirtualDevice.ID("Linked")) }
    #expect(linked == .unsafeDeviceFolder(Harness.pointed(linkedFolder)))
    let plainError = await thrownError { try await harness.client.erase(AndroidVirtualDevice.ID("Plain")) }
    #expect(plainError == .unsafeDeviceFolder(Harness.pointed(plain)))
    #expect(FileTree.exists(real, "cache.img"))
    #expect(FileTree.exists(plain, "cache.img"))
  }

  @Test("초기화: 켜진 기기는 deviceRunning, 쓸 수 없는 기기는 deviceUnavailable")
  func eraseRejectsRunningAndUnavailable() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let running = try harness.addDevice("Running")
    try FileTree.file(running, "cache.img")
    harness.locks.hold(running)
    let missing = try harness.addDevice(
      "Missing",
      config: Harness.config(sysdir: "system-images/android-35/google_apis/arm64-v8a/")
    )
    try FileTree.file(missing, "cache.img")

    #expect(await thrownError { try await harness.client.erase(AndroidVirtualDevice.ID("Running")) } == .deviceRunning)
    let image = AndroidSystemImageRef(apiFolder: "android-35", tag: "google_apis", abi: "arm64-v8a")
    let unavailable = await thrownError { try await harness.client.erase(AndroidVirtualDevice.ID("Missing")) }
    #expect(unavailable == .deviceUnavailable(.systemImageMissing(image)))
    #expect(FileTree.exists(running, "cache.img"))
    #expect(FileTree.exists(missing, "cache.img"))
  }
}
