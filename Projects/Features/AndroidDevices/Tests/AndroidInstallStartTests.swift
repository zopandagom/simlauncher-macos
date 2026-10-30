import AndroidEmulatorInterface
import AndroidEmulatorTesting
import Core
import DownloadInterface
import Testing
@testable import AndroidDevicesFeature

/// 여러 기기 설치의 시작 판정(`AndroidDeviceActivity.beginInstall`)·받기 묶음·소유자 번호, 결과 모으기(`AndroidInstallStart`).
struct AndroidInstallStartTests {
  static let tablet = AndroidVirtualDevice.bootedTabletSample
  static let second = AndroidVirtualDevice.secondPhoneSample.with(state: .booted)
  static let list = AndroidDevicesListState.loaded(AndroidDeviceList(devices: [
    .phoneSample, .bootedTabletSample, second, .unsupportedNameSample,
  ]))
  static let progress = DownloadProgress(receivedBytes: 1, expectedBytes: 2)

  static func targets(_ devices: [AndroidVirtualDevice]) -> [AndroidTargetDevice] {
    devices.map(AndroidTargetDevice.init)
  }

  @Test("대상마다 판정한다: 켜진 기기는 시작, 꺼짐·쓸 수 없음은 이유, 목록에 없음은 deviceNotFound, 다른 작업 중은 deviceBusy")
  func judgesEachTarget() {
    var activity = AndroidDeviceActivity()
    _ = activity.begin(.launchApp, on: Self.second)
    let gone = AndroidVirtualDevice.bootingSample
    let targets = Self.targets([.phoneSample, Self.tablet, Self.second, .unsupportedNameSample, gone])
    let start = activity.beginInstall(on: targets, in: Self.list, downloading: false)
    #expect(start.begun == [Self.tablet])
    #expect(start.skipped == [
      .init(target: targets[0], failure: .deviceNotReady(.notBooted)),
      .init(target: targets[2], failure: .deviceBusy),
      .init(target: targets[3], failure: .deviceNotReady(.unavailable)),
      .init(target: targets[4], failure: .emulator(.deviceNotFound)),
    ])
    #expect(activity.task(on: Self.tablet.id) == .installApp)
    #expect(activity.downloadStage(on: Self.tablet.id) == nil)
    #expect(!start.isSingle)
  }

  @Test("목록이 없으면 모든 대상이 deviceNotFound 로 건너뛴다")
  func notLoaded() {
    var activity = AndroidDeviceActivity()
    let start = activity.beginInstall(on: Self.targets([Self.tablet]), in: .loading, downloading: true)
    #expect(start.begun.isEmpty)
    #expect(start.skipped.map(\.failure) == [.emulator(.deviceNotFound)])
    #expect(start.isSingle)
  }

  @Test("받기로 시작하면 시작한 기기 모두가 한 받기 묶음이고, 진행·취소·크기가 묶음 단위다")
  func downloadGroup() {
    var activity = AndroidDeviceActivity()
    let start = activity.beginInstall(on: Self.targets([Self.tablet, Self.second]), in: Self.list, downloading: true)
    let ids = start.begun.map(\.id)
    #expect(ids == [Self.tablet.id, Self.second.id])
    #expect(activity.downloadGroupSize(on: Self.tablet.id) == 2)
    activity.downloadProgressed(Self.progress, on: ids)
    #expect(activity.downloadStage(on: Self.second.id) == .receiving(Self.progress))
    let cancelled = activity.requestDownloadCancel(on: Self.tablet.id)
    #expect(cancelled)
    #expect(activity.downloadStage(on: Self.second.id) == .cancelling)
    #expect(activity.isDownloadCancelRequested(on: Self.second.id))
    let cancelledAgain = activity.requestDownloadCancel(on: Self.second.id)
    #expect(!cancelledAgain)
    #expect(activity.downloadGroupSize(on: Self.tablet.id) == 0)
    activity.downloadEnded(on: ids)
    #expect(activity.downloadStage(on: Self.tablet.id) == nil)
    #expect(activity.task(on: Self.tablet.id) == .installApp)
  }

  @Test("받기 묶음은 서로 섞이지 않는다: 다른 묶음의 취소는 이 묶음을 멈추지 않는다")
  func groupsAreSeparate() {
    var activity = AndroidDeviceActivity()
    _ = activity.beginInstall(on: Self.targets([Self.tablet]), in: Self.list, downloading: true)
    _ = activity.beginInstall(on: Self.targets([Self.second]), in: Self.list, downloading: true)
    #expect(activity.downloadGroupSize(on: Self.tablet.id) == 1)
    let cancelled = activity.requestDownloadCancel(on: Self.second.id)
    #expect(cancelled)
    #expect(activity.downloadStage(on: Self.tablet.id) == .receiving(nil))
  }

  @Test("묶음의 끝(소유자 번호)은 먼저 풀린 기기에 새로 시작한 기록을 지우지 않는다")
  func ownerProtectsNewWork() {
    var activity = AndroidDeviceActivity()
    let start = activity.beginInstall(on: Self.targets([Self.tablet, Self.second]), in: Self.list, downloading: false)
    activity.end(on: Self.tablet.id, owner: start.owner)
    let began = activity.begin(.openURL, on: Self.tablet)
    #expect(began)
    for device in start.begun {
      activity.end(on: device.id, owner: start.owner)
    }
    #expect(activity.task(on: Self.tablet.id) == .openURL)
    #expect(activity.task(on: Self.second.id) == nil)
  }

  @Test("결과는 요청 순서로 모으고, 건너뛴 대상은 그 이유로 넣고, 공통 실패는 1대면 한 기기 알림이다")
  func reportAndFailedNotice() {
    var activity = AndroidDeviceActivity()
    let targets = Self.targets([.phoneSample, Self.tablet])
    let start = activity.beginInstall(on: targets, in: Self.list, downloading: false)
    let report = start.report(results: [Self.tablet.id: .launchFailed(.appCommandFailed)])
    #expect(report.entries == [
      .init(device: targets[0].label, result: .installFailed(.deviceNotReady(.notBooted))),
      .init(device: targets[1].label, result: .launchFailed(.appCommandFailed)),
    ])
    #expect(report.successCount == 1)
    #expect(report.needsNotice)
    #expect(!AndroidBatchInstallReport(entries: [.init(device: targets[1].label, result: .succeeded)]).needsNotice)
    #expect(start.failedNotice(.package(.appBundle)) == .batchInstallFailed(targets.map(\.label), .package(.appBundle)))
    let single = activity.beginInstall(on: [targets[0]], in: Self.list, downloading: false)
    #expect(single.failedNotice(.package(.appBundle)) == .installFailed(targets[0].label, .package(.appBundle)))
  }
}
