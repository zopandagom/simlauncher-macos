import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Foundation
import Testing
import WorkspaceInterface
import WorkspaceTesting
@testable import AndroidDevicesFeature

/// 행 "스크린샷": 예약 → 찍기 → Finder, 겹침·막힘·실패.
@MainActor
struct AndroidDevicesScreenshotTests: AndroidDevicesTesting {
  private let tablet = AndroidVirtualDevice.bootedTabletSample.id
  private let label = AndroidDeviceLabel(.bootedTabletSample)

  /// 켜진 태블릿을 고정 시각에 찍은 파일 이름 (런타임 자리는 "API 37.0").
  private let name = ScreenshotFileName(
    deviceName: "Pixel Tablet", runtimeName: "API 37.0", takenAt: fixedNow, timeZone: .current
  )

  private var reserved: URL {
    WorkspaceClientFake.folder.appending(path: self.name.fileName(attempt: 1)!, directoryHint: .notDirectory)
  }

  @Test("켜진 기기: 예약(이름에 API 자리) → 찍기 → Finder 순서로 부르고, 알림·다시 읽기 없이 찍는 중이 풀린다")
  func succeeds() async {
    let setup = await Self.loadedFixture()
    #expect(self.name.stem.hasPrefix("Pixel Tablet (API 37.0) "))

    await setup.model.screenshotTapped(self.tablet)

    #expect(setup.workspace.calls == [.reserveScreenshotFile(stem: self.name.stem), .revealInFinder(self.reserved)])
    #expect(setup.fake.calls == [.fetchDevices, .screenshot(self.tablet, self.reserved)])
    #expect(setup.model.notices.isEmpty)
    #expect(setup.model.screenshots == AndroidScreenshotActivity())
  }

  @Test("이미지 정보가 없는 기기는 파일 이름에서 API 자리를 뺀다")
  func nameWithoutImage() async {
    let device = AndroidVirtualDevice(
      id: .init("No_Image"), displayName: "이미지 모름", systemImage: nil, formFactor: .phone, state: .booted,
      availability: .available
    )
    let setup = await Self.loadedFixture(AndroidDeviceInventory(devices: [device], creationOptions: .sample))
    await setup.model.screenshotTapped(device.id)
    let stem = ScreenshotFileName(deviceName: "이미지 모름", runtimeName: "", takenAt: fixedNow, timeZone: .current).stem
    #expect(setup.workspace.calls.first == .reserveScreenshotFile(stem: stem))
  }

  @Test("꺼진·켜는 중·쓸 수 없는 기기와 목록에 없는 기기는 아무것도 부르지 않는다")
  func blockedDevices() async {
    let inventory = AndroidDeviceInventory(
      devices: [.phoneSample, .bootingSample, .unsupportedNameSample], creationOptions: .sample
    )
    let setup = await Self.loadedFixture(inventory)
    for id in [
      AndroidVirtualDevice.phoneSample.id,
      AndroidVirtualDevice.bootingSample.id,
      AndroidVirtualDevice.unsupportedNameSample.id,
      self.tablet,
    ] {
      await setup.model.screenshotTapped(id)
    }
    #expect(setup.workspace.calls.isEmpty)
    #expect(setup.fake.calls == [.fetchDevices])
  }

  @Test("찍는 중 같은 기기를 다시 누르면 아무것도 부르지 않고, 끝나면 한 번만 저장한다")
  func doubleTap() async {
    let setup = await Self.loadedFixture { $0.suspendScreenshots() }
    let first = Self.start { await setup.model.screenshotTapped(self.tablet) }
    await Self.waitUntil { setup.fake.calls.count == 2 }
    #expect(setup.model.screenshots.isTaking(on: self.tablet))

    await setup.model.screenshotTapped(self.tablet)
    #expect(setup.workspace.calls.count == 1)

    setup.fake.resumeScreenshots()
    await first.value()
    #expect(Self.count(.screenshot(self.tablet, self.reserved), in: setup.fake) == 1)
    #expect(!setup.model.screenshots.isTaking(on: self.tablet))
  }

  @Test("같은 기기에 앱을 설치하는 중에도 찍고, 기기 작업은 앱 설치 그대로다")
  func duringInstall() async {
    let setup = await Self.loadedFixture { $0.suspendInstalls() }
    let install = Self.start {
      await setup.model.appFileSelected(URL(filePath: "/tmp/app.apk"), for: self.tablet)
    }
    await Self.waitUntil { setup.model.activity.task(on: self.tablet) == .installApp && Self.installStarted(setup) }

    await setup.model.screenshotTapped(self.tablet)
    #expect(setup.workspace.calls.last == .revealInFinder(self.reserved))
    #expect(setup.model.activity.task(on: self.tablet) == .installApp)

    setup.fake.resumeInstalls()
    await install.value()
  }

  @Test("켜는 중(앱이 켜는 기기 작업)에는 찍지 않는다")
  func blockedDuringBoot() async {
    let setup = await Self.loadedFixture { $0.suspendBoots() }
    let boot = Self.start { await setup.model.bootTapped(AndroidVirtualDevice.phoneSample.id) }
    await Self.waitUntil { setup.fake.calls.contains(.boot(AndroidVirtualDevice.phoneSample.id)) }
    setup.fake.setInventory(AndroidDeviceInventory(
      devices: [AndroidVirtualDevice.phoneSample.with(state: .booted)], creationOptions: .sample
    ))
    await setup.model.refreshButtonTapped()

    await setup.model.screenshotTapped(AndroidVirtualDevice.phoneSample.id)
    #expect(setup.workspace.calls.isEmpty)

    setup.fake.resumeBoots()
    await boot.value()
  }

  @Test("예약 실패: 저장 폴더 알림, 찍기·Finder·지우기 없음, 다시 읽지 않고 찍는 중이 풀린다")
  func reserveFails() async {
    let setup = await Self.loadedFixture()
    setup.workspace.setReserveError(.folderUnavailable)
    await setup.model.screenshotTapped(self.tablet)
    #expect(setup.workspace.calls == [.reserveScreenshotFile(stem: self.name.stem)])
    #expect(setup.fake.calls == [.fetchDevices])
    #expect(Self.notices(setup.model) == [.screenshotFailed(self.label, .workspace(.folderUnavailable))])
    #expect(!setup.model.screenshots.isTaking(on: self.tablet))
  }

  @Test(
    "찍기 실패: 예약 파일을 지우고 알림 뒤 한 번 다시 읽는다",
    arguments: [AndroidEmulatorError.deviceNotBooted, .captureFailed, .captureFileUnwritable, .adbUnavailable]
  )
  func captureFails(_ error: AndroidEmulatorError) async {
    let setup = await Self.loadedFixture { $0.setScreenshotError(error) }
    await setup.model.screenshotTapped(self.tablet)
    #expect(setup.workspace.calls == [
      .reserveScreenshotFile(stem: self.name.stem), .removeReservedFile(self.reserved),
    ])
    #expect(Self.notices(setup.model) == [.screenshotFailed(self.label, .emulator(error))])
    #expect(Self.fetchCount(setup.fake) == 2)
  }

  @Test("찍기가 취소로 끝나면 예약 파일을 지우고 알리지 않는다")
  func cancelledIsSilent() async {
    let setup = await Self.loadedFixture { $0.setScreenshotError(.cancelled) }
    await setup.model.screenshotTapped(self.tablet)
    #expect(setup.workspace.calls.last == .removeReservedFile(self.reserved))
    #expect(setup.model.notices.isEmpty)
  }

  @Test("Finder 실패: 저장한 파일은 지우지 않고 Finder 실패 알림만 띄운다")
  func revealFails() async {
    let setup = await Self.loadedFixture()
    setup.workspace.setRevealError(.fileNotFound)
    await setup.model.screenshotTapped(self.tablet)
    #expect(setup.workspace.reservedFiles == [self.reserved])
    #expect(Self.notices(setup.model) == [.screenshotRevealFailed(self.label, .fileNotFound)])
    #expect(Self.fetchCount(setup.fake) == 1)
  }

  private static func installStarted(_ setup: AndroidDevicesFixture) -> Bool {
    setup.fake.calls.contains {
      if case .install = $0 {
        true
      } else {
        false
      }
    }
  }
}
