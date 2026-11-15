import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Foundation
import Testing
@testable import AndroidDevicesFeature

/// 앱 단위 구역 테스트가 함께 쓰는 샘플 패키지·권한과 도움 함수.
@MainActor
protocol AndroidTestConditionsAppTesting: AndroidDevicesTesting {}

@MainActor
extension AndroidTestConditionsAppTesting {
  static var deviceID: AndroidVirtualDevice.ID {
    AndroidVirtualDevice.bootedTabletSample.id
  }

  static var alpha: AndroidPackageName {
    AndroidPackageName("com.example.alpha")!
  }

  static var beta: AndroidPackageName {
    AndroidPackageName("com.example.beta")!
  }

  static func permission(_ raw: String) -> AndroidRuntimePermission {
    AndroidRuntimePermission(raw)!
  }

  static var camera: AndroidRuntimePermission {
    self.permission("android.permission.CAMERA")
  }

  static var fineLocation: AndroidRuntimePermission {
    self.permission("android.permission.ACCESS_FINE_LOCATION")
  }

  /// 카메라 거부·정확한 위치 허용.
  static var alphaGrants: [AndroidPermissionGrant] {
    [
      AndroidPermissionGrant(permission: self.camera, isGranted: false),
      AndroidPermissionGrant(permission: self.fineLocation, isGranted: true),
    ]
  }

  /// 두 패키지(권한은 alpha 만)를 둔 기기 목록과 시트를 열고 alpha 를 고른 상태.
  static func openedWithAlpha(
    _ configure: (AndroidEmulatorClientFake) -> Void = { _ in }
  ) async -> AndroidDevicesFixture {
    let setup = await Self.loadedFixture {
      $0.setInstalledPackages(.success([Self.alpha, Self.beta]))
      $0.setRuntimePermissions(Self.alphaGrants, of: Self.alpha, on: Self.deviceID)
      $0.setRuntimePermissions([], of: Self.beta, on: Self.deviceID)
      configure($0)
    }
    await setup.conditions.testConditionsTapped(Self.deviceID)
    await setup.conditions.packageSelected(Self.alpha)
    return setup
  }

  static func conditionCalls(_ fake: AndroidEmulatorClientFake) -> [AndroidEmulatorClientFake.ConditionCall] {
    fake.calls.compactMap {
      if case let .testCondition(call) = $0 {
        call
      } else {
        nil
      }
    }
  }

  static func packageReadCount(_ fake: AndroidEmulatorClientFake) -> Int {
    fake.calls.count { $0 == .installedPackages(Self.deviceID) }
  }

  static func permissionReadCount(_ fake: AndroidEmulatorClientFake) -> Int {
    self.conditionCalls(fake).count {
      if case .runtimePermissions = $0 {
        true
      } else {
        false
      }
    }
  }

  static func permissionWrites(_ fake: AndroidEmulatorClientFake) -> [AndroidEmulatorClientFake.ConditionCall] {
    self.conditionCalls(fake).filter {
      if case .setRuntimePermission = $0 {
        true
      } else {
        false
      }
    }
  }
}

/// 테스트 조건 시트의 앱 단위 구역: 패키지 목록 읽기·고르기·다시 읽기와 권한 읽기. 권한 쓰기는 `AndroidTestConditionsPermissionTests`.
@MainActor
struct AndroidTestConditionsAppTests: AndroidTestConditionsAppTesting {
  private var id: AndroidVirtualDevice.ID {
    Self.deviceID
  }

  // MARK: - 패키지 목록

  @Test("열면 지금 값을 읽은 뒤 패키지 목록을 읽고, 둘 이상이면 고르지 않아 권한은 읽지 않는다")
  func opensAndReadsPackages() async {
    let setup = await Self.loadedFixture { $0.setInstalledPackages(.success([Self.alpha, Self.beta])) }
    await setup.conditions.testConditionsTapped(self.id)
    #expect(setup.conditions.draft?.app.packages == .loaded([Self.alpha, Self.beta]))
    #expect(setup.conditions.draft?.app.selectedPackage == nil)
    #expect(setup.conditions.draft?.app.permissions == .idle)
    #expect(Self.permissionReadCount(setup.fake) == 0)
  }

  @Test("패키지를 읽는 동안은 읽는 중이고, 패키지가 하나면 고르고 그 권한을 읽는다")
  func singlePackageAutoSelected() async {
    let setup = await Self.loadedFixture {
      $0.setInstalledPackages(.success([Self.alpha]))
      $0.setRuntimePermissions(Self.alphaGrants, of: Self.alpha, on: Self.deviceID)
      $0.suspendPackageLists()
    }
    let tap = Self.start { await setup.conditions.testConditionsTapped(self.id) }
    await Self.waitUntil { Self.packageReadCount(setup.fake) == 1 }
    #expect(setup.conditions.draft?.app.packages == .loading)

    setup.fake.resumePackageLists()
    await tap.value()
    #expect(setup.conditions.draft?.app.selectedPackage == Self.alpha)
    #expect(setup.conditions.draft?.app.permissions == .loaded(Self.alphaGrants))
  }

  @Test("같은 기기에서 마지막으로 고른 패키지를 다시 열 때 먼저 고른다")
  func remembersLastSelection() async {
    let setup = await Self.openedWithAlpha()
    let conditions = setup.conditions
    await conditions.packageSelected(Self.beta)
    conditions.closeTapped()
    await conditions.testConditionsTapped(self.id)
    #expect(conditions.draft?.app.selectedPackage == Self.beta)
    #expect(conditions.draft?.app.permissions == .loaded([]))
  }

  @Test("패키지 목록을 읽지 못하면 실패를 보이고, adb 문제면 기기 목록을 다시 읽지 않고 꺼짐이면 다시 읽는다")
  func packagesFailure() async {
    let setup = await Self.loadedFixture { $0.setInstalledPackages(.failure(.adbUnavailable)) }
    await setup.conditions.testConditionsTapped(self.id)
    #expect(setup.conditions.draft?.app.packages == .failed(.adbUnavailable))
    #expect(Self.fetchCount(setup.fake) == 1)

    setup.fake.setInstalledPackages(.failure(.deviceNotBooted))
    await setup.conditions.packagesRefreshTapped()
    #expect(setup.conditions.draft?.app.packages == .failed(.deviceNotBooted))
    #expect(Self.fetchCount(setup.fake) == 2)
  }

  @Test("지금 값 읽기가 기기 꺼짐으로 실패하면 패키지 목록은 읽지 않고 같은 실패를 보인다")
  func conditionsNotBootedSkipsPackages() async {
    let setup = await Self.loadedFixture { $0.setTestConditionsError(.deviceNotBooted) }
    await setup.conditions.testConditionsTapped(self.id)
    #expect(setup.conditions.draft?.app.packages == .failed(.deviceNotBooted))
    #expect(Self.packageReadCount(setup.fake) == 0)
    #expect(Self.fetchCount(setup.fake) == 2)
  }

  @Test("앱 목록 다시 읽기는 읽는 중엔 무시하고, 읽은 뒤엔 고른 패키지를 그대로 두고 그 권한도 다시 읽는다")
  func refreshKeepsSelectionAndRereadsPermissions() async {
    let setup = await Self.loadedFixture {
      $0.setInstalledPackages(.success([Self.alpha, Self.beta]))
      $0.setRuntimePermissions(Self.alphaGrants, of: Self.alpha, on: Self.deviceID)
      $0.suspendPackageLists()
    }
    let conditions = setup.conditions
    let tap = Self.start { await conditions.testConditionsTapped(self.id) }
    await Self.waitUntil { Self.packageReadCount(setup.fake) == 1 }
    let ignored = Self.start { await conditions.packagesRefreshTapped() }
    await Self.waitUntil { ignored.isFinished }
    #expect(Self.packageReadCount(setup.fake) == 1)
    setup.fake.resumePackageLists()
    await tap.value()
    await conditions.packageSelected(Self.alpha)
    #expect(Self.permissionReadCount(setup.fake) == 1)

    await conditions.packagesRefreshTapped()
    #expect(Self.packageReadCount(setup.fake) == 2)
    #expect(conditions.draft?.app.selectedPackage == Self.alpha)
    #expect(Self.permissionReadCount(setup.fake) == 2)
    #expect(conditions.draft?.app.permissions == .loaded(Self.alphaGrants))
  }

  @Test("다시 읽은 목록에 고른 패키지가 없으면 규칙대로 고르고, 아무것도 고르지 않으면 권한은 비운다")
  func refreshDropsMissingSelection() async {
    let setup = await Self.openedWithAlpha()
    let conditions = setup.conditions
    setup.fake.setInstalledPackages(.success([Self.beta]))
    await conditions.packagesRefreshTapped()
    // 기억한 alpha 가 없어 패키지 하나 규칙으로 beta.
    #expect(conditions.draft?.app.selectedPackage == Self.beta)
    #expect(conditions.draft?.app.permissions == .loaded([]))

    setup.fake.setInstalledPackages(.success([]))
    await conditions.packagesRefreshTapped()
    #expect(conditions.draft?.app.selectedPackage == nil)
    #expect(conditions.draft?.app.permissions == .idle)
  }

  // MARK: - 고르기·권한 읽기

  @Test("목록 밖의 패키지는 고르지 않고, nil 로 고르면 권한 구역이 비워진다")
  func packageSelection() async {
    let setup = await Self.openedWithAlpha()
    let conditions = setup.conditions
    await conditions.packageSelected(AndroidPackageName("com.example.missing"))
    #expect(conditions.draft?.app.selectedPackage == Self.alpha)
    #expect(Self.permissionReadCount(setup.fake) == 1)

    await conditions.packageSelected(nil)
    #expect(conditions.draft?.app.selectedPackage == nil)
    #expect(conditions.draft?.app.permissions == .idle)
  }

  @Test("권한을 읽는 중에 다른 패키지를 고르면 앞 패키지의 늦은 결과를 버린다")
  func latePermissionsDropped() async {
    let setup = await Self.loadedFixture {
      $0.setInstalledPackages(.success([Self.alpha, Self.beta]))
      $0.setRuntimePermissions(Self.alphaGrants, of: Self.alpha, on: Self.deviceID)
      $0.setRuntimePermissions([], of: Self.beta, on: Self.deviceID)
    }
    let conditions = setup.conditions
    await conditions.testConditionsTapped(self.id)
    setup.fake.suspendConditionReads()
    let first = Self.start { await conditions.packageSelected(Self.alpha) }
    await Self.waitUntil { Self.permissionReadCount(setup.fake) == 1 }
    let second = Self.start { await conditions.packageSelected(Self.beta) }
    await Self.waitUntil { Self.permissionReadCount(setup.fake) == 2 }
    #expect(conditions.draft?.app.permissions == .loading)

    setup.fake.resumeConditionReads()
    await first.value()
    await second.value()
    #expect(conditions.draft?.app.selectedPackage == Self.beta)
    #expect(conditions.draft?.app.permissions == .loaded([]))
  }

  @Test("권한 읽기가 꺼짐으로 실패하면 실패를 보이고 기기 목록을 다시 읽으며, 다시 읽기로 다시 읽는다")
  func permissionsReadFailureThenRetry() async {
    let setup = await Self.openedWithAlpha { $0.setRuntimePermissionsError(.deviceNotBooted) }
    let conditions = setup.conditions
    #expect(conditions.draft?.app.permissions == .failed(.deviceNotBooted))
    #expect(Self.fetchCount(setup.fake) == 2)

    setup.fake.setRuntimePermissionsError(nil)
    await conditions.permissionsRetryTapped()
    #expect(conditions.draft?.app.permissions == .loaded(Self.alphaGrants))
    // 읽은 상태에서는 다시 읽기를 무시한다.
    await conditions.permissionsRetryTapped()
    #expect(Self.permissionReadCount(setup.fake) == 2)
  }

  @Test("앱이 기기에 없다고 읽으면 그 상태를 보이고, 다시 읽기로 다시 읽는다")
  func permissionsAppNotInstalled() async throws {
    let gamma = try #require(AndroidPackageName("com.example.gamma"))
    let setup = await Self.loadedFixture { $0.setInstalledPackages(.success([gamma])) }
    let conditions = setup.conditions
    await conditions.testConditionsTapped(self.id)
    #expect(conditions.draft?.app.selectedPackage == gamma)
    #expect(conditions.draft?.app.permissions == .appNotInstalled)

    setup.fake.setRuntimePermissions(Self.alphaGrants, of: gamma, on: self.id)
    await conditions.permissionsRetryTapped()
    #expect(conditions.draft?.app.permissions == .loaded(Self.alphaGrants))
  }

  @Test("표시 순서는 알려진 권한(정해진 순서) 먼저, 나머지는 원래 이름 순이다")
  func sortedPermissions() async {
    let bluetooth = Self.permission("android.permission.BLUETOOTH_CONNECT")
    let activity = Self.permission("android.permission.ACTIVITY_RECOGNITION")
    let notifications = Self.permission("android.permission.POST_NOTIFICATIONS")
    let grants = [bluetooth, notifications, Self.camera, activity, Self.fineLocation].map {
      AndroidPermissionGrant(permission: $0, isGranted: false)
    }
    let setup = await Self.loadedFixture {
      $0.setInstalledPackages(.success([Self.alpha]))
      $0.setRuntimePermissions(grants, of: Self.alpha, on: Self.deviceID)
    }
    await setup.conditions.testConditionsTapped(self.id)
    #expect(
      setup.conditions.draft?.app.sortedPermissions.map(\.permission)
        == [Self.fineLocation, Self.camera, notifications, activity, bluetooth]
    )
  }
}
