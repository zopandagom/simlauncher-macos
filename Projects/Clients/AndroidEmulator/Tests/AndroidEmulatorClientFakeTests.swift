import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Foundation
import Synchronization
import Testing

/// Feature 테스트·Example 이 기대는 Fake 동작.
struct AndroidEmulatorClientFakeTests {
  @Test("켜기·끄기는 목록 상태를 바꾸고 호출을 기록한다, 기기별 켜기 에러가 먼저다")
  func bootAndShutdown() async throws {
    let fake = AndroidEmulatorClientFake(inventory: .sample)
    let phone = AndroidVirtualDevice.phoneSample.id

    try await fake.boot(phone)
    #expect(try await fake.fetchDevices().devices.first { $0.id == phone }?.state == .booted)
    try await fake.shutdown(phone)
    #expect(fake.inventory.devices.first { $0.id == phone }?.state == .shutdown)

    fake.setBootError(.bootTimedOut)
    fake.setBootError(.emulatorExited(1), for: phone)
    await #expect(throws: AndroidEmulatorError.emulatorExited(1)) { try await fake.boot(phone) }
    let tablet = AndroidVirtualDevice.bootedTabletSample.id
    await #expect(throws: AndroidEmulatorError.bootTimedOut) { try await fake.boot(tablet) }
    #expect(fake.calls == [.boot(phone), .fetchDevices, .shutdown(phone), .boot(phone), .boot(tablet)])
  }

  @Test("만들기: Impl 과 같은 순서로 검사하고 꺼진 새 기기를 더한다")
  func create() async throws {
    let fake = AndroidEmulatorClientFake(inventory: .sample)

    let id = try await fake.create(displayName: " 테스트 폰 ", image: .sample, profile: .tablet)
    #expect(id == AndroidVirtualDevice.ID("Android_Device_2"))
    #expect(fake.inventory.devices.last == AndroidVirtualDevice(
      id: id,
      displayName: "테스트 폰",
      systemImage: .sample,
      formFactor: .tablet,
      state: .shutdown,
      availability: .available
    ))

    await #expect(throws: AndroidEmulatorError.invalidDeviceName(.empty)) {
      _ = try await fake.create(displayName: " ", image: .sample, profile: .phone)
    }
    let missing = try #require(AndroidSystemImageRef(apiFolder: "android-35", tag: "google_apis", abi: "arm64-v8a"))
    await #expect(throws: AndroidEmulatorError.creationOptionUnavailable) {
      _ = try await fake.create(displayName: "Phone", image: missing, profile: .phone)
    }
  }

  @Test("삭제는 설정한 결과를 돌려주고 성공이면 목록에서 뺀다, 초기화는 목록을 바꾸지 않는다")
  func deleteAndErase() async throws {
    let fake = AndroidEmulatorClientFake(inventory: .sample)
    let phone = AndroidVirtualDevice.phoneSample.id
    let kept = URL(filePath: "/Users/fake/Documents", directoryHint: .isDirectory)

    try await fake.erase(phone)
    #expect(fake.inventory == .sample)
    fake.setDeleteResult(.success(.folderKept(kept)))
    #expect(try await fake.delete(phone) == .folderKept(kept))
    #expect(!fake.inventory.devices.contains { $0.id == phone })
    fake.setDeleteResult(.failure(.deviceRunning))
    await #expect(throws: AndroidEmulatorError.deviceRunning) {
      _ = try await fake.delete(AndroidVirtualDevice.bootedTabletSample.id)
    }
    #expect(fake.inventory.devices.contains { $0.id == AndroidVirtualDevice.bootedTabletSample.id })
  }

  @Test("멈춘 기기의 켜기는 재개까지 기다리고 다른 기기는 기다리지 않는다")
  func suspendBootOfDevice() async throws {
    let fake = AndroidEmulatorClientFake(inventory: .sample)
    let phone = AndroidVirtualDevice.phoneSample.id
    let tablet = AndroidVirtualDevice.bootedTabletSample.id
    fake.suspendBoot(of: phone)

    let waiting = Task { try await fake.boot(phone) }
    try await fake.boot(tablet)
    while !fake.calls.contains(.boot(phone)) {
      await Task.yield()
    }
    #expect(fake.inventory.devices.first { $0.id == phone }?.state == .shutdown)
    fake.resumeBoot(of: phone)
    try await waiting.value
    #expect(fake.inventory.devices.first { $0.id == phone }?.state == .booted)
  }

  @Test("앱 작업: 기본 결과, 설정한 결과·에러를 돌려주고 호출을 기록한다")
  func appActions() async throws {
    let fake = AndroidEmulatorClientFake(inventory: .sample)
    let tablet = AndroidVirtualDevice.bootedTabletSample.id
    let apk = URL(filePath: "/Users/fake/app.apk")
    let package = try #require(AndroidPackageName("com.example.app"))
    let other = try #require(AndroidPackageName("com.example.other"))
    let link = try #require(DeepLink("myapp://item/1"))

    #expect(try await fake.deviceTraits(tablet) == .sample)
    try await fake.install(apk, on: tablet)
    try await fake.launch(package, on: tablet)
    try await fake.openURL(link, on: tablet)
    #expect(try await fake.installedPackages(on: tablet).isEmpty)
    #expect(fake.calls == [
      .deviceTraits(tablet), .install(apk, tablet), .launch(package, tablet), .openURL(link, tablet),
      .installedPackages(tablet),
    ])

    let traits = AndroidDeviceTraits(apiLevel: 30, abis: ["x86_64"])
    fake.setDeviceTraits(.success(traits))
    #expect(try await fake.deviceTraits(tablet) == traits)
    fake.setDeviceTraits(.failure(.deviceNotBooted))
    await #expect(throws: AndroidEmulatorError.deviceNotBooted) { _ = try await fake.deviceTraits(tablet) }
    fake.setInstallError(.installFailed(.versionDowngrade))
    await #expect(throws: AndroidEmulatorError.installFailed(.versionDowngrade)) {
      try await fake.install(apk, on: tablet)
    }
    fake.setLaunchError(.launchFailed(.noLauncherActivity))
    await #expect(throws: AndroidEmulatorError.launchFailed(.noLauncherActivity)) {
      try await fake.launch(package, on: tablet)
    }
    fake.setOpenURLError(.urlNotHandled)
    await #expect(throws: AndroidEmulatorError.urlNotHandled) { try await fake.openURL(link, on: tablet) }
    fake.setInstalledPackages(.success([other, package]))
    #expect(try await fake.installedPackages(on: tablet) == [other, package])
    fake.setInstalledPackages(.failure(.appCommandFailed))
    await #expect(throws: AndroidEmulatorError.appCommandFailed) { _ = try await fake.installedPackages(on: tablet) }
  }

  @Test("멈춘 설치·앱 목록은 기록만 하고 재개까지 기다린다, 결과는 깨어난 뒤의 설정을 쓴다")
  func suspendAppActions() async throws {
    let fake = AndroidEmulatorClientFake(inventory: .sample)
    let tablet = AndroidVirtualDevice.bootedTabletSample.id
    let apk = URL(filePath: "/Users/fake/app.apk")
    let package = try #require(AndroidPackageName("com.example.app"))
    fake.suspendInstalls()
    fake.suspendPackageLists()

    let installing = Task { try await fake.install(apk, on: tablet) }
    let listing = Task { try await fake.installedPackages(on: tablet) }
    while !(fake.calls.contains(.install(apk, tablet)) && fake.calls.contains(.installedPackages(tablet))) {
      await Task.yield()
    }
    try await fake.launch(package, on: tablet)
    fake.setInstallError(.installTimedOut)
    fake.setInstalledPackages(.success([package]))
    fake.resumeInstalls()
    fake.resumePackageLists()
    await #expect(throws: AndroidEmulatorError.installTimedOut) { try await installing.value }
    #expect(try await listing.value == [package])
  }

  @Test("기기별 설정(traits·설치·실행 에러, 설치 멈춤)이 전체 설정보다 먼저이고 다른 기기는 전체 설정을 쓴다")
  func perDeviceSettings() async throws {
    let fake = AndroidEmulatorClientFake(inventory: .sample)
    let tablet = AndroidVirtualDevice.bootedTabletSample.id
    let phone = AndroidVirtualDevice.phoneSample.id
    let apk = URL(filePath: "/Users/fake/app.apk")
    let package = try #require(AndroidPackageName("com.example.app"))
    let older = AndroidDeviceTraits(apiLevel: 30, abis: ["x86_64"])
    fake.setDeviceTraits(.success(older), for: tablet)
    fake.setInstallError(.installFailed(.olderSDK), for: tablet)
    fake.setLaunchError(.launchFailed(.notInstalled), for: tablet)
    fake.setInstallError(.installTimedOut)

    #expect(try await fake.deviceTraits(tablet) == older)
    #expect(try await fake.deviceTraits(phone) == .sample)
    await #expect(throws: AndroidEmulatorError.installFailed(.olderSDK)) { try await fake.install(apk, on: tablet) }
    await #expect(throws: AndroidEmulatorError.installTimedOut) { try await fake.install(apk, on: phone) }
    await #expect(throws: AndroidEmulatorError.launchFailed(.notInstalled)) {
      try await fake.launch(package, on: tablet)
    }
    try await fake.launch(package, on: phone)

    fake.setInstallError(nil)
    fake.setDeviceTraits(nil, for: tablet)
    #expect(try await fake.deviceTraits(tablet) == .sample)
    fake.suspendInstall(of: tablet)
    let installing = Task { try await fake.install(apk, on: tablet) }
    while !fake.calls.contains(.install(apk, tablet)) {
      await Task.yield()
    }
    try await fake.install(apk, on: phone)
    fake.setInstallError(nil, for: tablet)
    fake.resumeInstall(of: tablet)
    try await installing.value
  }

  @Test("스크린샷: 기록하고 설정한 에러를 던진다, 멈춤은 재개까지 기다린다")
  func screenshot() async throws {
    let fake = AndroidEmulatorClientFake(inventory: .sample)
    let tablet = AndroidVirtualDevice.bootedTabletSample.id
    let file = URL(filePath: "/Users/fake/Pictures/SimLauncher/shot.png")

    try await fake.screenshot(on: tablet, to: file)
    fake.setScreenshotError(.captureFailed)
    await #expect(throws: AndroidEmulatorError.captureFailed) { try await fake.screenshot(on: tablet, to: file) }
    fake.setScreenshotError(nil)
    fake.suspendScreenshots()
    let taking = Task { try await fake.screenshot(on: tablet, to: file) }
    while fake.calls.count < 3 {
      await Task.yield()
    }
    fake.resumeScreenshots()
    try await taking.value
    #expect(fake.calls == Array(repeating: .screenshot(tablet, file), count: 3))
  }

  @Test("녹화: 시작 신호 뒤 취소까지 기다려 saved, 멈춘 뒤 결과를 바꿀 수 있다")
  func recordUntilCancelled() async throws {
    let fake = AndroidEmulatorClientFake(inventory: .sample)
    let tablet = AndroidVirtualDevice.bootedTabletSample.id
    let file = URL(filePath: "/Users/fake/Movies/SimLauncher/rec.mp4")
    let started = FakeStartFlag()

    let recording = Task { try await fake.recordScreen(on: tablet, to: file) { started.set() } }
    while !started.isSet {
      await Task.yield()
    }
    recording.cancel()
    #expect(try await recording.value == .saved)

    fake.setRecordingResult(.failure(.recordingLost))
    let lost = Task { try await fake.recordScreen(on: tablet, to: file) {} }
    while fake.calls.count < 2 {
      await Task.yield()
    }
    lost.cancel()
    await #expect(throws: AndroidEmulatorError.recordingLost) { try await lost.value }
    #expect(fake.calls == [.recordScreen(tablet, file), .recordScreen(tablet, file)])
  }

  @Test("녹화: 시작 신호 없이 멈추면 stoppedBeforeStart, 스스로 끝나는 결과는 취소를 기다리지 않는다")
  func recordVariants() async throws {
    let fake = AndroidEmulatorClientFake(inventory: .sample)
    let tablet = AndroidVirtualDevice.bootedTabletSample.id
    let file = URL(filePath: "/Users/fake/Movies/SimLauncher/rec.mp4")
    let started = FakeStartFlag()

    fake.setRecordingSignalsStart(false)
    fake.suspendRecordings()
    let silent = Task { try await fake.recordScreen(on: tablet, to: file) { started.set() } }
    while fake.calls.isEmpty {
      await Task.yield()
    }
    silent.cancel()
    fake.resumeRecordings()
    #expect(try await silent.value == .stoppedBeforeStart)
    #expect(!started.isSet)

    fake.setRecordingSignalsStart(true)
    fake.setRecordingEndsByItself(.success(.savedAtTimeLimit))
    #expect(try await fake.recordScreen(on: tablet, to: file) { started.set() } == .savedAtTimeLimit)
    #expect(started.isSet)

    let failed = FakeStartFlag()
    fake.setRecordingEndsByItself(.failure(.recordingFailed))
    await #expect(throws: AndroidEmulatorError.recordingFailed) {
      _ = try await fake.recordScreen(on: tablet, to: file) { failed.set() }
    }
    #expect(!failed.isSet)
  }
}

/// `onStarted` 를 받았는지.
final class FakeStartFlag: Sendable {
  private let flag = Mutex(false)

  var isSet: Bool {
    self.flag.withLock { $0 }
  }

  func set() {
    self.flag.withLock { $0 = true }
  }
}
