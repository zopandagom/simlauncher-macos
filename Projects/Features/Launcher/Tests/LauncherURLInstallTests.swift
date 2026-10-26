import AppBundleInterface
import AppBundleTesting
import Core
import DownloadInterface
import DownloadTesting
import Foundation
import SimulatorInterface
import SimulatorTesting
import Testing
import WorkspaceTesting
@testable import LauncherFeature

@MainActor
struct LauncherURLInstallTests: LauncherModelTesting {
  static let raw = "https://example.com/MyApp.zip"
  static let url = DownloadURL(raw)!
  /// Fake 의 첫 받기 결과와 첫 풀기 결과.
  static let file = DownloadedFile.fake(index: 1)
  static let first = ExtractedApp.fake(index: 1)
  static let sample = AppBundleInfo.sample

  /// 시트를 열고 주소를 넣어 받아서 설치를 누른다.
  static func installFromURL(_ model: LauncherModel, on id: VirtualDevice.ID, text: String = Self.raw) async {
    model.installFromURLMenuTapped(id)
    model.installURLTextChanged(text)
    await model.installURLConfirmTapped()
  }

  /// 받은 결과를 바꾼 Fake. 진행 알림은 없다.
  static func download(result: Result<DownloadedFile, DownloadError>) -> DownloadClientFake {
    let download = DownloadClientFake()
    download.setDownloadScript(progress: [], result: result)
    return download
  }

  static func downloadedFile(mimeType: String?) -> DownloadedFile {
    DownloadedFile(file: self.file.file, folder: self.file.folder, byteCount: 2048, mimeType: mimeType)
  }

  // MARK: - 시트 열기·입력·닫기

  @Test("설치할 수 있는 기기(켜짐·꺼짐)에서 메뉴를 고르면 누른 시점의 기기로 빈 초안을 연다", arguments: [
    SampleID.iPhoneOn, SampleID.iPhoneOff,
  ])
  func menuOpensDraft(id: VirtualDevice.ID) async {
    let (model, _) = await Self.loadedModel()

    model.installFromURLMenuTapped(id)

    #expect(model.installURLDraft?.targets == [TargetDevice(id: id, label: Self.label(id))])
    #expect(model.installURLDraft?.text.isEmpty == true)
    #expect(model.installURLDraft?.problem == .empty)
    #expect(model.installURLDraft?.canSubmit == false)
  }

  @Test("쓸 수 없는·켜는 중·목록에 없는 기기, 작업 중인 기기, 목록을 읽기 전에는 시트를 열지 않는다")
  func menuIgnoresBlockedDevices() async {
    let (model, simulator) = await Self.loadedModel { $0.suspendBoots() }
    model.installFromURLMenuTapped(SampleID.unavailableIPhone)
    model.installFromURLMenuTapped(SampleID.watch)
    model.installFromURLMenuTapped(VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF"))
    #expect(model.installURLDraft == nil)

    let boot = Task { await model.bootButtonTapped(SampleID.iPadOff) }
    await Self.waitUntil { simulator.calls.contains(.boot(SampleID.iPadOff)) }
    model.installFromURLMenuTapped(SampleID.iPadOff)
    #expect(model.installURLDraft == nil)
    simulator.resumeBoots()
    await boot.value

    simulator.setInventory(Self.inventory(SampleID.iPhoneOff, state: .booting))
    await model.refreshButtonTapped()
    model.installFromURLMenuTapped(SampleID.iPhoneOff)
    #expect(model.installURLDraft == nil)

    let beforeLoad = LauncherModel(
      simulator: SimulatorClientFake(inventory: .sample),
      appBundle: AppBundleClientFake(),
      download: DownloadClientFake(),
      workspace: WorkspaceClientFake()
    )
    beforeLoad.installFromURLMenuTapped(SampleID.iPhoneOn)
    #expect(beforeLoad.installURLDraft == nil)
  }

  @Test("다른 시트나 확인 대화상자가 열려 있으면 URL 설치 시트를 열지 않는다")
  func menuIgnoredWhileOtherSheetIsOpen() async {
    let (model, _) = await Self.loadedModel()

    model.openURLButtonTapped(SampleID.iPhoneOn)
    model.installFromURLMenuTapped(SampleID.iPhoneOff)
    #expect(model.installURLDraft == nil)
    model.openURLCancelTapped()

    model.createButtonTapped()
    model.installFromURLMenuTapped(SampleID.iPhoneOff)
    #expect(model.installURLDraft == nil)
    model.createCancelTapped()

    model.deleteButtonTapped(SampleID.iPhoneOff)
    model.installFromURLMenuTapped(SampleID.iPhoneOff)
    #expect(model.installURLDraft == nil)
    model.confirmationDismissed()

    model.installFromURLMenuTapped(SampleID.iPhoneOff)
    model.installFromURLMenuTapped(SampleID.iPhoneOn)
    #expect(model.installURLDraft?.targets.map(\.id) == [SampleID.iPhoneOff])
  }

  @Test("URL 설치 시트가 열려 있으면 + 버튼·삭제·초기화 확인·링크 시트가 열리지 않는다")
  func otherSheetsIgnoredWhileInstallURLSheetIsOpen() async {
    let (model, _) = await Self.loadedModel()
    #expect(model.canCreateDevice)

    model.installFromURLMenuTapped(SampleID.iPhoneOn)

    #expect(!model.canCreateDevice)
    model.createButtonTapped()
    #expect(model.createDraft == nil)
    model.deleteButtonTapped(SampleID.iPhoneOff)
    model.eraseButtonTapped(SampleID.iPhoneOff)
    #expect(model.pendingConfirmation == nil)
    model.openURLButtonTapped(SampleID.iPhoneOff)
    #expect(model.openURLDraft == nil)

    model.installURLSheetDismissed()
    #expect(model.canCreateDevice)
  }

  @Test("입력하면 초안의 주소·문제가 바뀌고, 취소·닫기는 초안을 지운다")
  func textChangeCancelAndDismiss() async {
    let (model, _) = await Self.loadedModel()
    model.installFromURLMenuTapped(SampleID.iPhoneOn)

    model.installURLTextChanged("http://example.com/MyApp.zip")
    #expect(model.installURLDraft?.problem == .notHTTPS)
    #expect(model.installURLDraft?.canSubmit == false)

    model.installURLTextChanged("  \(Self.raw)  ")
    #expect(model.installURLDraft?.text == "  \(Self.raw)  ")
    #expect(model.installURLDraft?.problem == nil)
    #expect(model.installURLDraft?.url == Self.url)
    #expect(model.installURLDraft?.canSubmit == true)

    model.installURLCancelTapped()
    #expect(model.installURLDraft == nil)
    model.installURLTextChanged(Self.raw)
    #expect(model.installURLDraft == nil)

    model.installFromURLMenuTapped(SampleID.iPhoneOn)
    model.installURLSheetDismissed()
    #expect(model.installURLDraft == nil)
  }

  @Test("주소에 문제가 있으면 받아서 설치를 눌러도 시트와 입력을 그대로 두고 받지 않는다")
  func confirmWithInvalidURLKeepsSheet() async {
    let download = DownloadClientFake()
    let (model, _) = await Self.loadedModel(download: download)
    model.installFromURLMenuTapped(SampleID.iPhoneOn)
    model.installURLTextChanged("https://user:pw@example.com/a.zip")

    await model.installURLConfirmTapped()

    #expect(model.installURLDraft?.text == "https://user:pw@example.com/a.zip")
    #expect(download.calls.isEmpty)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  // MARK: - 성공 흐름

  @Test("받기 → 풀기 → 받은 파일 지우기 → 검사 → 설치 → 실행 → 다시 읽기 → 푼 폴더 정리이고, 시트가 닫히고 알림이 없다")
  func installFromURLOnBootedDevice() async {
    let appBundle = AppBundleClientFake()
    let download = DownloadClientFake()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle, download: download)

    await Self.installFromURL(model, on: SampleID.iPhoneOn)

    #expect(model.installURLDraft == nil)
    #expect(download.calls == [.download(Self.url.url), .removeDownloaded(Self.file)])
    #expect(appBundle.calls == [.extractApp(Self.file.file), .inspect(Self.first.app), .removeExtracted(Self.first)])
    #expect(simulator.calls == [
      .fetchInventory,
      .openSimulatorApp,
      .install(Self.sample.location, SampleID.iPhoneOn),
      .launch(Self.sample.bundleID, SampleID.iPhoneOn),
      .fetchInventory,
    ])
    #expect(model.notices.isEmpty)
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(model.activity.downloads.isEmpty)
  }

  @Test("꺼진 기기면 받아서 푼 뒤 켜고 설치한다")
  func installFromURLOnShutdownDevice() async {
    let (model, simulator) = await Self.loadedModel()

    await Self.installFromURL(model, on: SampleID.iPhoneOff)

    #expect(simulator.calls.suffix(5) == [
      .boot(SampleID.iPhoneOff),
      .openSimulatorApp,
      .install(Self.sample.location, SampleID.iPhoneOff),
      .launch(Self.sample.bundleID, SampleID.iPhoneOff),
      .fetchInventory,
    ])
    #expect(model.notices.isEmpty)
  }

  @Test("받은 파일은 풀기 직후, 푼 .app 을 검사하기 전에 지운다")
  func downloadedFileIsRemovedBeforeInspection() async {
    let appBundle = AppBundleClientFake()
    appBundle.suspendInspections()
    let download = DownloadClientFake()
    let (model, _) = await Self.loadedModel(appBundle: appBundle, download: download)
    let install = Task { await Self.installFromURL(model, on: SampleID.iPhoneOn) }
    await Self.waitUntil { appBundle.calls.count == 2 }

    #expect(appBundle.calls == [.extractApp(Self.file.file), .inspect(Self.first.app)])
    #expect(download.calls == [.download(Self.url.url), .removeDownloaded(Self.file)])
    // 받기가 끝나 받기 단계는 없고, 설치 작업만 남아 있다.
    #expect(model.activity.downloadStage(on: SampleID.iPhoneOn) == nil)
    #expect(model.activity.task(on: SampleID.iPhoneOn) == .installApp)

    appBundle.resumeInspections()
    await install.value
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("받는 동안 행의 받기 단계가 응답 전 → 진행 값으로 바뀐다")
  func progressUpdatesStage() async {
    let download = DownloadClientFake()
    download.setDownloadScript(progress: [], result: nil)
    download.suspendDownloads()
    let (model, _) = await Self.loadedModel(download: download)
    let id = SampleID.iPhoneOn
    let install = Task { await Self.installFromURL(model, on: id) }
    await Self.waitUntil { download.suspendedDownloadCount == 1 }
    #expect(model.activity.downloadStage(on: id) == .receiving(nil))
    #expect(model.activity.task(on: id) == .installApp)

    let progress = DownloadProgress(receivedBytes: 512, expectedBytes: 1024)
    await download.sendDownloadProgress(progress)
    #expect(model.activity.downloadStage(on: id) == .receiving(progress))
    let unknown = DownloadProgress(receivedBytes: 4096, expectedBytes: nil)
    await download.sendDownloadProgress(unknown)
    #expect(model.activity.downloadStage(on: id) == .receiving(unknown))

    download.resumeDownloads()
    await install.value
    #expect(model.activity.downloadStage(on: id) == nil)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("연타해도 한 번만 받는다 (시트를 첫 호출에서 닫는다)")
  func doubleConfirmDownloadsOnce() async {
    let download = DownloadClientFake()
    let (model, _) = await Self.loadedModel(download: download)
    model.installFromURLMenuTapped(SampleID.iPhoneOn)
    model.installURLTextChanged(Self.raw)

    async let first: Void = model.installURLConfirmTapped()
    async let second: Void = model.installURLConfirmTapped()
    _ = await (first, second)

    #expect(download.calls == [.download(Self.url.url), .removeDownloaded(Self.file)])
  }
}
