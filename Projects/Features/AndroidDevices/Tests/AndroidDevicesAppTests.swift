import AndroidEmulatorInterface
import AndroidEmulatorTesting
import AndroidPackageInterface
import AndroidPackageTesting
import Core
import Foundation
import Testing
@testable import AndroidDevicesFeature

/// 켜진 기기 행의 앱 설치 (파일 고르기·드롭 → 검사 → 기기 값 → 판정 → 설치 → 실행).
@MainActor
struct AndroidDevicesInstallTests: AndroidDevicesTesting {
  static let tablet = AndroidVirtualDevice.bootedTabletSample
  static let label = AndroidDeviceLabel(.bootedTabletSample)
  static let apk = URL(filePath: "/Users/me/Downloads/app.apk", directoryHint: .notDirectory)
  static let info = AndroidPackageInfo.sample()

  /// 기기 목록 읽기 밖의 Client 호출.
  static func appCalls(_ fake: AndroidEmulatorClientFake) -> [AndroidEmulatorClientFake.Call] {
    fake.calls.filter { $0 != .fetchDevices }
  }

  @Test("성공: 검사 → 기기 값 → 설치 → 실행 → 다시 읽기 순서이고, 흐름 동안만 설치 중이다")
  func installSucceeds() async {
    let setup = await Self.loadedFixture()
    setup.package.suspend()
    let task = Self.start { await setup.model.appFileSelected(Self.apk, for: Self.tablet.id) }
    await Self.waitUntil { setup.package.calls.count == 1 }
    #expect(setup.model.activity.task(on: Self.tablet.id) == .installApp)
    setup.package.resume()
    await task.value()
    #expect(setup.package.calls == [Self.apk])
    #expect(Self.appCalls(setup.fake) == [
      .deviceTraits(Self.tablet.id),
      .install(Self.info.location, Self.tablet.id),
      .launch(Self.info.packageName, Self.tablet.id),
    ])
    #expect(Self.fetchCount(setup.fake) == 2)
    #expect(setup.model.activity.task(on: Self.tablet.id) == nil)
    #expect(setup.model.notices.isEmpty)
  }

  @Test("둘 이상 끌어다 놓으면 이유를 알리고 Client 를 부르지 않는다. 빈 드롭은 무시한다")
  func multipleItems() async {
    let setup = await Self.loadedFixture()
    await setup.model.appDropped([Self.apk, Self.apk], on: Self.tablet.id)
    #expect(Self.notices(setup.model) == [.installFailed(Self.label, .multipleItems)])
    await setup.model.appDropped([], on: Self.tablet.id)
    #expect(setup.model.notices.count == 1)
    #expect(setup.package.calls.isEmpty)
    #expect(Self.appCalls(setup.fake).isEmpty)
    #expect(setup.model.activity.task(on: Self.tablet.id) == nil)
  }

  @Test(
    "검사 실패는 그 원인을 알리고 기기에 닿지 않아 다시 읽지 않는다",
    arguments: [
      AndroidPackageError.notLocalFile, .fileNotFound, .appBundle, .splitPackage, .notAPK, .unreadable, .unsafeEntry,
      .unsigned, .inspectionUnavailable,
    ]
  )
  func inspectionFails(_ error: AndroidPackageError) async {
    let setup = await Self.loadedFixture()
    setup.package.setResult(.failure(error))
    await setup.model.appDropped([Self.apk], on: Self.tablet.id)
    #expect(Self.notices(setup.model) == [.installFailed(Self.label, .package(error))])
    #expect(Self.appCalls(setup.fake).isEmpty)
    #expect(Self.fetchCount(setup.fake) == 1)
  }

  @Test("검사하는 사이 기기가 꺼지면(다시 읽기로 바뀜) 막힌 이유를 알리고 기기 값을 읽지 않는다")
  func deviceTurnedOffDuringInspection() async {
    let setup = await Self.loadedFixture()
    setup.package.suspend()
    let task = Self.start { await setup.model.appFileSelected(Self.apk, for: Self.tablet.id) }
    await Self.waitUntil { setup.package.calls.count == 1 }
    setup.fake.setInventory(AndroidDeviceInventory(
      devices: [Self.tablet.with(state: .shutdown)],
      creationOptions: .sample
    ))
    await setup.model.refreshButtonTapped()
    setup.package.resume()
    await task.value()
    #expect(Self.notices(setup.model) == [.installFailed(Self.label, .deviceNotReady(.notBooted))])
    #expect(Self.appCalls(setup.fake).isEmpty)
  }

  @Test("기기 값을 읽지 못하면 알리고 다시 읽으며 설치하지 않는다")
  func traitsFail() async {
    let setup = await Self.loadedFixture { $0.setDeviceTraits(.failure(.deviceNotBooted)) }
    await setup.model.appFileSelected(Self.apk, for: Self.tablet.id)
    #expect(Self.notices(setup.model) == [.installFailed(Self.label, .emulator(.deviceNotBooted))])
    #expect(Self.appCalls(setup.fake) == [.deviceTraits(Self.tablet.id)])
    #expect(Self.fetchCount(setup.fake) == 2)
  }

  @Test(
    "판정 거절(ABI → API)은 설치하지 않고 다시 읽지 않는다",
    arguments: [
      (
        AndroidPackageInfo.sample(minSDK: .level(99), nativeABIs: ["x86_64"]),
        AndroidInstallProblem.noMatchingABI(app: ["x86_64"], device: ["arm64-v8a"])
      ),
      (AndroidPackageInfo.sample(minSDK: .level(99)), .requiresNewerAPI(required: 99, device: 37)),
    ]
  )
  func rejected(_ info: AndroidPackageInfo, _ problem: AndroidInstallProblem) async {
    let setup = await Self.loadedFixture()
    setup.package.setResult(.success(info))
    await setup.model.appFileSelected(Self.apk, for: Self.tablet.id)
    #expect(Self.notices(setup.model) == [.installFailed(Self.label, .rejected(problem))])
    #expect(Self.appCalls(setup.fake) == [.deviceTraits(Self.tablet.id)])
    #expect(Self.fetchCount(setup.fake) == 1)
  }

  @Test("설치 명령이 실패하면 알리고 다시 읽으며 실행하지 않는다")
  func installFails() async {
    let setup = await Self.loadedFixture { $0.setInstallError(.installFailed(.updateIncompatible)) }
    await setup.model.appFileSelected(Self.apk, for: Self.tablet.id)
    #expect(Self.notices(setup.model) == [
      .installFailed(Self.label, .emulator(.installFailed(.updateIncompatible))),
    ])
    #expect(!Self.appCalls(setup.fake).contains(.launch(Self.info.packageName, Self.tablet.id)))
    #expect(Self.fetchCount(setup.fake) == 2)
    #expect(setup.model.activity.task(on: Self.tablet.id) == nil)
  }

  @Test("설치 뒤 실행이 실패하면 설치는 됐다는 알림이고 다시 읽는다")
  func launchAfterInstallFails() async {
    let setup = await Self.loadedFixture { $0.setLaunchError(.launchFailed(.noLauncherActivity)) }
    await setup.model.appFileSelected(Self.apk, for: Self.tablet.id)
    #expect(Self.notices(setup.model) == [.installedButNotLaunched(Self.label, .launchFailed(.noLauncherActivity))])
    #expect(Self.fetchCount(setup.fake) == 2)
  }

  @Test(
    "켜짐이 아니거나 쓸 수 없는 기기는 검사하지 않고 막힌 이유를 알린다 (파일을 고르는 사이 꺼진 경우)",
    arguments: [
      (AndroidVirtualDevice.phoneSample, AndroidAppActionBlockReason.notBooted),
      (.bootingSample, .notBooted),
      (AndroidVirtualDevice.unsupportedNameSample.with(state: .booted), .unavailable),
    ]
  )
  func blockedDevice(_ device: AndroidVirtualDevice, _ reason: AndroidAppActionBlockReason) async {
    let setup = await Self.loadedFixture(AndroidDeviceInventory(devices: [device], creationOptions: .sample))
    await setup.model.appFileSelected(Self.apk, for: device.id)
    #expect(Self.notices(setup.model) == [.installFailed(AndroidDeviceLabel(device), .deviceNotReady(reason))])
    #expect(setup.package.calls.isEmpty)
    #expect(Self.appCalls(setup.fake).isEmpty)
    #expect(setup.model.activity.task(on: device.id) == nil)
  }

  @Test("목록에 없는 기기나 목록을 읽기 전이면 아무것도 하지 않는다")
  func missingDevice() async {
    let setup = await Self.loadedFixture()
    await setup.model.appFileSelected(Self.apk, for: AndroidVirtualDevice.ID("Gone"))
    let notLoaded = Self.fixture()
    await notLoaded.model.appFileSelected(Self.apk, for: Self.tablet.id)
    #expect(setup.model.notices.isEmpty && notLoaded.model.notices.isEmpty)
    #expect(setup.package.calls.isEmpty && notLoaded.package.calls.isEmpty)
  }

  @Test("같은 기기에서 설치 중이면 두 번째 설치는 알리지 않고 무시한다")
  func sameDeviceIgnored() async {
    let setup = await Self.loadedFixture { $0.suspendInstalls() }
    let first = Self.start { await setup.model.appFileSelected(Self.apk, for: Self.tablet.id) }
    await Self.waitUntil { Self.appCalls(setup.fake).contains(.install(Self.info.location, Self.tablet.id)) }
    await setup.model.appDropped([Self.apk], on: Self.tablet.id)
    #expect(setup.package.calls.count == 1)
    #expect(setup.model.notices.isEmpty)
    setup.fake.resumeInstalls()
    await first.value()
    #expect(setup.model.activity.task(on: Self.tablet.id) == nil)
  }

  @Test("다른 기기에는 동시에 설치한다")
  func otherDevicesInParallel() async {
    let second = AndroidVirtualDevice.secondPhoneSample.with(state: .booted)
    let setup = await Self.loadedFixture(AndroidDeviceInventory(
      devices: [Self.tablet, second],
      creationOptions: .sample
    )) {
      $0.suspendInstalls()
    }
    let first = Self.start { await setup.model.appFileSelected(Self.apk, for: Self.tablet.id) }
    let other = Self.start { await setup.model.appDropped([Self.apk], on: second.id) }
    await Self.waitUntil { Self.appCalls(setup.fake).count(where: {
      if case .install = $0 {
        true
      } else {
        false
      }
    }) == 2 }
    #expect(setup.model.activity.task(on: Self.tablet.id) == .installApp)
    #expect(setup.model.activity.task(on: second.id) == .installApp)
    setup.fake.resumeInstalls()
    await first.value()
    await other.value()
    #expect(setup.model.activity.busyDeviceIDs.isEmpty)
    #expect(setup.model.notices.isEmpty)
  }
}

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
    let task = Self.start { await setup.model.launchAppTapped(Self.tablet.id) }
    await Self.waitUntil { setup.fake.calls.contains(.installedPackages(Self.tablet.id)) }
    #expect(setup.model.launchAppDraft?.packages == .loading)
    #expect(setup.model.launchAppDraft?.device == Self.label)
    #expect(setup.model.activity.task(on: Self.tablet.id) == nil)
    setup.fake.resumePackageLists()
    await task.value()
    #expect(setup.model.launchAppDraft?.packages == .loaded(Self.packages))
    #expect(setup.model.launchAppDraft?.selection == nil)
    #expect(setup.model.launchAppDraft?.canSubmit == false)
  }

  @Test("빈 목록이면 실행할 수 없고, 하나뿐이면 그것을 고른다")
  func emptyAndSingle() async {
    let empty = await Self.loadedFixture()
    await empty.model.launchAppTapped(Self.tablet.id)
    #expect(empty.model.launchAppDraft?.packages == .loaded([]))
    #expect(empty.model.launchAppDraft?.canSubmit == false)
    let single = await Self.loadedFixture { $0.setInstalledPackages(.success([Self.packages[0]])) }
    await single.model.launchAppTapped(Self.tablet.id)
    #expect(single.model.launchAppDraft?.selection == Self.packages[0])
    #expect(single.model.launchAppDraft?.canSubmit == true)
  }

  @Test("목록을 읽지 못하면 시트에 이유를 보이고, 다시 시도하면 다시 읽는다")
  func failsAndRetries() async {
    let setup = await Self.loadedFixture { $0.setInstalledPackages(.failure(.deviceNotBooted)) }
    await setup.model.launchAppTapped(Self.tablet.id)
    #expect(setup.model.launchAppDraft?.packages == .failed(.deviceNotBooted))
    #expect(setup.model.notices.isEmpty)
    setup.fake.setInstalledPackages(.success(Self.packages))
    await setup.model.launchAppRetryTapped()
    #expect(setup.model.launchAppDraft?.packages == .loaded(Self.packages))
    #expect(Self.count(.installedPackages(Self.tablet.id), in: setup.fake) == 2)
  }

  @Test("시트를 닫은 뒤 도착한 목록은 버린다")
  func resultAfterDismissIsDropped() async {
    let setup = await Self.loadedFixture { $0.suspendPackageLists() }
    let task = Self.start { await setup.model.launchAppTapped(Self.tablet.id) }
    await Self.waitUntil { setup.fake.calls.contains(.installedPackages(Self.tablet.id)) }
    setup.model.launchAppSheetDismissed()
    setup.fake.resumePackageLists()
    await task.value()
    #expect(setup.model.launchAppDraft == nil)
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
    let first = Self.start { await setup.model.launchAppTapped(Self.tablet.id) }
    await Self.waitUntil { setup.fake.calls.contains(.installedPackages(Self.tablet.id)) }
    let firstRequest = setup.model.launchAppDraft?.request
    setup.model.launchAppCancelTapped()
    let other = Self.start { await setup.model.launchAppTapped(second.id) }
    await Self.waitUntil { setup.fake.calls.contains(.installedPackages(second.id)) }
    #expect(setup.model.launchAppDraft?.request != firstRequest)
    setup.fake.resumePackageLists()
    await first.value()
    await other.value()
    #expect(setup.model.launchAppDraft?.deviceID == second.id)
    #expect(setup.model.launchAppDraft?.packages == .loaded(Self.packages))
  }

  @Test("고르고 실행하면 시트를 닫고 그 앱을 실행한 뒤 다시 읽는다")
  func confirmLaunches() async {
    let setup = await Self.loadedFixture { $0.setInstalledPackages(.success(Self.packages)) }
    await setup.model.launchAppTapped(Self.tablet.id)
    setup.model.launchAppSelectionChanged(Self.packages[1])
    await setup.model.launchAppConfirmTapped()
    #expect(setup.model.launchAppDraft == nil)
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
    await setup.model.launchAppTapped(Self.tablet.id)
    await setup.model.launchAppConfirmTapped()
    #expect(Self.notices(setup.model) == [.launchFailed(Self.label, .emulator(.launchFailed(.notInstalled)))])
  }

  @Test("시트를 연 사이 기기가 꺼졌으면 막힌 이유를 알리고 실행하지 않는다")
  func deviceTurnedOff() async {
    let setup = await Self.loadedFixture { $0.setInstalledPackages(.success([Self.packages[0]])) }
    await setup.model.launchAppTapped(Self.tablet.id)
    setup.fake.setInventory(AndroidDeviceInventory(
      devices: [Self.tablet.with(state: .shutdown)],
      creationOptions: .sample
    ))
    await setup.model.refreshButtonTapped()
    await setup.model.launchAppConfirmTapped()
    #expect(setup.model.launchAppDraft == nil)
    #expect(Self.notices(setup.model) == [.launchFailed(Self.label, .deviceNotReady(.notBooted))])
    #expect(!setup.fake.calls.contains(.launch(Self.packages[0], Self.tablet.id)))
  }

  @Test("꺼진 기기·작업 중인 기기에서는 열리지 않는다")
  func notOpenedForBlockedDevice() async {
    let setup = await Self.loadedFixture { $0.suspendInstalls() }
    await setup.model.launchAppTapped(AndroidVirtualDevice.phoneSample.id)
    #expect(setup.model.launchAppDraft == nil)
    let install = Self.start {
      await setup.model.appFileSelected(AndroidDevicesInstallTests.apk, for: Self.tablet.id)
    }
    await Self.waitUntil { setup.model.activity.task(on: Self.tablet.id) == .installApp }
    await setup.model.launchAppTapped(Self.tablet.id)
    setup.model.openURLTapped(Self.tablet.id)
    #expect(setup.model.launchAppDraft == nil && setup.model.openURLDraft == nil)
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
    setup.model.openURLTapped(Self.tablet.id)
    #expect(setup.model.openURLDraft?.device == Self.label)
    setup.model.openURLTextChanged("example.com")
    #expect(setup.model.openURLDraft?.problem == .missingScheme)
    #expect(setup.model.openURLDraft?.canSubmit == false)
    setup.model.openURLTextChanged("  https://example.com/a?b=1&c=2 ")
    let link = try #require(DeepLink("https://example.com/a?b=1&c=2"))
    await setup.model.openURLConfirmTapped()
    #expect(setup.model.openURLDraft == nil)
    #expect(setup.fake.calls.contains(.openURL(link, Self.tablet.id)))
    #expect(Self.fetchCount(setup.fake) == 2)
    #expect(setup.model.activity.task(on: Self.tablet.id) == nil)
  }

  @Test("받을 앱이 없으면 알린다")
  func urlNotHandled() async {
    let setup = await Self.loadedFixture { $0.setOpenURLError(.urlNotHandled) }
    setup.model.openURLTapped(Self.tablet.id)
    setup.model.openURLTextChanged("myapp://x")
    await setup.model.openURLConfirmTapped()
    #expect(Self.notices(setup.model) == [.openURLFailed(Self.label, .emulator(.urlNotHandled))])
  }

  @Test("시트를 연 사이 기기가 목록에서 사라지거나 쓸 수 없게 되면 이유를 알리고 열지 않는다")
  func deviceChanged() async {
    let gone = await Self.loadedFixture()
    gone.model.openURLTapped(Self.tablet.id)
    gone.model.openURLTextChanged("myapp://x")
    gone.fake.setInventory(.emptySample)
    await gone.model.refreshButtonTapped()
    await gone.model.openURLConfirmTapped()
    #expect(Self.notices(gone.model) == [.openURLFailed(Self.label, .emulator(.deviceNotFound))])
    let booting = await Self.loadedFixture()
    booting.model.openURLTapped(Self.tablet.id)
    booting.model.openURLTextChanged("myapp://x")
    booting.fake.setInventory(AndroidDeviceInventory(
      devices: [Self.tablet.with(state: .booting)],
      creationOptions: .sample
    ))
    await booting.model.refreshButtonTapped()
    await booting.model.openURLConfirmTapped()
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
    setup.model.openURLTapped(Self.tablet.id)
    setup.model.openURLCancelTapped()
    #expect(setup.model.openURLDraft == nil)
    setup.model.openURLTapped(Self.tablet.id)
    setup.model.openURLSheetDismissed()
    #expect(setup.model.openURLDraft == nil)
    setup.model.openURLTapped(AndroidVirtualDevice.phoneSample.id)
    #expect(setup.model.openURLDraft == nil)
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
    await launch.model.launchAppTapped(Self.tablet.id)
    launch.model.createButtonTapped()
    launch.model.deleteTapped(Self.phone.id)
    launch.model.eraseTapped(Self.phone.id)
    launch.model.openURLTapped(Self.tablet.id)
    #expect(launch.model.creationDraft == nil && launch.model.confirmation == nil && launch.model.openURLDraft == nil)
    #expect(!launch.model.canCreateDevice)
    launch.model.launchAppCancelTapped()
    #expect(launch.model.launchAppDraft == nil)

    let link = await Self.loadedFixture()
    link.model.openURLTapped(Self.tablet.id)
    await link.model.launchAppTapped(Self.tablet.id)
    link.model.createButtonTapped()
    link.model.deleteTapped(Self.phone.id)
    #expect(link.model.launchAppDraft == nil && link.model.creationDraft == nil && link.model.confirmation == nil)
    #expect(Self.count(.installedPackages(Self.tablet.id), in: link.fake) == 0)
  }

  @Test("만들기 시트나 확인 대화상자가 있으면 두 앱 시트가 열리지 않는다")
  func otherSheetsBlockAppSheets() async {
    let create = await Self.loadedFixture()
    create.model.createButtonTapped()
    await create.model.launchAppTapped(Self.tablet.id)
    create.model.openURLTapped(Self.tablet.id)
    #expect(create.model.launchAppDraft == nil && create.model.openURLDraft == nil)

    let confirm = await Self.loadedFixture()
    confirm.model.deleteTapped(Self.phone.id)
    await confirm.model.launchAppTapped(Self.tablet.id)
    confirm.model.openURLTapped(Self.tablet.id)
    #expect(confirm.model.launchAppDraft == nil && confirm.model.openURLDraft == nil)
  }
}

/// 앱 작업의 시작 판정과 초안 값 타입.
@MainActor
struct AndroidAppActionValueTests {
  static let packages = ["com.example.a", "com.example.b"].compactMap(AndroidPackageName.init)

  @Test("앱 설치·실행·링크 열기는 쓸 수 있는 켜진 기기에서, 작업이 없을 때만 시작한다")
  func canStart() {
    var activity = AndroidDeviceActivity()
    let tablet = AndroidVirtualDevice.bootedTabletSample
    for task in [AndroidDeviceTask.installApp, .launchApp, .openURL] {
      #expect(activity.canStart(task, on: tablet))
      #expect(!activity.canStart(task, on: .phoneSample))
      #expect(!activity.canStart(task, on: .bootingSample))
      #expect(!activity.canStart(task, on: AndroidVirtualDevice.unsupportedNameSample.with(state: .booted)))
    }
    let begun = activity.begin(.installApp, on: tablet)
    #expect(begun)
    #expect(!activity.canStart(.openURL, on: tablet))
    #expect(!activity.canStart(.shutdown, on: tablet))
  }

  @Test("링크 초안: 입력에 따라 문제·링크·열기 가능이 바뀐다")
  func openURLDraft() {
    var draft = AndroidOpenURLDraft(
      deviceID: AndroidVirtualDevice.bootedTabletSample.id,
      device: AndroidDeviceLabel(.bootedTabletSample)
    )
    #expect(draft.problem == .empty && draft.link == nil && !draft.canSubmit)
    draft.textChanged("item/1")
    #expect(draft.problem == .missingScheme && !draft.canSubmit)
    draft.textChanged(" myapp://item/1 ")
    #expect(draft.problem == nil && draft.link == DeepLink("myapp://item/1") && draft.canSubmit)
  }

  @Test("앱 실행 초안: 목록에 있는 선택만 실행할 수 있고, 번호가 다른 결과는 버린다")
  func launchAppDraft() {
    var draft = AndroidLaunchAppDraft(
      deviceID: AndroidVirtualDevice.bootedTabletSample.id,
      device: AndroidDeviceLabel(.bootedTabletSample),
      request: 1
    )
    draft.selectionChanged(Self.packages[0])
    #expect(!draft.canSubmit)
    draft.packagesLoaded(.success(Self.packages), request: 2)
    #expect(draft.packages == .loading)
    draft.packagesLoaded(.success(Self.packages), request: 1)
    #expect(draft.canSubmit)
    draft.selectionChanged(AndroidPackageName("com.example.other"))
    #expect(!draft.canSubmit)
    draft.reloadStarted(request: 3)
    #expect(draft.packages == .loading && !draft.canSubmit)
    draft.packagesLoaded(.failure(.appCommandFailed), request: 3)
    #expect(draft.packages == .failed(.appCommandFailed) && !draft.canSubmit)
    draft.reloadStarted(request: 4)
    draft.packagesLoaded(.success([Self.packages[1]]), request: 4)
    #expect(draft.selection == Self.packages[1])
  }
}
