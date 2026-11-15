import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import Foundation
import Testing
@testable import AndroidDevicesFeature

/// 테스트 조건 시트의 앱 단위 구역: 런타임 권한 허용·거부(`setRuntimePermission`)와 다른 적용과의 겹침.
@MainActor
struct AndroidTestConditionsPermissionTests: AndroidTestConditionsAppTesting {
  private var id: AndroidVirtualDevice.ID {
    Self.deviceID
  }

  @Test("지금 값과 같은 값이거나 목록에 없는 권한이면 보내지 않는다")
  func sameValueIgnored() async {
    let setup = await Self.openedWithAlpha()
    await setup.conditions.permissionChanged(Self.camera, granted: false)
    await setup.conditions.permissionChanged(Self.permission("android.permission.READ_SMS"), granted: true)
    #expect(Self.permissionWrites(setup.fake).isEmpty)
  }

  @Test("허용하면 첫 await 전에 적용 중이 되고 연타·다른 적용은 무시되며, 끝나면 다시 읽은 목록을 보인다")
  func grantApplies() async {
    let setup = await Self.openedWithAlpha()
    let conditions = setup.conditions
    conditions.pointTextChanged("37.5, 127.0")
    setup.fake.suspendConditions()
    let first = Self.start { await conditions.permissionChanged(Self.camera, granted: true) }
    await Self.waitUntil { !Self.permissionWrites(setup.fake).isEmpty }
    #expect(conditions.applying[self.id] == .permission(Self.camera))

    let others = [
      Self.start { await conditions.permissionChanged(Self.camera, granted: true) },
      Self.start { await conditions.permissionChanged(Self.fineLocation, granted: false) },
      Self.start { await conditions.appearanceSelected(.dark) },
      Self.start { await conditions.setPointTapped() },
    ]
    await Self.waitUntil { others.allSatisfy(\.isFinished) }

    setup.fake.resumeConditions()
    await first.value()
    #expect(Self.permissionWrites(setup.fake) == [.setRuntimePermission(Self.camera, true, Self.alpha, self.id)])
    #expect(Self.conditionCalls(setup.fake).count {
      if case .setNightMode = $0 {
        true
      } else {
        false
      }
    } == 0)
    #expect(conditions.applying.isEmpty)
    #expect(conditions.draft?.message == nil)
    #expect(
      conditions.draft?.app.permissions == .loaded([
        AndroidPermissionGrant(permission: Self.camera, isGranted: true),
        AndroidPermissionGrant(permission: Self.fineLocation, isGranted: true),
      ])
    )
  }

  @Test("거부했는데 다시 읽은 값이 그대로면 적용 안 됨 문구와 다시 읽은 목록을 보인다")
  func notApplied() async {
    let setup = await Self.openedWithAlpha { $0.setRuntimePermissionNotApplied(true) }
    await setup.conditions.permissionChanged(Self.fineLocation, granted: false)
    #expect(setup.conditions.draft?.message == .permissionNotApplied(Self.fineLocation, granted: false))
    #expect(setup.conditions.draft?.app.permissions == .loaded(Self.alphaGrants))
  }

  @Test("쓰는 동안 앱이 없어지면 권한 구역에 그 상태와 문구를 보인다")
  func appRemoved() async {
    let setup = await Self.openedWithAlpha()
    setup.fake.removeRuntimePermissions(of: Self.alpha, on: self.id)
    await setup.conditions.permissionChanged(Self.camera, granted: true)
    #expect(setup.conditions.draft?.app.permissions == .appNotInstalled)
    #expect(setup.conditions.draft?.message == .appNotInstalled(Self.alpha))
  }

  @Test("쓰기가 꺼짐으로 실패하면 실패 줄을 보이고 기기 목록을 다시 읽으며, adb 문제면 다시 읽지 않는다")
  func writeFailures() async {
    let setup = await Self.openedWithAlpha { $0.setRuntimePermissionError(.deviceNotBooted) }
    let conditions = setup.conditions
    await conditions.permissionChanged(Self.camera, granted: true)
    #expect(conditions.draft?.message == .failed(.permission(Self.camera), .deviceNotBooted))
    #expect(conditions.draft?.app.permissions == .loaded(Self.alphaGrants))
    #expect(Self.fetchCount(setup.fake) == 2)
    #expect(conditions.applying.isEmpty)

    setup.fake.setRuntimePermissionError(.adbUnavailable)
    await conditions.permissionChanged(Self.camera, granted: true)
    #expect(conditions.draft?.message == .failed(.permission(Self.camera), .adbUnavailable))
    #expect(Self.fetchCount(setup.fake) == 2)
  }

  @Test("쓰는 중에 다른 패키지를 고르면 결과는 버리고 새 패키지의 읽기가 보이며, 쓰기는 앞 앱에 적용된 채다")
  func packageChangedDuringWrite() async {
    let setup = await Self.openedWithAlpha()
    let conditions = setup.conditions
    setup.fake.suspendConditions()
    let write = Self.start { await conditions.permissionChanged(Self.camera, granted: true) }
    await Self.waitUntil { !Self.permissionWrites(setup.fake).isEmpty }
    let select = Self.start { await conditions.packageSelected(Self.beta) }
    await Self.waitUntil { Self.permissionReadCount(setup.fake) == 2 }

    setup.fake.resumeConditions()
    await write.value()
    await select.value()
    #expect(conditions.draft?.app.selectedPackage == Self.beta)
    #expect(conditions.draft?.app.permissions == .loaded([]))
    #expect(conditions.draft?.message == nil)
    #expect(setup.fake.storedRuntimePermissions(of: Self.alpha, on: self.id)?.first?.isGranted == true)
  }

  @Test("시트를 닫은 뒤 끝난 쓰기는 적용 중만 풀고, 다시 연 같은 기기의 시트는 새로 읽은 값을 보인다")
  func writeAfterClose() async {
    let setup = await Self.openedWithAlpha()
    let conditions = setup.conditions
    setup.fake.suspendConditions()
    let write = Self.start { await conditions.permissionChanged(Self.camera, granted: true) }
    await Self.waitUntil { !Self.permissionWrites(setup.fake).isEmpty }
    conditions.closeTapped()
    setup.fake.resumeConditions()
    await write.value()
    #expect(conditions.draft == nil)
    #expect(conditions.applying.isEmpty)

    await conditions.testConditionsTapped(self.id)
    #expect(conditions.draft?.app.selectedPackage == Self.alpha)
    #expect(conditions.draft?.app.grant(of: Self.camera)?.isGranted == true)
  }

  @Test("권한을 읽는 동안 그 기기의 쓰기가 끝나면 그 읽기는 쓰기 전 값일 수 있어 한 번 더 읽는다")
  func readDuringWriteRereads() async {
    let setup = await Self.openedWithAlpha()
    let conditions = setup.conditions
    setup.fake.suspendConditions()
    let write = Self.start { await conditions.permissionChanged(Self.camera, granted: true) }
    await Self.waitUntil { !Self.permissionWrites(setup.fake).isEmpty }
    // 쓰는 동안 앱 목록 다시 읽기가 고른 패키지의 권한을 다시 읽는다 (읽기는 쓰기보다 늦게 풀린다).
    let refresh = Self.start { await conditions.packagesRefreshTapped() }
    await Self.waitUntil { Self.permissionReadCount(setup.fake) == 2 }
    setup.fake.suspendConditionReads()
    setup.fake.resumeConditions()
    await write.value()
    setup.fake.resumeConditionReads()
    await refresh.value()

    #expect(Self.permissionReadCount(setup.fake) == 3)
    #expect(conditions.draft?.app.grant(of: Self.camera)?.isGranted == true)
  }
}
