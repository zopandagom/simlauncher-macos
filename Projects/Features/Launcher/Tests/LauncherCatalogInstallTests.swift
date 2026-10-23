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

/// `LauncherModel.catalogInstallRequested(_:)`: 카탈로그 버전을 URL 설치와 같은 경로로 받아 설치하고, 받기·받은 파일 실패는
/// 카탈로그 출처의 알림으로 낸다.
@MainActor
struct LauncherCatalogInstallTests: LauncherModelTesting {
  static let url = CatalogData.alphaV2URL
  static let file = DownloadedFile.fake(index: 1)
  static let first = ExtractedApp.fake(index: 1)
  static let sample = AppBundleInfo.sample

  static func request(_ id: VirtualDevice.ID) -> CatalogInstallRequest {
    CatalogInstallRequest(deviceID: id, device: label(id), buildURL: self.url)
  }

  static func download(result: Result<DownloadedFile, DownloadError>) -> DownloadClientFake {
    let download = DownloadClientFake()
    download.setDownloadScript(progress: [], result: result)
    return download
  }

  @Test("받기 → 풀기 → 받은 파일 지우기 → 검사 → (꺼져 있으면 켜기) → 설치 → 실행 → 다시 읽기 → 푼 폴더 정리이고 알림이 없다", arguments: [
    SampleID.iPhoneOn, SampleID.iPhoneOff,
  ])
  func installsLikeURLInstall(id: VirtualDevice.ID) async {
    let appBundle = AppBundleClientFake()
    let download = DownloadClientFake()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle, download: download)

    await model.catalogInstallRequested(Self.request(id))

    #expect(download.calls == [.download(Self.url.url), .removeDownloaded(Self.file)])
    #expect(appBundle.calls == [.extractApp(Self.file.file), .inspect(Self.first.app), .removeExtracted(Self.first)])
    let boot: [SimulatorClientFake.Call] = id == SampleID.iPhoneOff ? [.boot(id)] : []
    var expected: [SimulatorClientFake.Call] = [.fetchInventory]
    expected += boot
    expected += [
      .openSimulatorApp,
      .install(Self.sample.location, id),
      .launch(Self.sample.bundleID, id),
      .fetchInventory,
    ]
    #expect(simulator.calls == expected)
    #expect(model.notices.isEmpty)
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(model.activity.downloads.isEmpty)
  }

  @Test("시트를 연 사이 기기가 사라지거나 켜는 중이 되면 받지 않고 이유를 알린다")
  func deviceChangedWhileSheetOpen() async {
    let download = DownloadClientFake()
    let (model, simulator) = await Self.loadedModel(download: download)
    simulator.setInventory(Self.inventory(removing: SampleID.iPhoneOn))
    await model.refreshButtonTapped()

    await model.catalogInstallRequested(Self.request(SampleID.iPhoneOn))
    #expect(model.notices.map(\.notice) == [.installFailed(Self.label(SampleID.iPhoneOn), .simulator(.deviceNotFound))])

    simulator.setInventory(Self.inventory(SampleID.iPhoneOff, state: .booting))
    await model.refreshButtonTapped()
    await model.catalogInstallRequested(Self.request(SampleID.iPhoneOff))
    #expect(model.notices.map(\.notice).last == .installFailed(
      Self.label(SampleID.iPhoneOff),
      .deviceNotReady(.stateChanging)
    ))
    #expect(download.calls.isEmpty)
  }

  @Test("받기 실패는 카탈로그 출처로 알리고 풀지 않는다", arguments: [
    DownloadError.httpStatus(404), .hostNotFound, .insecureRedirect, .failed,
  ])
  func downloadFailureUsesCatalogOrigin(error: DownloadError) async {
    let appBundle = AppBundleClientFake()
    let download = Self.download(result: .failure(error))
    let (model, _) = await Self.loadedModel(appBundle: appBundle, download: download)

    await model.catalogInstallRequested(Self.request(SampleID.iPhoneOn))

    #expect(model.notices.map(\.notice) == [.installFailed(Self.label(SampleID.iPhoneOn), .catalogDownload(error))])
    #expect(appBundle.calls.isEmpty)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("URL 설치의 받기 실패는 여전히 입력한 주소 출처로 알린다")
  func urlInstallKeepsEnteredOrigin() async {
    let download = Self.download(result: .failure(.httpStatus(404)))
    let (model, _) = await Self.loadedModel(download: download)

    await LauncherURLInstallTests.installFromURL(model, on: SampleID.iPhoneOn)

    #expect(model.notices.map(\.notice) == [.installFailed(Self.label(SampleID.iPhoneOn), .download(.httpStatus(404)))])
  }

  @Test("받은 내용이 zip 이 아니면 카탈로그 출처로 웹 페이지인지 나눠 알리고, 받은 파일은 지운다", arguments: [
    ("text/html", true), (nil, false),
  ] as [(String?, Bool)])
  func downloadedNotZip(mimeType: String?, isWebPage: Bool) async {
    let appBundle = AppBundleClientFake()
    appBundle.setExtractError(.zipUnreadable)
    let file = DownloadedFile(file: Self.file.file, folder: Self.file.folder, byteCount: 2048, mimeType: mimeType)
    let download = Self.download(result: .success(file))
    let (model, _) = await Self.loadedModel(appBundle: appBundle, download: download)

    await model.catalogInstallRequested(Self.request(SampleID.iPhoneOn))

    #expect(
      model.notices.map(\.notice)
        == [.installFailed(Self.label(SampleID.iPhoneOn), .catalogDownloadedNotZip(isWebPage: isWebPage))]
    )
    #expect(download.calls == [.download(Self.url.url), .removeDownloaded(file)])
    #expect(appBundle.calls == [.extractApp(file.file)])
  }

  @Test("받은 zip 의 풀기 실패는 카탈로그 출처로 알린다")
  func downloadedZipFailure() async {
    let appBundle = AppBundleClientFake()
    appBundle.setExtractError(.zipWithoutApp)
    let download = DownloadClientFake()
    let (model, _) = await Self.loadedModel(appBundle: appBundle, download: download)

    await model.catalogInstallRequested(Self.request(SampleID.iPhoneOn))

    #expect(
      model.notices.map(\.notice) == [.installFailed(
        Self.label(SampleID.iPhoneOn),
        .catalogDownloadedZip(.zipWithoutApp)
      )]
    )
    #expect(download.calls == [.download(Self.url.url), .removeDownloaded(Self.file)])
  }

  @Test("받기·받은 파일 실패의 분류는 출처를 따른다 (입력한 주소 / 카탈로그 버전)")
  func failureClassificationByOrigin() {
    let errors: [DownloadError] = [.httpStatus(404), .offline, .cancelled]
    for error in errors {
      #expect(AppInstallFailure.download(error, from: .enteredURL) == .download(error))
      #expect(AppInstallFailure.download(error, from: .catalog) == .catalogDownload(error))
    }
    #expect(AppInstallFailure.downloaded(.zipUnreadable, mimeType: "text/html") == .downloadedNotZip(isWebPage: true))
    #expect(
      AppInstallFailure.downloaded(.zipUnreadable, mimeType: "TEXT/HTML", from: .catalog)
        == .catalogDownloadedNotZip(isWebPage: true)
    )
    #expect(
      AppInstallFailure.downloaded(.zipUnreadable, mimeType: "application/zip", from: .catalog)
        == .catalogDownloadedNotZip(isWebPage: false)
    )
    #expect(
      AppInstallFailure.downloaded(.zipWithMultipleApps, mimeType: "text/html", from: .catalog)
        == .catalogDownloadedZip(.zipWithMultipleApps)
    )
    #expect(
      AppInstallFailure.downloaded(.zipWithMultipleApps, mimeType: nil, from: .enteredURL)
        == .downloadedZip(.zipWithMultipleApps)
    )
  }

  @Test("받는 중 행의 받기 취소는 카탈로그 버전에서도 알림 없이 끝나고 풀지 않는다")
  func cancelWhileDownloading() async {
    let appBundle = AppBundleClientFake()
    let download = DownloadClientFake()
    download.suspendDownloads()
    let (model, _) = await Self.loadedModel(appBundle: appBundle, download: download)
    let id = SampleID.iPhoneOn
    let install = Self.start { await model.catalogInstallRequested(Self.request(id)) }
    await Self.waitUntil { download.suspendedDownloadCount == 1 }

    model.downloadCancelTapped(id)

    await Self.waitUntil { install.isFinished }
    download.resumeDownloads()
    await install.value()
    #expect(model.notices.isEmpty)
    #expect(download.calls == [.download(Self.url.url)])
    #expect(appBundle.calls.isEmpty)
    #expect(model.busyDeviceIDs.isEmpty)
  }
}
