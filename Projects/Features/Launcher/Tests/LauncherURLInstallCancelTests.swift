import AppBundleInterface
import AppBundleTesting
import Core
import DownloadInterface
import DownloadTesting
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing
@testable import LauncherFeature

@MainActor
struct LauncherURLInstallCancelTests: LauncherModelTesting {
  static let url = LauncherURLInstallTests.url
  static let file = LauncherURLInstallTests.file
  static let first = LauncherURLInstallTests.first
  static let sample = LauncherURLInstallTests.sample
  static let picked = URL(filePath: "/Users/tester/Downloads/My App.app", directoryHint: .isDirectory)

  static func installFromURL(_ model: LauncherModel, on id: VirtualDevice.ID) async {
    await LauncherURLInstallTests.installFromURL(model, on: id)
  }

  // MARK: - 받는 중 취소

  @Test("받는 중 취소하면 취소 중이 되고, 받기가 .cancelled 로 끝나면 알림 없이 끝나며 풀기·지우기를 부르지 않는다")
  func cancelWhileReceiving() async {
    let appBundle = AppBundleClientFake()
    let download = DownloadClientFake()
    download.suspendDownloads()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle, download: download)
    let id = SampleID.iPhoneOn
    let install = Self.start { await Self.installFromURL(model, on: id) }
    await Self.waitUntil { download.suspendedDownloadCount == 1 }

    model.downloadCancelTapped(id)
    #expect(model.activity.downloadStage(on: id) == .cancelling)
    // 취소 중에 다시 눌러도 바뀌지 않는다.
    model.downloadCancelTapped(id)
    #expect(model.activity.downloadStage(on: id) == .cancelling)

    // 취소가 받기를 멈추지 못하는 회귀에서도 멈추지 않고 실패하게, 끝나기를 제한 시간 안에서 기다린 뒤 정리로만 재개한다.
    await Self.waitUntil { install.isFinished }
    download.resumeDownloads()
    await install.value()
    #expect(model.notices.isEmpty)
    #expect(download.calls == [.download(Self.url.url)])
    #expect(appBundle.calls.isEmpty)
    #expect(simulator.calls == [.fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(model.activity.downloads.isEmpty)
  }

  @Test("마지막 진행 콜백 안에서 취소해도 알림 없이 끝나고 풀지 않는다")
  func cancelInsideLastProgress() async {
    let appBundle = AppBundleClientFake()
    let box = ModelBox()
    let id = SampleID.iPhoneOn
    let fake = DownloadClientFake()
    let download = HookedDownloadClient(fake: fake, point: .lastProgress) { box.model?.downloadCancelTapped(id) }
    let (model, _) = await Self.loadedModel(appBundle: appBundle, download: download)
    box.model = model

    await Self.installFromURL(model, on: id)

    #expect(model.notices.isEmpty)
    #expect(fake.calls == [.download(Self.url.url)])
    #expect(appBundle.calls.isEmpty)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("받기가 성공으로 끝난 뒤 결과를 보기 전에 취소하면(늦은 취소) 받은 파일을 지우고 알림 없이 끝나며 풀지 않는다")
  func lateCancelRemovesDownloadedFile() async {
    let appBundle = AppBundleClientFake()
    let box = ModelBox()
    let id = SampleID.iPhoneOn
    let fake = DownloadClientFake()
    let download = HookedDownloadClient(fake: fake, point: .beforeReturn) { box.model?.downloadCancelTapped(id) }
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle, download: download)
    box.model = model

    await Self.installFromURL(model, on: id)

    #expect(model.notices.isEmpty)
    #expect(fake.calls == [.download(Self.url.url), .removeDownloaded(Self.file)])
    #expect(appBundle.calls.isEmpty)
    #expect(simulator.calls == [.fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(model.activity.downloads.isEmpty)
  }

  @Test("받기가 끝난 뒤(푸는 중)에는 취소를 무시하고 설치를 끝까지 한다")
  func cancelAfterDownloadIsIgnored() async {
    let appBundle = AppBundleClientFake()
    appBundle.suspendExtractions()
    let download = DownloadClientFake()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle, download: download)
    let id = SampleID.iPhoneOn
    let install = Task { await Self.installFromURL(model, on: id) }
    await Self.waitUntil { appBundle.calls.count == 1 }

    model.downloadCancelTapped(id)
    #expect(model.activity.downloadStage(on: id) == nil)
    #expect(model.activity.task(on: id) == .installApp)

    appBundle.resumeExtractions()
    await install.value
    #expect(model.notices.isEmpty)
    #expect(simulator.calls.contains(.launch(Self.sample.bundleID, id)))
    #expect(download.calls == [.download(Self.url.url), .removeDownloaded(Self.file)])
  }

  @Test("받는 중이 아닌 기기의 취소는 아무 일도 하지 않는다")
  func cancelWithoutDownloadDoesNothing() async {
    let (model, simulator) = await Self.loadedModel { $0.suspendBoots() }
    model.downloadCancelTapped(SampleID.iPhoneOn)
    #expect(model.activity == DeviceActivity())

    let boot = Task { await model.bootButtonTapped(SampleID.iPhoneOff) }
    await Self.waitUntil { simulator.calls.contains(.boot(SampleID.iPhoneOff)) }
    model.downloadCancelTapped(SampleID.iPhoneOff)
    #expect(model.activity.task(on: SampleID.iPhoneOff) == .boot)
    #expect(model.activity.downloads.isEmpty)
    simulator.resumeBoots()
    await boot.value
  }

  // MARK: - 겹침

  @Test("받는 중인 기기는 고르기·드롭·링크 열기·켜기·URL 설치 시트를 받지 않고, 새로 고침은 받기 단계를 지우지 않는다")
  func downloadingDeviceBlocksOtherActions() async {
    let appBundle = AppBundleClientFake()
    let download = DownloadClientFake()
    download.suspendDownloads()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle, download: download)
    let id = SampleID.iPhoneOff
    let install = Task { await Self.installFromURL(model, on: id) }
    await Self.waitUntil { download.suspendedDownloadCount == 1 }
    let stage = model.activity.downloadStage(on: id)

    await model.appFileSelected(Self.picked, for: id)
    await model.appDropped([Self.picked], on: id)
    model.openURLButtonTapped(id)
    model.installFromURLMenuTapped(id)
    await model.bootButtonTapped(id)
    model.deleteButtonTapped(id)
    await model.refreshButtonTapped()

    #expect(appBundle.calls.isEmpty)
    #expect(model.openURLDraft == nil)
    #expect(model.installURLDraft == nil)
    #expect(model.pendingConfirmation == nil)
    #expect(Self.bootCount(id, in: simulator) == 0)
    #expect(model.activity.downloadStage(on: id) == stage)
    #expect(model.activity.task(on: id) == .installApp)

    download.resumeDownloads()
    await install.value
    #expect(model.notices.isEmpty)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("받는 동안 다른 기기에는 고른 앱을 설치할 수 있다")
  func otherDeviceInstallsWhileDownloading() async {
    let appBundle = AppBundleClientFake()
    let download = DownloadClientFake()
    download.suspendDownloads()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle, download: download)
    let install = Task { await Self.installFromURL(model, on: SampleID.iPhoneOn) }
    await Self.waitUntil { download.suspendedDownloadCount == 1 }

    await model.appFileSelected(Self.picked, for: SampleID.iPadOff)

    #expect(simulator.calls.contains(.install(Self.sample.location, SampleID.iPadOff)))
    #expect(model.activity.downloadStage(on: SampleID.iPhoneOn) != nil)

    download.resumeDownloads()
    await install.value
    #expect(simulator.calls.contains(.install(Self.sample.location, SampleID.iPhoneOn)))
    #expect(model.notices.isEmpty)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("두 기기에서 함께 받다가 하나를 취소하면 그 기기만 멈추고 다른 기기는 설치까지 간다")
  func cancelOneOfTwoDownloads() async {
    let appBundle = AppBundleClientFake()
    let download = DownloadClientFake()
    download.suspendDownloads()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle, download: download)
    let phone = Self.start { await Self.installFromURL(model, on: SampleID.iPhoneOn) }
    await Self.waitUntil { download.suspendedDownloadCount == 1 }
    let pad = Task { await Self.installFromURL(model, on: SampleID.iPadOff) }
    await Self.waitUntil { download.suspendedDownloadCount == 2 }

    model.downloadCancelTapped(SampleID.iPhoneOn)
    // 취소가 받기를 멈추지 못하는 회귀에서도 멈추지 않고 실패하게 제한 시간 안에서 기다린다 (재개는 아래에서 함께).
    await Self.waitUntil { phone.isFinished }
    #expect(model.activity.task(on: SampleID.iPhoneOn) == nil)
    #expect(model.activity.downloadStage(on: SampleID.iPadOff) != nil)

    download.resumeDownloads()
    await phone.value()
    await pad.value
    #expect(model.notices.isEmpty)
    #expect(simulator.calls.contains(.install(Self.sample.location, SampleID.iPadOff)))
    #expect(!simulator.calls.contains(.install(Self.sample.location, SampleID.iPhoneOn)))
    #expect(appBundle.calls.count == 3)
    #expect(model.busyDeviceIDs.isEmpty)
  }
}

/// 받기 Client 를 만든 뒤에 Model 을 넣는 상자 (스텁의 hook 이 Model 의 취소 이벤트를 부른다).
@MainActor
private final class ModelBox {
  var model: LauncherModel?
}

/// 받기 중 정한 시점에 MainActor 에서 `hook` 을 부르는 Client. 나머지는 Fake 에 넘긴다.
/// Fake 로는 "받기가 성공으로 끝난 뒤 Model 이 결과를 보기 전" 의 틈을 결정적으로 만들 수 없어 둔다.
private struct HookedDownloadClient: DownloadClient {
  enum Point {
    /// Fake 의 마지막 진행 알림(샘플 진행의 끝)을 넘긴 직후. 취소는 Fake 계약대로 `.cancelled` 가 된다.
    case lastProgress
    /// Fake 가 성공으로 돌아온 뒤 돌려주기 직전. 이 스텁은 그 뒤의 Task 취소를 무시하고 성공을 돌려준다 (늦은 취소).
    case beforeReturn
  }

  let fake: DownloadClientFake
  let point: Point
  let hook: @MainActor @Sendable () -> Void

  func download(
    _ url: DownloadURL,
    onProgress: @escaping @Sendable (DownloadProgress) async -> Void
  ) async throws(DownloadError) -> DownloadedFile {
    switch self.point {
    case .lastProgress:
      let hook = self.hook
      return try await self.fake.download(url) { progress in
        await onProgress(progress)
        if progress == DownloadProgress.samples.last {
          await hook()
        }
      }
    case .beforeReturn:
      let file = try await self.fake.download(url, onProgress: onProgress)
      await self.hook()
      return file
    }
  }

  func fetchData(_ url: DownloadURL, maxBytes: Int) async throws(DownloadError) -> Data {
    try await self.fake.fetchData(url, maxBytes: maxBytes)
  }

  func removeDownloaded(_ file: DownloadedFile) async {
    await self.fake.removeDownloaded(file)
  }

  func removeLeftoverDownloads() async {
    await self.fake.removeLeftoverDownloads()
  }
}
