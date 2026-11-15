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

// MARK: - 권한 다시 읽기와 쓰기가 여러 번 겹침

// 타입 본문 길이(lint `type_body_length`)에 들지 않게 extension 에 둔다.
extension AndroidTestConditionsPermissionTests {
  /// 카메라 허용·정확한 위치 허용 (alpha 에서 카메라를 허용한 뒤).
  private static var cameraGranted: [AndroidPermissionGrant] {
    [
      AndroidPermissionGrant(permission: camera, isGranted: true),
      AndroidPermissionGrant(permission: fineLocation, isGranted: true),
    ]
  }

  /// 카메라 허용·정확한 위치 거부 (그 뒤 위치를 거부한 뒤).
  private static var locationDenied: [AndroidPermissionGrant] {
    [
      AndroidPermissionGrant(permission: camera, isGranted: true),
      AndroidPermissionGrant(permission: fineLocation, isGranted: false),
    ]
  }

  /// alpha 권한 읽기 호출 수.
  private static func alphaReads(_ fake: AndroidEmulatorClientFake) -> Int {
    self.conditionCalls(fake).count { $0 == .runtimePermissions(Self.alpha, Self.deviceID) }
  }

  /// 멈춘 읽기를 깨우고 곧바로 다시 멈춤을 걸어, 다음 시도의 읽기가 멈추게 한다 (Model 은 테스트가 await 할 때까지 MainActor 에서 돌지
  /// 않아 다음 시도는 반드시 다시 건 멈춤에 걸린다). Fake 는 호출을 기록한 뒤에 멈춤을 확인하므로, 깨울 읽기가 기록만 하고 아직 멈춤에
  /// 닿지 않았으면 다시 건 멈춤에 걸려 깨지 않는다. 그래서 깨우기 전에 `settle()` 로 그 읽기가 멈춤에 닿을 차례를 준다. 다만 `settle()`
  /// 은 MainActor 양보라 전역 executor 에서 도는 Fake 읽기가 멈춤에 닿았다고 보장하지는 못해, 부하가 높으면 드물게 다음 `waitUntil` 이
  /// 시간 제한으로 실패할 수 있다 (알고 둔 위험. Fake 에 멈춰 기다리는 읽기 수 조회를 더해 기다리는 것은 이후 후보).
  private static func wakeReadsAndSuspendAgain(_ fake: AndroidEmulatorClientFake) async {
    await settle()
    fake.resumeConditionReads()
    fake.suspendConditionReads()
  }

  @Test("같은 패키지 권한을 다시 읽는 동안 쓰기가 두 번 이어 끝나도 마지막 쓰기 뒤 기기 값을 보인다")
  func rereadKeepsLatestWriteAcrossRepeatedOverlaps() async {
    let setup = await Self.openedWithAlpha()
    let conditions = setup.conditions
    setup.fake.suspendConditionReads()
    let refresh = Self.start { await conditions.packagesRefreshTapped() }
    await Self.waitUntil { Self.permissionReadCount(setup.fake) == 2 }

    // 시도1 안에서 쓰기1 이 끝난다.
    await conditions.permissionChanged(Self.camera, granted: true)
    #expect(conditions.draft?.app.permissions == .loaded(Self.cameraGranted))
    await Self.wakeReadsAndSuspendAgain(setup.fake)
    await Self.waitUntil { Self.permissionReadCount(setup.fake) == 3 }

    // 시도2 안에서 쓰기2 가 끝나고, 시도2 는 쓰기2 전 값을 읽은 것으로 한다.
    await conditions.permissionChanged(Self.fineLocation, granted: false)
    #expect(conditions.draft?.app.permissions == .loaded(Self.locationDenied))
    setup.fake.setRuntimePermissions(Self.cameraGranted, of: Self.alpha, on: Self.deviceID)
    await Self.wakeReadsAndSuspendAgain(setup.fake)
    await Self.waitUntil { Self.permissionReadCount(setup.fake) == 4 || refresh.isFinished }
    #expect(Self.permissionReadCount(setup.fake) == 4)

    // 시도3 은 쓰기가 끝나지 않은 읽기라 그 값을 보인다.
    setup.fake.setRuntimePermissions(Self.locationDenied, of: Self.alpha, on: Self.deviceID)
    setup.fake.resumeConditionReads()
    await refresh.value()
    #expect(conditions.draft?.app.permissions == .loaded(Self.locationDenied))
    #expect(Self.permissionReadCount(setup.fake) == 4)
  }

  @Test("다시 읽는 동안 두 번째로 끝난 쓰기가 실패해도 한 번 더 읽고 실패 알림은 남긴다")
  func rereadAfterFailedSecondWrite() async {
    let setup = await Self.openedWithAlpha()
    let conditions = setup.conditions
    setup.fake.suspendConditionReads()
    let refresh = Self.start { await conditions.packagesRefreshTapped() }
    await Self.waitUntil { Self.permissionReadCount(setup.fake) == 2 }
    await conditions.permissionChanged(Self.camera, granted: true)
    await Self.wakeReadsAndSuspendAgain(setup.fake)
    await Self.waitUntil { Self.permissionReadCount(setup.fake) == 3 }

    // 시도2 안에서 쓰기2 가 실패로 끝난다 (기기 값은 그대로).
    setup.fake.setRuntimePermissionError(.appCommandFailed)
    await conditions.permissionChanged(Self.fineLocation, granted: false)
    #expect(conditions.draft?.message == .failed(.permission(Self.fineLocation), .appCommandFailed))
    #expect(conditions.draft?.app.permissions == .loaded(Self.cameraGranted))
    setup.fake.setRuntimePermissionError(nil)
    setup.fake.resumeConditionReads()
    await refresh.value()

    #expect(Self.permissionReadCount(setup.fake) == 4)
    #expect(conditions.draft?.app.permissions == .loaded(Self.cameraGranted))
    #expect(conditions.draft?.message == .failed(.permission(Self.fineLocation), .appCommandFailed))
  }

  @Test("다시 읽기를 반복하는 동안 다른 패키지를 고르면 반복을 멈추고 그 패키지 권한을 보인다")
  func repeatedRereadStopsWhenPackageChanges() async {
    let setup = await Self.openedWithAlpha()
    let conditions = setup.conditions
    setup.fake.suspendConditionReads()
    let refresh = Self.start { await conditions.packagesRefreshTapped() }
    await Self.waitUntil { Self.permissionReadCount(setup.fake) == 2 }
    await conditions.permissionChanged(Self.camera, granted: true)
    await Self.wakeReadsAndSuspendAgain(setup.fake)
    await Self.waitUntil { Self.permissionReadCount(setup.fake) == 3 }
    await conditions.permissionChanged(Self.fineLocation, granted: false)

    // alpha 시도2 가 멈춘 동안 beta 를 고른다.
    let select = Self.start { await conditions.packageSelected(Self.beta) }
    await Self.waitUntil { Self.permissionReadCount(setup.fake) == 4 }
    #expect(conditions.draft?.app.selectedPackage == Self.beta)
    #expect(conditions.draft?.app.permissions == .loading)

    setup.fake.resumeConditionReads()
    await select.value()
    await refresh.value()
    await Self.settle()
    #expect(conditions.draft?.app.selectedPackage == Self.beta)
    #expect(conditions.draft?.app.permissions == .loaded([]))
    #expect(Self.alphaReads(setup.fake) == 3)
  }

  @Test("쓰는 동안 다른 패키지를 골랐다 돌아와 처음부터 읽는 중에 그 쓰기가 끝나 토글이 켜지고, 다시 토글해 겹쳐도 마지막 쓰기 뒤 기기 값을 보인다")
  func loadingReadBecomesLoadedByPendingWriteThenOverlapsAgain() async {
    let setup = await Self.openedWithAlpha()
    let conditions = setup.conditions
    setup.fake.suspendConditions()
    let write1 = Self.start { await conditions.permissionChanged(Self.camera, granted: true) }
    await Self.waitUntil { Self.permissionWrites(setup.fake).count == 1 }

    // 쓰는 동안 beta 를 골랐다가 alpha 로 돌아온다 (alpha 시도1 은 처음부터 `.loading`).
    let selectBeta = Self.start { await conditions.packageSelected(Self.beta) }
    await Self.waitUntil { Self.permissionReadCount(setup.fake) == 2 }
    let selectAlpha = Self.start { await conditions.packageSelected(Self.alpha) }
    await Self.waitUntil { Self.alphaReads(setup.fake) == 2 }
    #expect(conditions.draft?.app.permissions == .loading)

    // 읽기는 멈춘 채 쓰기1 만 끝나 읽는 중에 표시가 `.loaded` 가 된다 (토글이 켜진다).
    setup.fake.suspendConditionReads()
    setup.fake.resumeConditions()
    await write1.value()
    #expect(conditions.draft?.app.permissions == .loaded(Self.cameraGranted))

    // alpha 시도1 은 쓰기1 이 끝나 버리고 시도2 가 멈춘다 (beta 읽기는 고른 패키지가 달라 버린다).
    await Self.wakeReadsAndSuspendAgain(setup.fake)
    await selectBeta.value()
    await Self.waitUntil { Self.alphaReads(setup.fake) == 3 }

    // 시도2 안에서 쓰기2 가 끝나고, 시도2 는 쓰기2 전 값을 읽은 것으로 한다.
    await conditions.permissionChanged(Self.fineLocation, granted: false)
    #expect(conditions.draft?.app.permissions == .loaded(Self.locationDenied))
    setup.fake.setRuntimePermissions(Self.cameraGranted, of: Self.alpha, on: Self.deviceID)
    await Self.wakeReadsAndSuspendAgain(setup.fake)
    await Self.waitUntil { Self.alphaReads(setup.fake) == 4 || selectAlpha.isFinished }
    #expect(Self.alphaReads(setup.fake) == 4)

    setup.fake.setRuntimePermissions(Self.locationDenied, of: Self.alpha, on: Self.deviceID)
    setup.fake.resumeConditionReads()
    await selectAlpha.value()
    #expect(conditions.draft?.app.permissions == .loaded(Self.locationDenied))
  }
}
