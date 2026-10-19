import AppBundleInterface
import AppBundleTesting
import Core
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

@MainActor
struct LauncherZipInstallTests: LauncherModelTesting {
  static let zip = URL(filePath: "/Users/tester/Downloads/My App.zip")
  static let sample = AppBundleInfo.sample
  static let first = ExtractedApp.fake(index: 1)

  // MARK: - 성공 흐름

  @Test(
    "zip 을 고르면 풀기 → 푼 .app 검사 → 설치 → 실행 → 다시 읽기 → 임시 폴더 정리이고 알림이 없다 (확장자 대소문자 무시)",
    arguments: [
      URL(filePath: "/Users/tester/Downloads/My App.zip"), URL(filePath: "/Users/tester/Downloads/BUILD.ZIP"),
    ]
  )
  func installFromZip(zip: URL) async {
    let appBundle = AppBundleClientFake()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)

    await model.appFileSelected(zip, for: SampleID.iPhoneOn)

    #expect(appBundle.calls == [.extractApp(zip), .inspect(Self.first.app), .removeExtracted(Self.first)])
    #expect(simulator.calls == [
      .fetchInventory,
      .openSimulatorApp,
      .install(Self.sample.location, SampleID.iPhoneOn),
      .launch(Self.sample.bundleID, SampleID.iPhoneOn),
      .fetchInventory,
    ])
    #expect(model.notices.isEmpty)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("zip 하나를 드롭하면 고른 경우와 같은 흐름이다")
  func dropZipInstalls() async {
    let appBundle = AppBundleClientFake()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)

    await model.appDropped([Self.zip], on: SampleID.iPhoneOff)

    #expect(appBundle.calls == [.extractApp(Self.zip), .inspect(Self.first.app), .removeExtracted(Self.first)])
    #expect(simulator.calls.suffix(4) == [
      .openSimulatorApp,
      .install(Self.sample.location, SampleID.iPhoneOff),
      .launch(Self.sample.bundleID, SampleID.iPhoneOff),
      .fetchInventory,
    ])
    #expect(model.notices.isEmpty)
  }

  @Test("확장자가 zip 이 아니면 이름에 zip 이 들어가도 풀지 않고 바로 검사한다", arguments: [
    URL(filePath: "/Users/tester/Downloads/My.zip.app", directoryHint: .isDirectory),
    URL(filePath: "/Users/tester/zip/zip.app", directoryHint: .isDirectory),
  ])
  func nonZipIsNotExtracted(url: URL) async {
    let appBundle = AppBundleClientFake()
    let (model, _) = await Self.loadedModel(appBundle: appBundle)

    await model.appFileSelected(url, for: SampleID.iPhoneOn)

    #expect(appBundle.calls == [.inspect(url)])
  }

  // MARK: - 풀기 실패

  @Test("풀기가 실패하면 이유를 알리고 검사·정리·시뮬레이터를 부르지 않으며 다시 읽지 않는다", arguments: [
    AppBundleError.zipUnreadable, .zipWithoutApp, .zipWithMultipleApps, .zipUnsafeEntry, .insufficientDiskSpace,
    .extractionUnavailable, .notLocalFile, .fileNotFound,
  ])
  func extractFailure(error: AppBundleError) async {
    let appBundle = AppBundleClientFake()
    appBundle.setExtractError(error)
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)

    await model.appFileSelected(Self.zip, for: SampleID.iPhoneOff)

    #expect(model.notices.map(\.notice) == [.installFailed(Self.label(SampleID.iPhoneOff), .bundle(error))])
    #expect(appBundle.calls == [.extractApp(Self.zip)])
    #expect(simulator.calls == [.fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
  }

  // MARK: - 풀린 뒤 실패도 정리

  @Test("푼 .app 의 검사가 실패하면 알리고 임시 폴더를 정리한다")
  func inspectFailureAfterExtractCleansUp() async {
    let appBundle = AppBundleClientFake()
    appBundle.setInspectError(.invalidBundle)
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)

    await model.appFileSelected(Self.zip, for: SampleID.iPhoneOff)

    let notice = LauncherNotice.installFailed(Self.label(SampleID.iPhoneOff), .bundle(.invalidBundle))
    #expect(model.notices.map(\.notice) == [notice])
    #expect(appBundle.calls == [.extractApp(Self.zip), .inspect(Self.first.app), .removeExtracted(Self.first)])
    #expect(simulator.calls == [.fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("이 기기에 맞지 않는 빌드로 거절해도 임시 폴더를 정리한다")
  func rejectedBuildCleansUp() async {
    let appBundle = AppBundleClientFake()
    appBundle.setInfo(.deviceBuild)
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)

    await model.appFileSelected(Self.zip, for: SampleID.iPhoneOff)

    let notice = LauncherNotice.installFailed(Self.label(SampleID.iPhoneOff), .rejected(.notSimulatorBuild))
    #expect(model.notices.map(\.notice) == [notice])
    #expect(Self.removals(in: appBundle) == [Self.first])
    #expect(appBundle.calls.last == .removeExtracted(Self.first))
    #expect(simulator.calls == [.fetchInventory])
  }

  @Test("켜기·설치·실행이 실패해도 다시 읽은 뒤 임시 폴더를 한 번 정리한다", arguments: [
    SimulatorStep.boot, .install, .launch,
  ])
  func commandFailureCleansUp(step: SimulatorStep) async {
    let appBundle = AppBundleClientFake()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle) { simulator in
      switch step {
      case .boot: simulator.setBootError(.commandFailed)
      case .install: simulator.setInstallError(.appIncompatible)
      case .launch: simulator.setLaunchError(.appLaunchFailed)
      }
    }
    let id = SampleID.iPhoneOff

    await model.appFileSelected(Self.zip, for: id)

    let expected: LauncherNotice = switch step {
    case .boot: .bootFailed(Self.label(id), .commandFailed)
    case .install: .installFailed(Self.label(id), .simulator(.appIncompatible))
    case .launch: .launchFailed(Self.label(id), .appLaunchFailed)
    }
    #expect(model.notices.map(\.notice) == [expected])
    #expect(simulator.calls.last == .fetchInventory)
    #expect(Self.removals(in: appBundle) == [Self.first])
    #expect(appBundle.calls.last == .removeExtracted(Self.first))
    #expect(model.busyDeviceIDs.isEmpty)
  }

  // MARK: - 풀기 도중 겹침

  @Test("푸는 동안 단계마다 설치 중이고, 같은 기기의 켜기·끄기·두 번째 설치는 호출을 만들지 않는다")
  func extractingBlocksSameDevice() async {
    let appBundle = AppBundleClientFake()
    appBundle.suspendExtractions()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)
    let id = SampleID.iPhoneOff
    let install = Task { await model.appFileSelected(Self.zip, for: id) }
    await Self.waitUntil { appBundle.calls.count == 1 }

    await LauncherInstallTests.expectInstallBlocks(id, model: model, simulator: simulator, appBundle: appBundle)
    let again = Self.start { await model.appDropped([Self.zip], on: id) }
    await Self.waitUntil { again.isFinished || appBundle.calls.count > 1 }
    #expect(appBundle.calls == [.extractApp(Self.zip)])

    appBundle.resumeExtractions()
    await install.value
    await again.value()
    #expect(appBundle.calls == [.extractApp(Self.zip), .inspect(Self.first.app), .removeExtracted(Self.first)])
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("푸는 동안 그 기기의 켜기·삭제·초기화 확인을 받지 않는다")
  func extractingBlocksOtherActions() async {
    let appBundle = AppBundleClientFake()
    appBundle.suspendExtractions()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)
    let id = SampleID.iPhoneOff
    let install = Task { await model.appFileSelected(Self.zip, for: id) }
    await Self.waitUntil { appBundle.calls.count == 1 }

    await model.bootButtonTapped(id)
    model.deleteButtonTapped(id)
    #expect(model.pendingConfirmation == nil)
    model.eraseButtonTapped(id)
    #expect(model.pendingConfirmation == nil)
    for action in [DeviceConfirmation.Action.delete, .erase] {
      await model.confirmationConfirmed(DeviceConfirmation(action: action, deviceID: id, device: Self.label(id)))
    }
    #expect(simulator.calls == [.fetchInventory])
    #expect(model.notices.isEmpty)

    appBundle.resumeExtractions()
    await install.value
  }

  @Test("푸는 동안 기기가 목록에서 사라지면 찾을 수 없다고 알리고 명령 없이 임시 폴더를 정리한다")
  func deviceRemovedDuringExtraction() async {
    let appBundle = AppBundleClientFake()
    appBundle.suspendExtractions()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)
    let id = SampleID.iPhoneOff
    let install = Task { await model.appFileSelected(Self.zip, for: id) }
    await Self.waitUntil { appBundle.calls.count == 1 }
    simulator.setInventory(Self.inventory(removing: id))
    await model.refreshButtonTapped()

    appBundle.resumeExtractions()
    await install.value

    #expect(model.notices.map(\.notice) == [.installFailed(Self.label(id), .simulator(.deviceNotFound))])
    #expect(appBundle.calls == [.extractApp(Self.zip), .inspect(Self.first.app), .removeExtracted(Self.first)])
    #expect(simulator.calls == [.fetchInventory, .fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("같은 zip 을 두 기기에 함께 설치하면 각자 푼 .app 을 설치하고 각자 정리한다")
  func zipOnTwoDevicesConcurrently() async {
    let appBundle = AppBundleClientFake()
    appBundle.suspendExtractions()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle)
    let phone = Task { await model.appFileSelected(Self.zip, for: SampleID.iPhoneOn) }
    let pad = Task { await model.appFileSelected(Self.zip, for: SampleID.iPadOff) }
    await Self.waitUntil { appBundle.calls.count == 2 }
    #expect(model.activity.tasks == [SampleID.iPhoneOn: .installApp, SampleID.iPadOff: .installApp])

    appBundle.resumeExtractions()
    await phone.value
    await pad.value

    let second = ExtractedApp.fake(index: 2)
    #expect(appBundle.calls.filter { $0 == .extractApp(Self.zip) }.count == 2)
    #expect(Set(Self.removals(in: appBundle)) == [Self.first, second])
    #expect(appBundle.calls.contains(.inspect(Self.first.app)))
    #expect(appBundle.calls.contains(.inspect(second.app)))
    #expect(LauncherInstallTests.installCount(in: simulator) == 2)
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(model.notices.isEmpty)
  }
}

extension LauncherZipInstallTests {
  enum SimulatorStep: CaseIterable, Sendable {
    case boot, install, launch
  }

  static func removals(in appBundle: AppBundleClientFake) -> [ExtractedApp] {
    appBundle.calls.compactMap {
      if case let .removeExtracted(extracted) = $0 {
        extracted
      } else {
        nil
      }
    }
  }
}
