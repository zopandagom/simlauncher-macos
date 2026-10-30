import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Foundation
import Testing
@testable import AndroidDevicesFeature

// 앱 실행·링크 열기 시트(`AndroidAppSheetsModel`)와 그 요청을 받는 `AndroidDevicesModel` 쪽. fixture 가 두 Model 을 App 과
// 같이 클로저로 잇는다 (`AndroidDevicesTestSupport.swift`).

/// 행 "앱 실행…" 시트.
@MainActor
struct AndroidDevicesLaunchAppTests: AndroidDevicesTesting {
  static let tablet = AndroidVirtualDevice.bootedTabletSample
  static let label = AndroidDeviceLabel(.bootedTabletSample)
  static let packages = ["com.example.a", "com.example.b"].compactMap(AndroidPackageName.init)

  @Test("열면 불러오는 중이다가 목록이 오면 보이고, 작업 기록은 남기지 않는다")
  func opensAndLoads() async {
    let setup = await Self.loadedFixture {
      $0.setInstalledPackages(.success(Self.packages))
      $0.suspendPackageLists()
    }
    let task = Self.start { await setup.sheets.launchAppTapped(Self.tablet.id) }
    await Self.waitUntil { setup.fake.calls.contains(.installedPackages(Self.tablet.id)) }
    #expect(setup.sheets.launchAppDraft?.packages == .loading)
    #expect(setup.sheets.launchAppDraft?.device == Self.label)
    #expect(setup.model.activity.task(on: Self.tablet.id) == nil)
    setup.fake.resumePackageLists()
    await task.value()
    #expect(setup.sheets.launchAppDraft?.packages == .loaded(Self.packages))
    #expect(setup.sheets.launchAppDraft?.selection == nil)
    #expect(setup.sheets.launchAppDraft?.canSubmit == false)
  }

  @Test("빈 목록이면 실행할 수 없고, 하나뿐이면 그것을 고른다")
  func emptyAndSingle() async {
    let empty = await Self.loadedFixture()
    await empty.sheets.launchAppTapped(Self.tablet.id)
    #expect(empty.sheets.launchAppDraft?.packages == .loaded([]))
    #expect(empty.sheets.launchAppDraft?.canSubmit == false)
    let single = await Self.loadedFixture { $0.setInstalledPackages(.success([Self.packages[0]])) }
    await single.sheets.launchAppTapped(Self.tablet.id)
    #expect(single.sheets.launchAppDraft?.selection == Self.packages[0])
    #expect(single.sheets.launchAppDraft?.canSubmit == true)
  }

  @Test("목록을 읽지 못하면 시트에 이유를 보이고, 다시 시도하면 다시 읽는다")
  func failsAndRetries() async {
    let setup = await Self.loadedFixture { $0.setInstalledPackages(.failure(.deviceNotBooted)) }
    await setup.sheets.launchAppTapped(Self.tablet.id)
    #expect(setup.sheets.launchAppDraft?.packages == .failed(.deviceNotBooted))
    #expect(setup.model.notices.isEmpty)
    setup.fake.setInstalledPackages(.success(Self.packages))
    await setup.sheets.launchAppRetryTapped()
    #expect(setup.sheets.launchAppDraft?.packages == .loaded(Self.packages))
    #expect(Self.count(.installedPackages(Self.tablet.id), in: setup.fake) == 2)
  }

  @Test("시트를 닫은 뒤 도착한 목록은 버린다")
  func resultAfterDismissIsDropped() async {
    let setup = await Self.loadedFixture { $0.suspendPackageLists() }
    let task = Self.start { await setup.sheets.launchAppTapped(Self.tablet.id) }
    await Self.waitUntil { setup.fake.calls.contains(.installedPackages(Self.tablet.id)) }
    setup.sheets.launchAppSheetDismissed()
    setup.fake.resumePackageLists()
    await task.value()
    #expect(setup.sheets.launchAppDraft == nil)
  }

  @Test("닫고 다른 기기 시트를 열면 앞 기기의 늦은 결과는 버리고 지금 시트의 번호만 반영한다")
  func resultForOtherSheetIsDropped() async {
    let second = AndroidVirtualDevice.secondPhoneSample.with(state: .booted)
    let setup = await Self.loadedFixture(AndroidDeviceInventory(
      devices: [Self.tablet, second],
      creationOptions: .sample
    )) {
      $0.suspendPackageLists()
      $0.setInstalledPackages(.success(Self.packages))
    }
    let first = Self.start { await setup.sheets.launchAppTapped(Self.tablet.id) }
    await Self.waitUntil { setup.fake.calls.contains(.installedPackages(Self.tablet.id)) }
    let firstRequest = setup.sheets.launchAppDraft?.request
    setup.sheets.launchAppCancelTapped()
    let other = Self.start { await setup.sheets.launchAppTapped(second.id) }
    await Self.waitUntil { setup.fake.calls.contains(.installedPackages(second.id)) }
    #expect(setup.sheets.launchAppDraft?.request != firstRequest)
    setup.fake.resumePackageLists()
    await first.value()
    await other.value()
    #expect(setup.sheets.launchAppDraft?.deviceID == second.id)
    #expect(setup.sheets.launchAppDraft?.packages == .loaded(Self.packages))
  }

  @Test("고르고 실행하면 시트를 닫고 그 앱을 실행한 뒤 다시 읽는다")
  func confirmLaunches() async {
    let setup = await Self.loadedFixture { $0.setInstalledPackages(.success(Self.packages)) }
    await setup.sheets.launchAppTapped(Self.tablet.id)
    setup.sheets.launchAppSelectionChanged(Self.packages[1])
    await setup.sheets.launchAppConfirmTapped()
    #expect(setup.sheets.launchAppDraft == nil)
    #expect(setup.fake.calls.contains(.launch(Self.packages[1], Self.tablet.id)))
    #expect(Self.fetchCount(setup.fake) == 2)
    #expect(setup.model.activity.task(on: Self.tablet.id) == nil)
    #expect(setup.model.notices.isEmpty)
  }

  @Test("실행이 실패하면 알린다")
  func launchFails() async {
    let setup = await Self.loadedFixture {
      $0.setInstalledPackages(.success([Self.packages[0]]))
      $0.setLaunchError(.launchFailed(.notInstalled))
    }
    await setup.sheets.launchAppTapped(Self.tablet.id)
    await setup.sheets.launchAppConfirmTapped()
    #expect(Self.notices(setup.model) == [.launchFailed(Self.label, .emulator(.launchFailed(.notInstalled)))])
  }

  @Test("시트를 연 사이 기기가 꺼졌으면 막힌 이유를 알리고 실행하지 않는다")
  func deviceTurnedOff() async {
    let setup = await Self.loadedFixture { $0.setInstalledPackages(.success([Self.packages[0]])) }
    await setup.sheets.launchAppTapped(Self.tablet.id)
    setup.fake.setInventory(AndroidDeviceInventory(
      devices: [Self.tablet.with(state: .shutdown)],
      creationOptions: .sample
    ))
    await setup.model.refreshButtonTapped()
    await setup.sheets.launchAppConfirmTapped()
    #expect(setup.sheets.launchAppDraft == nil)
    #expect(Self.notices(setup.model) == [.launchFailed(Self.label, .deviceNotReady(.notBooted))])
    #expect(!setup.fake.calls.contains(.launch(Self.packages[0], Self.tablet.id)))
  }

  @Test("꺼진 기기·작업 중인 기기에서는 열리지 않는다")
  func notOpenedForBlockedDevice() async {
    let setup = await Self.loadedFixture { $0.suspendInstalls() }
    await setup.sheets.launchAppTapped(AndroidVirtualDevice.phoneSample.id)
    #expect(setup.sheets.launchAppDraft == nil)
    let install = Self.start {
      await setup.model.appFileSelected(AndroidDevicesInstallTests.apk, for: Self.tablet.id)
    }
    await Self.waitUntil { setup.model.activity.task(on: Self.tablet.id) == .installApp }
    await setup.sheets.launchAppTapped(Self.tablet.id)
    setup.sheets.openURLTapped(Self.tablet.id)
    #expect(setup.sheets.launchAppDraft == nil && setup.sheets.openURLDraft == nil)
    setup.fake.resumeInstalls()
    await install.value()
  }
}

/// 행 "링크 열기…" 시트.
@MainActor
struct AndroidDevicesOpenURLTests: AndroidDevicesTesting {
  static let tablet = AndroidVirtualDevice.bootedTabletSample
  static let label = AndroidDeviceLabel(.bootedTabletSample)

  @Test("열고 입력 문제를 보인 뒤, 열기를 누르면 시트를 닫고 검사한 링크를 연다")
  func opensLink() async throws {
    let setup = await Self.loadedFixture()
    setup.sheets.openURLTapped(Self.tablet.id)
    #expect(setup.sheets.openURLDraft?.device == Self.label)
    setup.sheets.openURLTextChanged("example.com")
    #expect(setup.sheets.openURLDraft?.problem == .missingScheme)
    #expect(setup.sheets.openURLDraft?.canSubmit == false)
    setup.sheets.openURLTextChanged("  https://example.com/a?b=1&c=2 ")
    let link = try #require(DeepLink("https://example.com/a?b=1&c=2"))
    await setup.sheets.openURLConfirmTapped()
    #expect(setup.sheets.openURLDraft == nil)
    #expect(setup.fake.calls.contains(.openURL(link, Self.tablet.id)))
    #expect(Self.fetchCount(setup.fake) == 2)
    #expect(setup.model.activity.task(on: Self.tablet.id) == nil)
  }

  @Test("받을 앱이 없으면 알린다")
  func urlNotHandled() async {
    let setup = await Self.loadedFixture { $0.setOpenURLError(.urlNotHandled) }
    setup.sheets.openURLTapped(Self.tablet.id)
    setup.sheets.openURLTextChanged("myapp://x")
    await setup.sheets.openURLConfirmTapped()
    #expect(Self.notices(setup.model) == [.openURLFailed(Self.label, .emulator(.urlNotHandled))])
  }

  @Test("시트를 연 사이 기기가 목록에서 사라지거나 쓸 수 없게 되면 이유를 알리고 열지 않는다")
  func deviceChanged() async {
    let gone = await Self.loadedFixture()
    gone.sheets.openURLTapped(Self.tablet.id)
    gone.sheets.openURLTextChanged("myapp://x")
    gone.fake.setInventory(.emptySample)
    await gone.model.refreshButtonTapped()
    await gone.sheets.openURLConfirmTapped()
    #expect(Self.notices(gone.model) == [.openURLFailed(Self.label, .emulator(.deviceNotFound))])
    let booting = await Self.loadedFixture()
    booting.sheets.openURLTapped(Self.tablet.id)
    booting.sheets.openURLTextChanged("myapp://x")
    booting.fake.setInventory(AndroidDeviceInventory(
      devices: [Self.tablet.with(state: .booting)],
      creationOptions: .sample
    ))
    await booting.model.refreshButtonTapped()
    await booting.sheets.openURLConfirmTapped()
    #expect(Self.notices(booting.model) == [.openURLFailed(Self.label, .deviceNotReady(.notBooted))])
    #expect(!(gone.fake.calls + booting.fake.calls).contains {
      if case .openURL = $0 {
        true
      } else {
        false
      }
    })
  }

  @Test("취소·닫기는 초안을 지우고, 꺼진 기기에서는 열리지 않는다")
  func cancelAndDismiss() async {
    let setup = await Self.loadedFixture()
    setup.sheets.openURLTapped(Self.tablet.id)
    setup.sheets.openURLCancelTapped()
    #expect(setup.sheets.openURLDraft == nil)
    setup.sheets.openURLTapped(Self.tablet.id)
    setup.sheets.openURLSheetDismissed()
    #expect(setup.sheets.openURLDraft == nil)
    setup.sheets.openURLTapped(AndroidVirtualDevice.phoneSample.id)
    #expect(setup.sheets.openURLDraft == nil)
  }
}

/// 시트·확인 대화상자는 하나만 뜬다.
@MainActor
struct AndroidDevicesSheetExclusionTests: AndroidDevicesTesting {
  static let tablet = AndroidVirtualDevice.bootedTabletSample
  static let phone = AndroidVirtualDevice.phoneSample

  @Test("앱 실행·링크 시트가 열려 있으면 만들기·삭제·초기화·다른 앱 시트가 열리지 않는다")
  func appSheetsBlockOthers() async {
    let launch = await Self.loadedFixture()
    await launch.sheets.launchAppTapped(Self.tablet.id)
    launch.model.createButtonTapped()
    launch.model.deleteTapped(Self.phone.id)
    launch.model.eraseTapped(Self.phone.id)
    launch.sheets.openURLTapped(Self.tablet.id)
    #expect(launch.model.creationDraft == nil && launch.model.confirmation == nil && launch.sheets.openURLDraft == nil)
    #expect(!launch.model.canCreateDevice)
    launch.sheets.launchAppCancelTapped()
    #expect(launch.sheets.launchAppDraft == nil)

    let link = await Self.loadedFixture()
    link.sheets.openURLTapped(Self.tablet.id)
    await link.sheets.launchAppTapped(Self.tablet.id)
    link.model.createButtonTapped()
    link.model.deleteTapped(Self.phone.id)
    #expect(link.sheets.launchAppDraft == nil && link.model.creationDraft == nil && link.model.confirmation == nil)
    #expect(Self.count(.installedPackages(Self.tablet.id), in: link.fake) == 0)
  }

  @Test("만들기 시트나 확인 대화상자가 있으면 두 앱 시트가 열리지 않는다")
  func otherSheetsBlockAppSheets() async {
    let create = await Self.loadedFixture()
    create.model.createButtonTapped()
    await create.sheets.launchAppTapped(Self.tablet.id)
    create.sheets.openURLTapped(Self.tablet.id)
    #expect(create.sheets.launchAppDraft == nil && create.sheets.openURLDraft == nil)

    let confirm = await Self.loadedFixture()
    confirm.model.deleteTapped(Self.phone.id)
    await confirm.sheets.launchAppTapped(Self.tablet.id)
    confirm.sheets.openURLTapped(Self.tablet.id)
    #expect(confirm.sheets.launchAppDraft == nil && confirm.sheets.openURLDraft == nil)
  }
}

/// 시트 Model 이 넘긴 요청을 받는 `AndroidDevicesModel` 쪽과 시트를 열 기기를 정하는 읽기 API.
@MainActor
struct AndroidAppSheetRequestTests: AndroidDevicesTesting {
  static let tablet = AndroidVirtualDevice.bootedTabletSample
  static let label = AndroidDeviceLabel(.bootedTabletSample)
  static let package = AndroidPackageName("com.example.a")
  static let link = DeepLink("myapp://item/1")

  @Test("실행 요청: 지금 목록으로 확인한 기기에서 앱을 실행하고 다시 읽으며, 끝나면 행을 푼다")
  func launchRequested() async throws {
    let package = try #require(Self.package)
    let setup = await Self.loadedFixture()
    await setup.model.launchAppRequested(AndroidLaunchAppRequest(
      deviceID: Self.tablet.id,
      device: Self.label,
      package: package
    ))
    #expect(setup.fake.calls == [.fetchDevices, .launch(package, Self.tablet.id), .fetchDevices])
    #expect(setup.model.activity.task(on: Self.tablet.id) == nil)
    #expect(setup.model.notices.isEmpty)
  }

  @Test("실행 요청: 기기가 꺼졌으면 막힌 이유를 알리고 실행하지도 다시 읽지도 않는다")
  func launchRequestedBlocked() async throws {
    let package = try #require(Self.package)
    let setup = await Self.loadedFixture()
    let phone = AndroidVirtualDevice.phoneSample
    await setup.model.launchAppRequested(AndroidLaunchAppRequest(
      deviceID: phone.id,
      device: AndroidDeviceLabel(phone),
      package: package
    ))
    #expect(Self.notices(setup.model) == [.launchFailed(AndroidDeviceLabel(phone), .deviceNotReady(.notBooted))])
    #expect(setup.fake.calls == [.fetchDevices])
  }

  @Test("링크 열기 요청: 링크를 열고 다시 읽으며, 기기가 목록에서 사라졌으면 이유를 알리고 열지 않는다")
  func openURLRequested() async throws {
    let link = try #require(Self.link)
    let request = AndroidOpenURLRequest(deviceID: Self.tablet.id, device: Self.label, link: link)
    let setup = await Self.loadedFixture()
    await setup.model.openURLRequested(request)
    #expect(setup.fake.calls == [.fetchDevices, .openURL(link, Self.tablet.id), .fetchDevices])
    #expect(setup.model.activity.task(on: Self.tablet.id) == nil)
    #expect(setup.model.notices.isEmpty)
    let gone = await Self.loadedFixture(.emptySample)
    await gone.model.openURLRequested(request)
    #expect(Self.notices(gone.model) == [.openURLFailed(Self.label, .emulator(.deviceNotFound))])
    #expect(gone.fake.calls == [.fetchDevices])
  }

  @Test("같은 기기가 다른 작업 중이면 실행·링크 열기 요청은 알리지 않고 끝난다")
  func requestsIgnoredWhileBusy() async throws {
    let package = try #require(Self.package)
    let link = try #require(Self.link)
    let setup = await Self.loadedFixture { $0.suspendInstalls() }
    let install = Self.start {
      await setup.model.appFileSelected(AndroidDevicesInstallTests.apk, for: Self.tablet.id)
    }
    await Self.waitUntil { setup.model.activity.task(on: Self.tablet.id) == .installApp }
    await setup.model.launchAppRequested(AndroidLaunchAppRequest(
      deviceID: Self.tablet.id,
      device: Self.label,
      package: package
    ))
    await setup.model.openURLRequested(AndroidOpenURLRequest(deviceID: Self.tablet.id, device: Self.label, link: link))
    #expect(!setup.fake.calls.contains(.launch(package, Self.tablet.id)))
    #expect(!setup.fake.calls.contains(.openURL(link, Self.tablet.id)))
    #expect(setup.model.notices.isEmpty)
    setup.fake.resumeInstalls()
    await install.value()
  }

  @Test("시트를 열 기기: 목록에 있고 그 작업을 시작할 수 있으며 만들기 시트·확인 대화상자가 없을 때만 돌려준다")
  func appSheetTarget() async {
    let before = Self.fixture()
    #expect(before.model.appSheetTarget(Self.tablet.id, for: .launchApp) == nil)
    let setup = await Self.loadedFixture()
    #expect(setup.model.appSheetTarget(Self.tablet.id, for: .launchApp) == Self.tablet)
    #expect(setup.model.appSheetTarget(Self.tablet.id, for: .openURL) == Self.tablet)
    #expect(setup.model.appSheetTarget(AndroidVirtualDevice.phoneSample.id, for: .launchApp) == nil)
    #expect(setup.model.appSheetTarget(AndroidVirtualDevice.ID("Missing"), for: .openURL) == nil)
    setup.model.createButtonTapped()
    #expect(setup.model.appSheetTarget(Self.tablet.id, for: .launchApp) == nil)
    setup.model.creationCancelTapped()
    setup.model.deleteTapped(AndroidVirtualDevice.phoneSample.id)
    #expect(setup.model.appSheetTarget(Self.tablet.id, for: .openURL) == nil)
  }
}
