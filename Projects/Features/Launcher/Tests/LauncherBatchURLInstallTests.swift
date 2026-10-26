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

/// 툴바 "선택한 기기에 앱 설치" > "URL 에서…" 와 대상 여러 대의 카탈로그 요청: 한 번 받고 풀어 기기별로 설치한다.
@MainActor
struct LauncherBatchURLInstallTests: LauncherModelTesting {
  static let raw = LauncherURLInstallTests.raw
  static let url = LauncherURLInstallTests.url
  static let file = DownloadedFile.fake(index: 1)
  static let first = ExtractedApp.fake(index: 1)
  static let sample = AppBundleInfo.sample

  /// 고른 기기로 툴바 "URL 에서…" 시트를 열고 주소를 넣어 받아서 설치를 누른다.
  static func installSelected(_ model: LauncherModel, on ids: Set<VirtualDevice.ID>) async {
    model.selectionChanged(ids)
    model.installSelectedFromURLMenuTapped()
    model.installURLTextChanged(self.raw)
    await model.installURLConfirmTapped()
  }

  static func launches(in simulator: SimulatorClientFake) -> Set<SimulatorClientFake.Call> {
    Set(simulator.calls.filter {
      if case .launch = $0 {
        true
      } else {
        false
      }
    })
  }

  static func labels(_ ids: [VirtualDevice.ID]) -> [LauncherNotice.Device] {
    ids.map { label($0) }
  }

  // MARK: - 받기 한 번

  @Test("한 번 받고 한 번 풀어 기기마다 설치·실행하고, 받은 파일과 푼 폴더를 한 번씩 지우며 알림이 없다")
  func downloadsOnceAndInstallsEach() async {
    let appBundle = AppBundleClientFake()
    let download = DownloadClientFake()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle, download: download)

    await Self.installSelected(model, on: [SampleID.iPhoneOn, SampleID.iPhoneOff])

    #expect(download.calls == [.download(Self.url.url), .removeDownloaded(Self.file)])
    #expect(appBundle.calls == [.extractApp(Self.file.file), .inspect(Self.first.app), .removeExtracted(Self.first)])
    #expect(Self.launches(in: simulator) == [
      .launch(Self.sample.bundleID, SampleID.iPhoneOn), .launch(Self.sample.bundleID, SampleID.iPhoneOff),
    ])
    #expect(model.notices.isEmpty)
    #expect(model.activity == DeviceActivity())
  }

  @Test("받는 동안 대상 행 모두에 같은 진행이 보이고 묶음 크기는 대상 수다")
  func progressShowsOnEveryTarget() async {
    let download = DownloadClientFake()
    download.suspendDownloads()
    let (model, _) = await Self.loadedModel(download: download)
    let install = Self.start { await Self.installSelected(model, on: [SampleID.iPhoneOn, SampleID.iPadOff]) }
    await Self.waitUntil { download.suspendedDownloadCount == 1 }
    let progress = DownloadProgress(receivedBytes: 512, expectedBytes: 1024)

    await download.sendDownloadProgress(progress)

    #expect(model.activity.downloadStage(on: SampleID.iPhoneOn) == .receiving(progress))
    #expect(model.activity.downloadStage(on: SampleID.iPadOff) == .receiving(progress))
    #expect(model.activity.downloadGroupSize(on: SampleID.iPadOff) == 2)
    download.resumeDownloads()
    await install.value()
    #expect(model.notices.isEmpty)
  }

  @Test("한 행에서 취소하면 대상 모두가 취소 중이 되고, 알림 없이 모두 풀리며 풀지 않는다")
  func cancelOnOneRowStopsAll() async {
    let appBundle = AppBundleClientFake()
    let download = DownloadClientFake()
    download.suspendDownloads()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle, download: download)
    let install = Self.start { await Self.installSelected(model, on: [SampleID.iPhoneOn, SampleID.iPhoneOff]) }
    await Self.waitUntil { download.suspendedDownloadCount == 1 }

    model.downloadCancelTapped(SampleID.iPhoneOff)
    #expect(model.activity.downloadStage(on: SampleID.iPhoneOff) == .cancelling)
    #expect(model.activity.downloadStage(on: SampleID.iPhoneOn) == .cancelling)

    await Self.waitUntil { install.isFinished }
    download.resumeDownloads()
    await install.value()
    #expect(model.notices.isEmpty)
    #expect(download.calls == [.download(Self.url.url)])
    #expect(appBundle.calls.isEmpty)
    #expect(simulator.calls == [.fetchInventory])
    #expect(model.activity == DeviceActivity())
  }

  // MARK: - 실패

  @Test("받기가 실패하면 출처에 맞는 공통 단계 실패 알림 하나다 (URL·카탈로그)")
  func downloadFailureIsOneNotice() async {
    let ids = [SampleID.iPhoneOff, SampleID.iPhoneOn]
    let urlDownload = LauncherURLInstallTests.download(result: .failure(.offline))
    let (urlModel, _) = await Self.loadedModel(download: urlDownload)
    await Self.installSelected(urlModel, on: Set(ids))

    let catalogDownload = LauncherURLInstallTests.download(result: .failure(.offline))
    let (catalogModel, _) = await Self.loadedModel(download: catalogDownload)
    let targets = ids.map { TargetDevice(id: $0, label: Self.label($0)) }
    await catalogModel.catalogInstallRequested(CatalogInstallRequest(targets: targets, buildURL: Self.url))

    #expect(urlModel.notices.map(\.notice) == [.batchInstallFailed(Self.labels(ids), .download(.offline))])
    #expect(catalogModel.notices.map(\.notice) == [.batchInstallFailed(Self.labels(ids), .catalogDownload(.offline))])
    #expect(urlModel.activity == DeviceActivity())
    #expect(catalogModel.activity == DeviceActivity())
  }

  @Test("받는 동안 대상 하나가 목록에서 사라지면 그 기기만 기기 없음으로 결과 알림에 넣는다")
  func removedTargetFailsAlone() async {
    let download = DownloadClientFake()
    download.suspendDownloads()
    let (model, simulator) = await Self.loadedModel(download: download)
    let install = Self.start { await Self.installSelected(model, on: [SampleID.iPhoneOn, SampleID.iPadOff]) }
    await Self.waitUntil { download.suspendedDownloadCount == 1 }

    simulator.setInventory(Self.inventory(removing: SampleID.iPadOff))
    await model.refreshButtonTapped()
    download.resumeDownloads()
    await install.value()

    #expect(Self.launches(in: simulator) == [.launch(Self.sample.bundleID, SampleID.iPhoneOn)])
    #expect(model.notices.map(\.notice) == [
      .batchFinished(BatchReport(
        action: .install,
        entries: [
          BatchReport.Entry(device: Self.label(SampleID.iPhoneOn), result: .succeeded),
          BatchReport.Entry(
            device: Self.label(SampleID.iPadOff),
            result: .installFailed(.simulator(.deviceNotFound))
          ),
        ],
        simulatorAppError: nil
      )),
    ])
    #expect(model.activity == DeviceActivity())
  }

  @Test("받는 동안 대상 모두가 목록에서 사라지면 풀지 않고 받은 파일을 지운 뒤 모두 기기 없음인 결과 알림 하나다")
  func allTargetsRemovedSkipsExtraction() async {
    let appBundle = AppBundleClientFake()
    let download = DownloadClientFake()
    download.suspendDownloads()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle, download: download)
    let install = Self.start { await Self.installSelected(model, on: [SampleID.iPhoneOn, SampleID.iPadOff]) }
    await Self.waitUntil { download.suspendedDownloadCount == 1 }

    let sample = DeviceInventory.sample
    simulator.setInventory(DeviceInventory(
      devices: sample.devices.filter { ![SampleID.iPhoneOn, SampleID.iPadOff].contains($0.id) },
      runtimes: sample.runtimes,
      deviceTypes: sample.deviceTypes
    ))
    await model.refreshButtonTapped()
    download.resumeDownloads()
    await install.value()

    #expect(download.calls == [.download(Self.url.url), .removeDownloaded(Self.file)])
    #expect(appBundle.calls.isEmpty)
    #expect(Self.launches(in: simulator).isEmpty)
    #expect(model.notices.map(\.notice) == [
      .batchFinished(BatchReport(
        action: .install,
        entries: [SampleID.iPhoneOn, SampleID.iPadOff].map {
          BatchReport.Entry(device: Self.label($0), result: .installFailed(.simulator(.deviceNotFound)))
        },
        simulatorAppError: nil
      )),
    ])
    #expect(model.activity == DeviceActivity())
  }

  @Test("시트를 연 사이 대상 모두가 다른 작업 중이 되면 받지 않고 모두 실패한 결과 알림 하나다")
  func allTargetsBusyAfterSheetOpened() async {
    let download = DownloadClientFake()
    let (model, simulator) = await Self.loadedModel(download: download) { $0.suspendBoots() }
    model.selectionChanged([SampleID.iPhoneOff, SampleID.iPadOff])
    model.installSelectedFromURLMenuTapped()
    model.installURLTextChanged(Self.raw)
    let boots = [SampleID.iPhoneOff, SampleID.iPadOff].map { id in
      Task { await model.bootButtonTapped(id) }
    }
    await Self.waitUntil {
      simulator.calls.contains(.boot(SampleID.iPhoneOff)) && simulator.calls.contains(.boot(SampleID.iPadOff))
    }

    await model.installURLConfirmTapped()

    #expect(download.calls.isEmpty)
    #expect(model.notices.map(\.notice) == [
      .batchFinished(BatchReport(
        action: .install,
        entries: [SampleID.iPhoneOff, SampleID.iPadOff].map {
          BatchReport.Entry(device: Self.label($0), result: .installFailed(.deviceBusy))
        },
        simulatorAppError: nil
      )),
    ])
    simulator.resumeBoots()
    for boot in boots {
      await boot.value
    }
  }

  @Test("대상 두 대의 카탈로그 요청도 한 번 받아 두 기기에 설치한다")
  func catalogRequestWithTwoTargets() async {
    let download = DownloadClientFake()
    let (model, simulator) = await Self.loadedModel(download: download)
    let targets = [SampleID.iPhoneOff, SampleID.iPhoneOn].map { TargetDevice(id: $0, label: Self.label($0)) }

    await model.catalogInstallRequested(CatalogInstallRequest(targets: targets, buildURL: CatalogData.alphaV2URL))

    #expect(download.calls == [.download(CatalogData.alphaV2URL.url), .removeDownloaded(Self.file)])
    #expect(Self.launches(in: simulator).count == 2)
    #expect(model.notices.isEmpty)
  }

  // MARK: - 시트 열기

  @Test("툴바 URL 메뉴는 선택 없음·다른 시트나 확인 대화상자·모두 설치 불가면 열지 않고, 열면 대상이 목록 순서다")
  func selectionMenuGuardsAndOrder() async {
    let (model, _) = await Self.loadedModel()
    model.installSelectedFromURLMenuTapped()
    #expect(model.installURLDraft == nil)

    model.selectionChanged([SampleID.unavailableIPhone])
    model.installSelectedFromURLMenuTapped()
    #expect(model.installURLDraft == nil)

    model.selectionChanged([SampleID.iPadOff, SampleID.iPhoneOff, SampleID.unavailableIPhone])
    model.createButtonTapped()
    model.installSelectedFromURLMenuTapped()
    #expect(model.installURLDraft == nil)
    model.createCancelTapped()

    model.deleteButtonTapped(SampleID.iPhoneOff)
    model.installSelectedFromURLMenuTapped()
    #expect(model.installURLDraft == nil)
    model.confirmationDismissed()

    model.installSelectedFromURLMenuTapped()
    #expect(model.installURLDraft?.targets.map(\.id) == [
      SampleID.iPhoneOff, SampleID.iPadOff, SampleID.unavailableIPhone,
    ])
  }

  @Test("고른 기기가 한 대면 행 메뉴 경로와 같다: 받기 실패는 기존 설치 실패 알림 하나다")
  func singleSelectionMatchesRow() async {
    let download = LauncherURLInstallTests.download(result: .failure(.offline))
    let (model, _) = await Self.loadedModel(download: download)
    model.selectionChanged([SampleID.iPhoneOn])
    model.installSelectedFromURLMenuTapped()
    #expect(model.installURLDraft?.targets == [TargetDevice(
      id: SampleID.iPhoneOn,
      label: Self.label(SampleID.iPhoneOn)
    )])
    model.installURLTextChanged(Self.raw)

    await model.installURLConfirmTapped()

    #expect(model.notices.map(\.notice) == [.installFailed(Self.label(SampleID.iPhoneOn), .download(.offline))])
    #expect(model.activity == DeviceActivity())
  }
}
