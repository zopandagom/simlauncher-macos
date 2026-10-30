import AndroidEmulatorInterface
import AndroidEmulatorTesting
import AndroidPackageInterface
import AndroidPackageTesting
import Core
import Foundation
import Testing
@testable import AndroidDevicesFeature

/// 툴바 "선택한 기기에 앱 설치" > "파일에서 고르기…" (`selectedAppFileChosen`): 한 번 검사 → 켜진 기기마다 동시에 대상 확인 →
/// 기기 값 → 판정 → 설치 → 실행 → 다시 읽기 → 결과 알림 하나 (실패·건너뜀이 있을 때만).
@MainActor
struct AndroidDevicesBatchInstallTests: AndroidDevicesTesting {
  static let tablet = AndroidVirtualDevice.bootedTabletSample
  /// 켜진 휴대전화 "두 번째 폰".
  static let second = AndroidVirtualDevice.secondPhoneSample.with(state: .booted)
  static let apk = URL(filePath: "/tmp/Picked.apk")
  static let info = AndroidPackageInfo.sample()
  /// 꺼진 폰·켜진 태블릿·켜진 두 번째 폰·쓸 수 없는 기기 (목록 순서).
  static let inventory = AndroidDeviceInventory(
    devices: [.phoneSample, .bootedTabletSample, second, .unsupportedNameSample],
    creationOptions: .sample
  )

  static func appCalls(
    _ fake: AndroidEmulatorClientFake,
    on id: AndroidVirtualDevice.ID
  ) -> [AndroidEmulatorClientFake.Call] {
    fake.calls.filter { call in
      switch call {
      case let .deviceTraits(target), let .install(_, target), let .launch(_, target): target == id
      default: false
      }
    }
  }

  static func installedAndLaunched(on id: AndroidVirtualDevice.ID) -> [AndroidEmulatorClientFake.Call] {
    [.deviceTraits(id), .install(self.info.location, id), .launch(self.info.packageName, id)]
  }

  static func entry(
    _ device: AndroidVirtualDevice,
    _ result: AndroidBatchDeviceResult
  ) -> AndroidBatchInstallReport.Entry {
    AndroidBatchInstallReport.Entry(device: AndroidDeviceLabel(device), result: result)
  }

  /// 기기를 지금 목록 순서로 늘어놓는다 (그 순서는 로케일에 따라 다르므로 목록에서 만든다).
  static func inListOrder(_ devices: [AndroidVirtualDevice], of model: AndroidDevicesModel) -> [AndroidVirtualDevice] {
    let order = self.list(model)?.devices.map(\.id) ?? []
    return devices.sorted { (order.firstIndex(of: $0.id) ?? .max) < (order.firstIndex(of: $1.id) ?? .max) }
  }

  /// 기기별 결과를 지금 목록 순서로 모은 결과 알림 내용.
  static func report(
    _ results: [(AndroidVirtualDevice, AndroidBatchDeviceResult)],
    in model: AndroidDevicesModel
  ) -> AndroidBatchInstallReport {
    let byID = Dictionary(uniqueKeysWithValues: results.map { ($0.0.id, $0.1) })
    return AndroidBatchInstallReport(entries: self.inListOrder(results.map(\.0), of: model).compactMap { device in
      byID[device.id].map { self.entry(device, $0) }
    })
  }

  // MARK: - 성공

  @Test("켜진 기기 둘: 한 번 검사하고 기기마다 설치·실행한 뒤 다시 읽고, 모두 성공이면 알림이 없고 행이 풀린다")
  func installsOnEachBootedDevice() async {
    let setup = await Self.loadedFixture(Self.inventory)
    setup.model.selectionChanged([Self.tablet.id, Self.second.id])
    await setup.model.selectedAppFileChosen(Self.apk)
    #expect(setup.package.calls == [Self.apk])
    #expect(Self.appCalls(setup.fake, on: Self.tablet.id) == Self.installedAndLaunched(on: Self.tablet.id))
    #expect(Self.appCalls(setup.fake, on: Self.second.id) == Self.installedAndLaunched(on: Self.second.id))
    #expect(Self.fetchCount(setup.fake) >= 2)
    #expect(Self.notices(setup.model).isEmpty)
    #expect(setup.model.activity.busyDeviceIDs.isEmpty)
  }

  @Test("한 대만 고르면 행 메뉴와 같은 경로다: 꺼진 기기는 한 기기 알림, 켜진 기기는 설치·실행")
  func singleSelectionUsesRowPath() async {
    let setup = await Self.loadedFixture(Self.inventory)
    setup.model.selectionChanged([AndroidVirtualDevice.phoneSample.id])
    await setup.model.selectedAppFileChosen(Self.apk)
    #expect(Self.notices(setup.model) == [
      .installFailed(AndroidDeviceLabel(.phoneSample), .deviceNotReady(.notBooted)),
    ])
    #expect(setup.package.calls.isEmpty)

    setup.model.selectionChanged([Self.tablet.id])
    await setup.model.selectedAppFileChosen(Self.apk)
    #expect(Self.appCalls(setup.fake, on: Self.tablet.id) == Self.installedAndLaunched(on: Self.tablet.id))
    #expect(Self.notices(setup.model).count == 1)
  }

  // MARK: - 건너뜀·기기별 실패

  @Test("꺼진·쓸 수 없는·다른 작업 중인 기기는 이유와 함께 건너뛰고, 결과 알림 하나에 목록 순서로 모은다")
  func skipsWithReasons() async {
    let setup = await Self.loadedFixture(Self.inventory) { $0.suspendInstall(of: Self.second.id) }
    let busy = Self.start { await setup.model.appFileSelected(Self.apk, for: Self.second.id) }
    await Self.waitUntil { setup.fake.calls.contains(.install(Self.info.location, Self.second.id)) }
    setup.model.selectionChanged(Set(Self.inventory.devices.map(\.id)))
    await setup.model.selectedAppFileChosen(Self.apk)
    #expect(Self.notices(setup.model) == [.batchInstallFinished(Self.report([
      (.phoneSample, .installFailed(.deviceNotReady(.notBooted))),
      (Self.tablet, .succeeded),
      (Self.second, .installFailed(.deviceBusy)),
      (.unsupportedNameSample, .installFailed(.deviceNotReady(.unavailable))),
    ], in: setup.model))])
    #expect(setup.model.activity.task(on: Self.second.id) == .installApp)
    setup.fake.resumeInstall(of: Self.second.id)
    await busy.value()
    #expect(setup.model.activity.busyDeviceIDs.isEmpty)
  }

  @Test("여러 대를 골랐는데 시작한 기기가 없으면 검사하지 않고 결과 알림(모두 건너뜀) 하나")
  func noneStartedReportsAllSkipped() async {
    let setup = await Self.loadedFixture(Self.inventory)
    setup.model.selectionChanged([AndroidVirtualDevice.phoneSample.id, AndroidVirtualDevice.unsupportedNameSample.id])
    await setup.model.selectedAppFileChosen(Self.apk)
    #expect(setup.package.calls.isEmpty)
    #expect(Self.notices(setup.model) == [.batchInstallFinished(Self.report([
      (.phoneSample, .installFailed(.deviceNotReady(.notBooted))),
      (.unsupportedNameSample, .installFailed(.deviceNotReady(.unavailable))),
    ], in: setup.model))])
  }

  @Test("한 기기만 판정 거절(API 낮음): 그 기기는 설치하지 않고, 다른 기기는 설치·실행한다")
  func rejectsOnlyOneDevice() async {
    let setup = await Self.loadedFixture(Self.inventory) {
      $0.setDeviceTraits(.success(AndroidDeviceTraits(apiLevel: 23, abis: ["arm64-v8a"])), for: Self.second.id)
    }
    setup.model.selectionChanged([Self.tablet.id, Self.second.id])
    await setup.model.selectedAppFileChosen(Self.apk)
    #expect(Self.appCalls(setup.fake, on: Self.second.id) == [.deviceTraits(Self.second.id)])
    #expect(Self.appCalls(setup.fake, on: Self.tablet.id) == Self.installedAndLaunched(on: Self.tablet.id))
    #expect(Self.notices(setup.model) == [.batchInstallFinished(Self.report([
      (Self.tablet, .succeeded),
      (Self.second, .installFailed(.rejected(.requiresNewerAPI(required: 24, device: 23)))),
    ], in: setup.model))])
  }

  @Test("한 기기 설치 실패·다른 기기 실행 실패는 각자의 결과 줄이 되고, 실행 실패는 설치한 기기로 센다")
  func perDeviceInstallAndLaunchFailures() async {
    let setup = await Self.loadedFixture(Self.inventory) {
      $0.setInstallError(.installFailed(.updateIncompatible), for: Self.tablet.id)
      $0.setLaunchError(.launchFailed(.noLauncherActivity), for: Self.second.id)
    }
    setup.model.selectionChanged([Self.tablet.id, Self.second.id])
    await setup.model.selectedAppFileChosen(Self.apk)
    let report = Self.report([
      (Self.tablet, .installFailed(.emulator(.installFailed(.updateIncompatible)))),
      (Self.second, .launchFailed(.launchFailed(.noLauncherActivity))),
    ], in: setup.model)
    #expect(Self.notices(setup.model) == [.batchInstallFinished(report)])
    #expect(report.successCount == 1)
  }

  @Test("검사 실패는 공통 알림 하나이고 기기에 명령을 보내지 않으며 다시 읽지 않는다")
  func inspectionFailureIsOneNotice() async {
    let setup = await Self.loadedFixture(Self.inventory)
    setup.package.setResult(.failure(.appBundle))
    setup.model.selectionChanged([Self.tablet.id, Self.second.id])
    await setup.model.selectedAppFileChosen(Self.apk)
    let labels = Self.inListOrder([Self.tablet, Self.second], of: setup.model).map(AndroidDeviceLabel.init)
    #expect(Self.notices(setup.model) == [.batchInstallFailed(labels, .package(.appBundle))])
    #expect(Self.appCalls(setup.fake, on: Self.tablet.id).isEmpty)
    #expect(Self.fetchCount(setup.fake) == 1)
    #expect(setup.model.activity.busyDeviceIDs.isEmpty)
  }

  @Test("먼저 끝난 기기는 곧바로 풀려 새 작업을 시작할 수 있고, 묶음의 끝이 그 작업을 지우지 않는다")
  func finishedDeviceIsReleasedEarly() async {
    let setup = await Self.loadedFixture(Self.inventory) { $0.suspendInstall(of: Self.second.id) }
    setup.model.selectionChanged([Self.tablet.id, Self.second.id])
    let batch = Self.start { await setup.model.selectedAppFileChosen(Self.apk) }
    // 묶음이 시작되기 전에도 태블릿 기록은 없으므로, 태블릿 실행이 끝난 뒤 풀린 것을 기다린다.
    await Self.waitUntil {
      setup.fake.calls.contains(.launch(Self.info.packageName, Self.tablet.id))
        && setup.model.activity.task(on: Self.tablet.id) == nil
    }
    #expect(setup.model.activity.task(on: Self.second.id) == .installApp)
    setup.fake.suspendInstall(of: Self.tablet.id)
    let next = Self.start { await setup.model.appFileSelected(Self.apk, for: Self.tablet.id) }
    await Self.waitUntil { setup.model.activity.task(on: Self.tablet.id) == .installApp }
    setup.fake.resumeInstall(of: Self.second.id)
    await batch.value()
    #expect(setup.model.activity.task(on: Self.tablet.id) == .installApp)
    setup.fake.resumeInstall(of: Self.tablet.id)
    await next.value()
    #expect(setup.model.activity.busyDeviceIDs.isEmpty)
    #expect(Self.notices(setup.model).isEmpty)
  }

  @Test("툴바 설치는 고른 기기 중 하나라도 앱을 설치할 수 있을 때만 켜진다")
  func canInstallOnSelection() async {
    let setup = await Self.loadedFixture(Self.inventory)
    #expect(!setup.model.canInstallOnSelection)
    setup.model.selectionChanged([AndroidVirtualDevice.phoneSample.id, AndroidVirtualDevice.unsupportedNameSample.id])
    #expect(!setup.model.canInstallOnSelection)
    setup.model.selectionChanged([AndroidVirtualDevice.phoneSample.id, Self.tablet.id])
    #expect(setup.model.canInstallOnSelection)
  }
}
