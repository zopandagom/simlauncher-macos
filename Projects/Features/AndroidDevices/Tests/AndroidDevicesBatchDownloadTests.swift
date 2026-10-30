import AndroidEmulatorInterface
import AndroidEmulatorTesting
import AndroidPackageInterface
import AndroidPackageTesting
import Core
import DownloadInterface
import DownloadTesting
import Foundation
import Testing
@testable import AndroidDevicesFeature

/// 툴바 "선택한 기기에 앱 설치" > "URL 에서…"·"카탈로그에서…" 의 여러 기기 요청 (`downloadInstallRequested`): 받기 묶음 하나로 한 번
/// 받고(대상 행 모두에 진행·어느 행에서든 함께 취소) → 한 번 검사 → 기기별 설치·실행 → 모든 기기가 끝난 뒤 받은 파일을 한 번 지운다.
@MainActor
struct AndroidDevicesBatchDownloadTests: AndroidDevicesTesting {
  static let tablet = AndroidVirtualDevice.bootedTabletSample
  static let second = AndroidVirtualDevice.secondPhoneSample.with(state: .booted)
  static let url = DownloadURL("https://builds.example.com/Sample-42.apk")!
  /// Fake 의 첫 받기 결과 (`.apk` 이름).
  static let file = DownloadedFile.fake(index: 1, name: .apk)
  static let info = AndroidPackageInfo.sample()
  static let inventory = AndroidDeviceInventory(
    devices: [.phoneSample, .bootedTabletSample, second, .unsupportedNameSample],
    creationOptions: .sample
  )

  static func request(_ devices: [AndroidVirtualDevice] = [tablet, second]) -> AndroidDownloadInstallRequest {
    AndroidDownloadInstallRequest(targets: devices.map(AndroidTargetDevice.init), url: self.url, origin: .enteredURL)
  }

  static func removals(_ download: DownloadClientFake) -> [DownloadedFile] {
    download.calls.compactMap {
      if case let .removeDownloaded(file) = $0 {
        file
      } else {
        nil
      }
    }
  }

  static func installs(_ fake: AndroidEmulatorClientFake) -> [AndroidEmulatorClientFake.Call] {
    fake.calls.filter {
      if case .install = $0 {
        true
      } else {
        false
      }
    }
  }

  // MARK: - 받기 묶음

  @Test("한 번 받고, 받는 동안 대상 행 모두에 같은 진행과 묶음 크기를 보이며, 받은 뒤 한 번 검사해 기기마다 설치한다")
  func downloadsOnceForAllTargets() async {
    let setup = await Self.loadedFixture(Self.inventory)
    setup.download.setDownloadScript(progress: [], result: nil)
    setup.download.suspendDownloads()
    let task = Self.start { await setup.model.downloadInstallRequested(Self.request()) }
    await Self.waitUntil { setup.download.suspendedDownloadCount == 1 }
    for id in [Self.tablet.id, Self.second.id] {
      #expect(setup.model.activity.downloadStage(on: id) == .receiving(nil))
      #expect(setup.model.activity.downloadGroupSize(on: id) == 2)
    }
    let progress = DownloadProgress(receivedBytes: 512, expectedBytes: 1024)
    await setup.download.sendDownloadProgress(progress)
    #expect(setup.model.activity.downloadStage(on: Self.tablet.id) == .receiving(progress))
    #expect(setup.model.activity.downloadStage(on: Self.second.id) == .receiving(progress))
    setup.download.resumeDownloads()
    await task.value()
    #expect(setup.download.downloadRequests == [.init(url: Self.url, name: .apk)])
    #expect(setup.package.calls == [Self.file.file])
    #expect(Set(Self.installs(setup.fake)) == [
      .install(Self.info.location, Self.tablet.id), .install(Self.info.location, Self.second.id),
    ])
    #expect(Self.removals(setup.download) == [Self.file])
    #expect(Self.notices(setup.model).isEmpty)
    #expect(setup.model.activity.busyDeviceIDs.isEmpty)
  }

  @Test("어느 행에서 취소하든 묶음 전체가 취소 중이 되고, 받기가 멈추면 알림·검사·설치 없이 모든 행이 풀린다")
  func cancelFromAnyRowCancelsAll() async {
    let setup = await Self.loadedFixture(Self.inventory)
    setup.download.suspendDownloads()
    let task = Self.start { await setup.model.downloadInstallRequested(Self.request()) }
    await Self.waitUntil { setup.download.suspendedDownloadCount == 1 }
    setup.model.downloadCancelTapped(Self.second.id)
    #expect(setup.model.activity.downloadStage(on: Self.tablet.id) == .cancelling)
    #expect(setup.model.activity.downloadStage(on: Self.second.id) == .cancelling)
    #expect(setup.model.activity.downloadGroupSize(on: Self.tablet.id) == 0)
    await task.value()
    #expect(Self.notices(setup.model).isEmpty)
    #expect(setup.package.calls.isEmpty)
    #expect(Self.installs(setup.fake).isEmpty)
    #expect(Self.removals(setup.download).isEmpty)
    #expect(Self.fetchCount(setup.fake) == 1)
    #expect(setup.model.activity.busyDeviceIDs.isEmpty)
  }

  @Test("막 끝난 성공 뒤 취소가 이기면(여러 대) 받은 파일을 한 번 지우고 알림·검사 없이 끝난다 (흐름)")
  func lateCancelRemovesFileOnce() async {
    let setup = await Self.loadedFixture(Self.inventory)
    let flow = AndroidAppInstallFlow(emulator: setup.fake, package: setup.package, download: setup.download)
    let enqueued = Counter()
    let host = AndroidAppInstallFlow.Host(
      enqueue: { _ in enqueued.increment() },
      reload: {},
      listState: { setup.model.listState },
      finished: { _, _ in }
    )
    let start = AndroidInstallStart(
      requested: Self.request().targets,
      begun: [Self.tablet, Self.second],
      skipped: [],
      owner: 1
    )
    await flow.installDownloaded(.success(Self.file), cancelRequested: true, start: start, origin: .catalog, host: host)
    #expect(Self.removals(setup.download) == [Self.file])
    #expect(enqueued.value == 0)
    #expect(setup.package.calls.isEmpty)
  }

  // MARK: - 공통 단계 실패

  @Test("받기 실패는 대상 모두의 공통 알림 하나이고 다시 읽지 않는다")
  func downloadFailureIsOneNotice() async {
    let setup = await Self.loadedFixture(Self.inventory)
    setup.download.setDownloadScript(progress: [], result: .failure(.httpStatus(404)))
    await setup.model.downloadInstallRequested(Self.request())
    #expect(Self.notices(setup.model) == [.batchInstallFailed(
      [AndroidDeviceLabel(Self.tablet), AndroidDeviceLabel(Self.second)],
      .download(.httpStatus(404), origin: .enteredURL)
    )])
    #expect(Self.fetchCount(setup.fake) == 1)
    #expect(setup.model.activity.busyDeviceIDs.isEmpty)
  }

  @Test("받은 파일의 검사 실패는 받은 파일을 지우고 공통 알림 하나 (공통 단계 실패 때 건너뛴 기기는 따로 알리지 않는다)")
  func inspectionFailureRemovesFile() async {
    let setup = await Self.loadedFixture(Self.inventory)
    setup.package.setResult(.failure(.notAPK))
    await setup.model.downloadInstallRequested(Self.request([.phoneSample, Self.tablet, Self.second]))
    #expect(Self.removals(setup.download) == [Self.file])
    let labels = [AndroidVirtualDevice.phoneSample, Self.tablet, Self.second].map(AndroidDeviceLabel.init)
    #expect(Self.notices(setup.model) == [
      .batchInstallFailed(labels, .downloadedPackage(.notAPK, isWebPage: false, origin: .enteredURL)),
    ])
  }

  // MARK: - 받은 파일·행 풀기

  @Test("받은 파일은 모든 기기의 흐름이 끝난 뒤 한 번만 지우고, 건너뛴 기기는 결과 알림에 든다")
  func removesAfterAllDevices() async {
    let setup = await Self.loadedFixture(Self.inventory) { $0.suspendInstall(of: Self.second.id) }
    let task = Self.start {
      await setup.model.downloadInstallRequested(Self.request([.phoneSample, Self.tablet, Self.second]))
    }
    await Self.waitUntil {
      setup.model.activity.task(on: Self.tablet.id) == nil && Self.installs(setup.fake).count == 2
    }
    #expect(Self.removals(setup.download).isEmpty)
    setup.fake.resumeInstall(of: Self.second.id)
    await task.value()
    #expect(Self.removals(setup.download) == [Self.file])
    #expect(Self.notices(setup.model) == [.batchInstallFinished(AndroidBatchInstallReport(entries: [
      .init(device: AndroidDeviceLabel(.phoneSample), result: .installFailed(.deviceNotReady(.notBooted))),
      .init(device: AndroidDeviceLabel(Self.tablet), result: .succeeded),
      .init(device: AndroidDeviceLabel(Self.second), result: .succeeded),
    ]))])
  }

  @Test("먼저 끝난 기기에서 새 URL 받기를 시작하면 그 행의 취소가 듣는다 (묶음 끝이 새 받기 Task·기록을 지우지 않는다)")
  func newDownloadOnReleasedDeviceStaysCancellable() async {
    let setup = await Self.loadedFixture(Self.inventory) { $0.suspendInstall(of: Self.second.id) }
    let batch = Self.start { await setup.model.downloadInstallRequested(Self.request()) }
    await Self.waitUntil {
      setup.model.activity.task(on: Self.tablet.id) == nil && Self.installs(setup.fake).count == 2
    }
    // 새 받기는 진행을 보내지 않아, 묶음이 끝난 뒤에도 그 받기의 첫 단계(`.receiving(nil)`)가 남아 있는지 본다.
    setup.download.setDownloadScript(progress: [], result: nil)
    setup.download.suspendDownloads()
    let next = Self.start { await setup.model.downloadInstallRequested(Self.request([Self.tablet])) }
    await Self.waitUntil { setup.download.suspendedDownloadCount == 1 }
    setup.fake.resumeInstall(of: Self.second.id)
    await batch.value()
    #expect(setup.model.activity.downloadStage(on: Self.tablet.id) == .receiving(nil))
    setup.model.downloadCancelTapped(Self.tablet.id)
    await next.value()
    #expect(setup.model.activity.busyDeviceIDs.isEmpty)
    #expect(Self.removals(setup.download) == [Self.file])
    #expect(Self.notices(setup.model).isEmpty)
  }

  @Test("여러 대 요청에서 시작한 기기가 없으면 받지 않고 결과 알림(모두 건너뜀) 하나")
  func notStarted() async {
    let setup = await Self.loadedFixture(Self.inventory)
    await setup.model.downloadInstallRequested(Self.request([.phoneSample, .unsupportedNameSample]))
    #expect(setup.download.downloadRequests.isEmpty)
    #expect(Self.notices(setup.model) == [.batchInstallFinished(AndroidBatchInstallReport(entries: [
      .init(device: AndroidDeviceLabel(.phoneSample), result: .installFailed(.deviceNotReady(.notBooted))),
      .init(device: AndroidDeviceLabel(.unsupportedNameSample), result: .installFailed(.deviceNotReady(.unavailable))),
    ]))])
  }
}
