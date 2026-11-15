import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Foundation
import Testing
@testable import AndroidDevicesFeature

/// 테스트 조건 시트의 "앱 목록 다시 읽기" 동안 마지막 목록·고른 패키지·권한 값을 그대로 두는 규칙과, 그동안의 조작·실패.
@MainActor
struct AndroidTestConditionsAppReloadTests: AndroidTestConditionsAppTesting {
  private var id: AndroidVirtualDevice.ID {
    Self.deviceID
  }

  @Test("다시 읽는 동안 마지막 목록·고른 패키지·권한 값을 그대로 보이고, 두 번째 다시 읽기는 무시한다")
  func refreshKeepsPackagesSelectionAndPermissionsWhileReading() async {
    let setup = await Self.openedWithAlpha()
    let conditions = setup.conditions
    setup.fake.suspendPackageLists()
    let refresh = Self.start { await conditions.packagesRefreshTapped() }
    await Self.waitUntil { Self.packageReadCount(setup.fake) == 2 }
    #expect(conditions.draft?.app.packages == .reloading([Self.alpha, Self.beta]))
    #expect(conditions.draft?.app.loadedPackages == [Self.alpha, Self.beta])
    #expect(conditions.draft?.app.isReadingPackages == true)
    #expect(conditions.draft?.app.selectedPackage == Self.alpha)
    #expect(conditions.draft?.app.permissions == .loaded(Self.alphaGrants))

    let ignored = Self.start { await conditions.packagesRefreshTapped() }
    await Self.waitUntil { ignored.isFinished }
    #expect(Self.packageReadCount(setup.fake) == 2)

    setup.fake.resumePackageLists()
    await refresh.value()
    #expect(conditions.draft?.app.packages == .loaded([Self.alpha, Self.beta]))
    #expect(conditions.draft?.app.isReadingPackages == false)
    #expect(conditions.draft?.app.selectedPackage == Self.alpha)
    #expect(conditions.draft?.app.permissions == .loaded(Self.alphaGrants))
  }

  @Test("목록 결과 뒤 같은 패키지의 권한을 다시 읽는 동안에도 마지막 권한 값을 보이고, 읽으면 새 값으로 바꾼다")
  func rereadOfSamePackageKeepsShownGrants() async {
    let setup = await Self.openedWithAlpha()
    let conditions = setup.conditions
    setup.fake.suspendConditionReads()
    let refresh = Self.start { await conditions.packagesRefreshTapped() }
    await Self.waitUntil { Self.permissionReadCount(setup.fake) == 2 }
    #expect(conditions.draft?.app.packages == .loaded([Self.alpha, Self.beta]))
    #expect(conditions.draft?.app.permissions == .loaded(Self.alphaGrants))

    let newGrants = [
      AndroidPermissionGrant(permission: Self.camera, isGranted: true),
      AndroidPermissionGrant(permission: Self.fineLocation, isGranted: true),
    ]
    setup.fake.setRuntimePermissions(newGrants, of: Self.alpha, on: self.id)
    setup.fake.resumeConditionReads()
    await refresh.value()
    #expect(conditions.draft?.app.permissions == .loaded(newGrants))
  }

  @Test("다시 읽은 목록에서 다른 패키지가 골라지면 그 권한을 읽는 동안 앞 패키지의 값을 보이지 않는다")
  func rereadWithChangedSelectionShowsLoading() async {
    let setup = await Self.openedWithAlpha()
    let conditions = setup.conditions
    setup.fake.setInstalledPackages(.success([Self.beta]))
    setup.fake.suspendConditionReads()
    let refresh = Self.start { await conditions.packagesRefreshTapped() }
    await Self.waitUntil { Self.permissionReadCount(setup.fake) == 2 }
    // 기억한 alpha 가 없어 패키지 하나 규칙으로 beta.
    #expect(conditions.draft?.app.selectedPackage == Self.beta)
    #expect(conditions.draft?.app.permissions == .loading)

    setup.fake.resumeConditionReads()
    await refresh.value()
    #expect(conditions.draft?.app.permissions == .loaded([]))
  }

  @Test("패키지 목록을 다시 읽는 동안 권한 토글을 쓸 수 있고 결과가 반영된다")
  func permissionToggleWorksWhileReloading() async throws {
    let setup = await Self.openedWithAlpha()
    let conditions = setup.conditions
    setup.fake.suspendPackageLists()
    let refresh = Self.start { await conditions.packagesRefreshTapped() }
    await Self.waitUntil { Self.packageReadCount(setup.fake) == 2 }

    await conditions.permissionChanged(Self.camera, granted: true)
    #expect(Self.permissionWrites(setup.fake).count == 1)
    #expect(conditions.draft?.app.grant(of: Self.camera)?.isGranted == true)
    #expect(conditions.draft?.app.packages == .reloading([Self.alpha, Self.beta]))

    setup.fake.resumePackageLists()
    await refresh.value()
    let stored = try #require(setup.fake.storedRuntimePermissions(of: Self.alpha, on: self.id))
    #expect(conditions.draft?.app.permissions == .loaded(stored))
    #expect(conditions.draft?.app.grant(of: Self.camera)?.isGranted == true)
  }

  @Test("다시 읽는 동안 마지막 목록의 다른 패키지를 고르면 받아 그 권한을 읽고, 목록 결과 뒤에도 그대로 둔다")
  func packageSelectedDuringReload() async {
    let setup = await Self.openedWithAlpha()
    let conditions = setup.conditions
    setup.fake.suspendPackageLists()
    let refresh = Self.start { await conditions.packagesRefreshTapped() }
    await Self.waitUntil { Self.packageReadCount(setup.fake) == 2 }

    await conditions.packageSelected(Self.beta)
    #expect(conditions.draft?.app.selectedPackage == Self.beta)
    #expect(conditions.draft?.app.permissions == .loaded([]))
    #expect(Self.permissionReadCount(setup.fake) == 2)

    setup.fake.resumePackageLists()
    await refresh.value()
    #expect(conditions.draft?.app.selectedPackage == Self.beta)
    #expect(conditions.draft?.app.permissions == .loaded([]))
    #expect(Self.permissionReadCount(setup.fake) == 3)
  }

  @Test("다시 읽기가 실패하면 선택·권한을 지우고, 실패 뒤 다시 읽기는 읽는 중부터 시작해 기억한 패키지를 다시 고른다")
  func reloadFailureClearsSelectionThenRestoresRemembered() async {
    let setup = await Self.openedWithAlpha()
    let conditions = setup.conditions
    setup.fake.setInstalledPackages(.failure(.adbUnavailable))
    await conditions.packagesRefreshTapped()
    #expect(conditions.draft?.app.packages == .failed(.adbUnavailable))
    #expect(conditions.draft?.app.selectedPackage == nil)
    #expect(conditions.draft?.app.permissions == .idle)

    setup.fake.setInstalledPackages(.success([Self.alpha, Self.beta]))
    setup.fake.suspendPackageLists()
    let refresh = Self.start { await conditions.packagesRefreshTapped() }
    await Self.waitUntil { Self.packageReadCount(setup.fake) == 3 }
    #expect(conditions.draft?.app.packages == .loading)

    setup.fake.resumePackageLists()
    await refresh.value()
    #expect(conditions.draft?.app.selectedPackage == Self.alpha)
    #expect(conditions.draft?.app.permissions == .loaded(Self.alphaGrants))
  }
}
