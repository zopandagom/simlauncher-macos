import AndroidEmulatorInterface
import CommandTesting
import Core
import Foundation
import Testing
@testable import AndroidEmulatorImpl

/// `create`·`delete`: 임시 홈의 `.android/avd` 에 파일을 쓰고 지운다. 실행 중은 테스트의 `flock` 잠금.
struct AndroidEmulatorClientImplFileTests {
  // MARK: - 만들기

  @Test("만들기: .android·avd 폴더를 만들고 두 파일을 정해진 내용으로 쓴다 (한글 표시 이름 → Android_Device)")
  func createWritesFiles() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }

    let id = try await harness.client.create(displayName: "  테스트 폰 ", image: Harness.image, profile: .phone)

    #expect(id == AndroidVirtualDevice.ID("Android_Device"))
    let folder = FileFacts.path(harness.deviceFolder("Android_Device"))
    #expect(FileTree.read(harness.avdFolder, "Android_Device.ini") == """
    avd.ini.encoding=UTF-8
    path=\(folder)
    target=android-37.0

    """)
    #expect(FileTree.read(harness.avdFolder, "Android_Device.avd/config.ini") == """
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
    #expect(FileTree.names(harness.avdFolder) == ["Android_Device.avd", "Android_Device.ini"])
    let device = try await harness.device("Android_Device")
    #expect(device?.displayName == "테스트 폰")
    #expect(device?.availability == .available)
    #expect(harness.command.invocations.isEmpty)
  }

  @Test("만들기: 대소문자만 다른 폴더·ini 와도 겹치지 않게 다음 번호")
  func createAvoidsCaseInsensitiveConflict() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try FileTree.directory(harness.avdFolder, "my_phone.avd")
    try FileTree.file(harness.avdFolder, "MY_PHONE_2.ini")

    let id = try await harness.client.create(displayName: "My Phone", image: Harness.image, profile: .tablet)
    #expect(id == AndroidVirtualDevice.ID("My_Phone_3"))
    #expect(FileTree.read(harness.avdFolder, "My_Phone_3.avd/config.ini")?.contains("hw.lcd.width=2560\n") == true)
  }

  @Test("독점 생성: 이름 집합에 없던 폴더·ini 가 이미 있으면 남의 것은 두고 다음 번호로 만든다")
  func createExclusiveRetry() throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try AVDFiles.prepareFolders(home: harness.home)
    try FileTree.file(harness.avdFolder, "Pixel.avd/marker")
    try FileTree.file(harness.avdFolder, "Pixel_2.ini", contents: "theirs")

    let id = try Self.createFiles(harness, taken: [])

    #expect(id == AndroidVirtualDevice.ID("Pixel_3"))
    #expect(FileTree.names(harness.avdFolder) == ["Pixel.avd", "Pixel_2.ini", "Pixel_3.avd", "Pixel_3.ini"])
    #expect(FileTree.names(harness.avdFolder.appending(path: "Pixel.avd")) == ["marker"])
    #expect(FileTree.read(harness.avdFolder, "Pixel_2.ini") == "theirs")
  }

  @Test("독점 생성: 세 번 모두 겹치면 nameUnavailable 이고 만든 것을 남기지 않는다")
  func createExclusiveGivesUp() throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try AVDFiles.prepareFolders(home: harness.home)
    for name in ["Pixel.avd", "Pixel_2.avd", "Pixel_3.avd"] {
      try FileTree.file(harness.avdFolder, "\(name)/marker", contents: "theirs")
    }

    #expect(throws: AndroidEmulatorError.nameUnavailable) { try Self.createFiles(harness, taken: []) }
    #expect(FileTree.names(harness.avdFolder) == ["Pixel.avd", "Pixel_2.avd", "Pixel_3.avd"])
    for name in ["Pixel.avd", "Pixel_2.avd", "Pixel_3.avd"] {
      // mkdir 이 EEXIST 로 실패한 남의 폴더는 지우지도, 안에 쓰지도 않는다.
      #expect(FileTree.names(harness.avdFolder.appending(path: name)) == ["marker"])
      #expect(FileTree.read(harness.avdFolder, "\(name)/marker") == "theirs")
    }
  }

  @Test("만들기: 표시 이름 문제(줄 바꿈·빈 이름)는 파일을 쓰기 전에 거절한다")
  func createRejectsInvalidName() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }

    let newline = await thrownError {
      _ = try await harness.client.create(displayName: "a\nhw.cpu.arch=x86_64", image: Harness.image, profile: .phone)
    }
    #expect(newline == .invalidDeviceName(.containsControlCharacter))
    let empty = await thrownError {
      _ = try await harness.client.create(displayName: "  ", image: Harness.image, profile: .phone)
    }
    #expect(empty == .invalidDeviceName(.empty))
    #expect(!FileTree.exists(harness.home, ".android"))
  }

  @Test("만들기: 실행 직전에 이미지가 없으면 creationOptionUnavailable, 다른 abi 이미지도 같다")
  func createRejectsMissingImage() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let older = try #require(AndroidSystemImageRef(apiFolder: "android-36", tag: "google_apis", abi: "arm64-v8a"))
    let intel = try #require(AndroidSystemImageRef(apiFolder: "android-37.0", tag: "google_apis", abi: "x86_64"))
    try Harness.installImage(intel, in: harness.sdk)

    for image in [older, intel] {
      let error = await thrownError {
        _ = try await harness.client.create(displayName: "Phone", image: image, profile: .phone)
      }
      #expect(error == .creationOptionUnavailable)
    }
    #expect(!FileTree.exists(harness.home, ".android"))
  }

  @Test("만들기: 폴더블을 만들면 폴더블 config 를 쓰고 목록에 폴더블 한 대")
  func createFoldable() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try Harness.installFoldFiles(Harness.image, in: harness.sdk)
    let profile = try #require(AndroidDeviceProfile.profile(.foldable))

    let id = try await harness.client.create(displayName: "테스트 폴더블", image: Harness.image, profile: .foldable)

    let config = try Data(contentsOf: harness.deviceFolder(id.rawValue).appending(path: "config.ini"))
    #expect(config == AndroidAVDConfig.configFile(
      displayName: "테스트 폴더블",
      image: Harness.image,
      profile: profile,
      host: .aarch64
    ))
    let devices = try await harness.client.fetchDevices().devices
    #expect(devices.count == 1)
    #expect(devices.first?.formFactor == .foldable)
    #expect(devices.first?.availability == .available)
  }

  @Test("만들기: 접기 설정이 없는 이미지로 폴더블을 만들면 아무것도 쓰지 않고 거절")
  func createFoldableRejectsImageWithoutFoldFiles() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }

    let error = await thrownError {
      _ = try await harness.client.create(displayName: "테스트 폴더블", image: Harness.image, profile: .foldable)
    }

    #expect(error == .creationOptionUnavailable)
    #expect(!FileTree.exists(harness.home, ".android"))
  }

  @Test("만들기: ~/.android 가 파일이면 avdFolderUnavailable, SDK 를 쓸 수 없으면 sdkUnavailable")
  func createFolderAndSDKFailures() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try FileTree.file(harness.home, ".android")
    let blocked = await thrownError {
      _ = try await harness.client.create(displayName: "Phone", image: Harness.image, profile: .phone)
    }
    #expect(blocked == .avdFolderUnavailable)

    let invalid = try Harness(sdkChoice: .invalidSetting)
    defer { invalid.cleanUp() }
    let unavailable = await thrownError {
      _ = try await invalid.client.create(displayName: "Phone", image: Harness.image, profile: .phone)
    }
    #expect(unavailable == .sdkUnavailable)
  }

  // MARK: - 삭제

  @Test("삭제: 켜진 기기는 deviceRunning 이고 아무것도 지우지 않는다")
  func deleteRejectsRunning() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let folder = try harness.addDevice("Pixel")
    harness.locks.hold(folder)

    #expect(await thrownError { _ = try await harness.client.delete(AndroidVirtualDevice.ID("Pixel")) } ==
      .deviceRunning)
    #expect(FileTree.exists(folder))
    #expect(FileTree.exists(harness.avdFolder, "Pixel.ini"))
  }

  @Test("삭제: .avd 로 끝나는 실제 디렉터리면 폴더와 ini 를 지운다")
  func deleteRemovesFolder() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("Pixel")
    try harness.addDevice("Other")

    #expect(try await harness.client.delete(AndroidVirtualDevice.ID("Pixel")) == .deleted)
    #expect(FileTree.names(harness.avdFolder) == ["Other.avd", "Other.ini"])
  }

  @Test("삭제: path 가 링크·.avd 아닌 폴더를 가리키면 ini 만 지우고 folderKept, 폴더가 없으면 ini 만 지운다")
  func deleteKeepsUnexpectedFolder() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let documents = harness.home.appending(path: "Documents", directoryHint: .isDirectory)
    try FileTree.file(documents, "keep.txt")
    try FileTree.file(harness.avdFolder, "Home.ini", contents: "path=\(FileFacts.path(documents))\n")
    let real = try harness.addDevice("Real")
    try FileTree.link(harness.avdFolder, "Linked.avd", to: FileFacts.path(real))
    try FileTree.file(
      harness.avdFolder,
      "Linked.ini",
      contents: "path=\(FileFacts.path(harness.deviceFolder("Linked")))\n"
    )
    try FileTree.file(harness.avdFolder, "Gone.ini", contents: "path=\(FileFacts.path(harness.deviceFolder("Gone")))\n")

    #expect(try await harness.client.delete(AndroidVirtualDevice.ID("Home")) == .folderKept(Harness.pointed(documents)))
    let linked = try await harness.client.delete(AndroidVirtualDevice.ID("Linked"))
    #expect(linked == .folderKept(Harness.pointed(harness.deviceFolder("Linked"))))
    #expect(try await harness.client.delete(AndroidVirtualDevice.ID("Gone")) == .deleted)

    #expect(FileTree.names(documents) == ["keep.txt"])
    #expect(FileTree.exists(real, "config.ini"))
    #expect(FileTree.names(harness.avdFolder) == ["Linked.avd", "Real.avd", "Real.ini"])
  }

  @Test("삭제: 공백·한글 이름의 ini 도 목록 항목으로 지운다, 없는 기기는 deviceNotFound")
  func deleteUnsupportedNames() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.addDevice("My Phone")
    try harness.addDevice("한글")

    #expect(try await harness.client.delete(AndroidVirtualDevice.ID("My Phone")) == .deleted)
    #expect(try await harness.client.delete(AndroidVirtualDevice.ID("한글")) == .deleted)
    #expect(FileTree.names(harness.avdFolder).isEmpty)
    #expect(await thrownError { _ = try await harness.client.delete(AndroidVirtualDevice.ID("한글")) } == .deviceNotFound)
  }

  /// 낡은 이름 집합으로 `AVDFiles.create` 를 불러 EEXIST 경로를 일으킨다.
  static func createFiles(_ harness: Harness, taken: Set<String>) throws(AndroidEmulatorError) -> AndroidVirtualDevice
    .ID
  {
    try AVDFiles.create(
      home: harness.home,
      device: .init(
        displayName: "Pixel",
        image: Harness.image,
        profile: AndroidDeviceProfile.all[0],
        host: .aarch64
      ),
      taken: taken
    )
  }
}
