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
struct LauncherURLInstallTargetTests: LauncherModelTesting {
  static let raw = LauncherURLInstallTests.raw
  static let url = LauncherURLInstallTests.url
  static let file = LauncherURLInstallTests.file
  static let first = LauncherURLInstallTests.first
  static let sample = LauncherURLInstallTests.sample

  static func installFromURL(_ model: LauncherModel, on id: VirtualDevice.ID) async {
    await LauncherURLInstallTests.installFromURL(model, on: id)
  }

  // MARK: - 대상 기기 다시 확인

  @Test("시트를 연 사이 기기가 목록에서 사라지면 받지 않고 기기를 찾지 못했다고 알린다")
  func deviceRemovedWhileSheetOpen() async {
    let download = DownloadClientFake()
    let (model, simulator) = await Self.loadedModel(download: download)
    model.installFromURLMenuTapped(SampleID.iPhoneOn)
    model.installURLTextChanged(Self.raw)
    simulator.setInventory(Self.inventory(removing: SampleID.iPhoneOn))
    await model.refreshButtonTapped()

    await model.installURLConfirmTapped()

    #expect(model.notices.map(\.notice) == [.installFailed(Self.label(SampleID.iPhoneOn), .simulator(.deviceNotFound))])
    #expect(download.calls.isEmpty)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("시트를 연 사이 기기가 켜는 중이 되면 받지 않고 설치할 수 없는 이유를 알린다")
  func deviceBootingWhileSheetOpen() async {
    let download = DownloadClientFake()
    let (model, simulator) = await Self.loadedModel(download: download)
    model.installFromURLMenuTapped(SampleID.iPhoneOff)
    model.installURLTextChanged(Self.raw)
    simulator.setInventory(Self.inventory(SampleID.iPhoneOff, state: .booting))
    await model.refreshButtonTapped()

    await model.installURLConfirmTapped()

    #expect(
      model.notices.map(\.notice) == [.installFailed(Self.label(SampleID.iPhoneOff), .deviceNotReady(.stateChanging))]
    )
    #expect(download.calls.isEmpty)
  }

  @Test("시트를 연 사이 같은 기기에서 다른 작업이 시작됐으면 조용히 끝난다 (행의 진행 표시가 이유)")
  func sameDeviceBusyWhenConfirmed() async {
    let download = DownloadClientFake()
    let (model, simulator) = await Self.loadedModel(download: download) { $0.suspendBoots() }
    model.installFromURLMenuTapped(SampleID.iPhoneOff)
    model.installURLTextChanged(Self.raw)
    let boot = Task { await model.bootButtonTapped(SampleID.iPhoneOff) }
    await Self.waitUntil { simulator.calls.contains(.boot(SampleID.iPhoneOff)) }

    await model.installURLConfirmTapped()

    #expect(download.calls.isEmpty)
    #expect(model.notices.isEmpty)
    #expect(model.activity.task(on: SampleID.iPhoneOff) == .boot)
    simulator.resumeBoots()
    await boot.value
  }

  @Test("받는 동안 기기가 목록에서 사라지면 풀지 않고 받은 파일을 지운 뒤 기기를 찾지 못했다고 알린다")
  func deviceRemovedWhileDownloading() async {
    let appBundle = AppBundleClientFake()
    let download = DownloadClientFake()
    download.suspendDownloads()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle, download: download)
    let install = Task { await Self.installFromURL(model, on: SampleID.iPhoneOn) }
    await Self.waitUntil { download.suspendedDownloadCount == 1 }
    simulator.setInventory(Self.inventory(removing: SampleID.iPhoneOn))
    await model.refreshButtonTapped()
    #expect(model.activity.downloadStage(on: SampleID.iPhoneOn) != nil)

    download.resumeDownloads()
    await install.value

    #expect(download.calls == [.download(Self.url.url), .removeDownloaded(Self.file)])
    #expect(appBundle.calls.isEmpty)
    #expect(model.notices.map(\.notice) == [.installFailed(Self.label(SampleID.iPhoneOn), .simulator(.deviceNotFound))])
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(model.activity.downloads.isEmpty)
  }

  @Test("받는 동안 기기가 켜는 중이 되면 받은 뒤 풀고 받은 파일을 지운 다음, 검사 뒤 설치할 수 없는 이유를 알린다")
  func deviceBootingWhileDownloading() async {
    let appBundle = AppBundleClientFake()
    let download = DownloadClientFake()
    download.suspendDownloads()
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle, download: download)
    let install = Task { await Self.installFromURL(model, on: SampleID.iPhoneOff) }
    await Self.waitUntil { download.suspendedDownloadCount == 1 }
    simulator.setInventory(Self.inventory(SampleID.iPhoneOff, state: .booting))
    await model.refreshButtonTapped()

    download.resumeDownloads()
    await install.value

    #expect(download.calls == [.download(Self.url.url), .removeDownloaded(Self.file)])
    #expect(appBundle.calls == [.extractApp(Self.file.file), .inspect(Self.first.app), .removeExtracted(Self.first)])
    #expect(
      model.notices.map(\.notice) == [.installFailed(Self.label(SampleID.iPhoneOff), .deviceNotReady(.stateChanging))]
    )
    #expect(!simulator.calls.contains(.install(Self.sample.location, SampleID.iPhoneOff)))
  }
}

@MainActor
struct LauncherURLInstallFailureTests: LauncherModelTesting {
  static let url = LauncherURLInstallTests.url
  static let file = LauncherURLInstallTests.file
  static let first = LauncherURLInstallTests.first
  static let sample = LauncherURLInstallTests.sample

  static func installFromURL(_ model: LauncherModel, on id: VirtualDevice.ID) async {
    await LauncherURLInstallTests.installFromURL(model, on: id)
  }

  static func download(result: Result<DownloadedFile, DownloadError>) -> DownloadClientFake {
    LauncherURLInstallTests.download(result: result)
  }

  static func downloadedFile(mimeType: String?) -> DownloadedFile {
    LauncherURLInstallTests.downloadedFile(mimeType: mimeType)
  }

  // MARK: - 받기 실패

  @Test("받기가 실패하면 그 이유를 알리고, 풀기·받은 파일 지우기·시뮬레이터 명령이 없으며 다시 읽지 않는다", arguments: [
    DownloadError.insecureRedirect, .httpStatus(404), .httpStatus(401), .httpStatus(407), .httpStatus(503), .offline,
    .hostNotFound, .cannotConnect, .timedOut, .connectionLost, .secureConnectionFailed, .insufficientDiskSpace,
    .storageUnavailable, .tooLarge, .failed,
  ])
  func downloadFailure(error: DownloadError) async {
    let appBundle = AppBundleClientFake()
    let download = Self.download(result: .failure(error))
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle, download: download)

    await Self.installFromURL(model, on: SampleID.iPhoneOn)

    #expect(model.notices.map(\.notice) == [.installFailed(Self.label(SampleID.iPhoneOn), .download(error))])
    #expect(download.calls == [.download(Self.url.url)])
    #expect(appBundle.calls.isEmpty)
    #expect(simulator.calls == [.fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
    #expect(model.activity.downloads.isEmpty)
  }

  @Test("취소를 누르지 않았는데 받기가 .cancelled 로 끝나면 이유 없이 끝나지 않게 알린다")
  func cancelledWithoutRequestIsReported() async {
    let appBundle = AppBundleClientFake()
    let download = Self.download(result: .failure(.cancelled))
    let (model, _) = await Self.loadedModel(appBundle: appBundle, download: download)

    await Self.installFromURL(model, on: SampleID.iPhoneOn)

    #expect(model.notices.map(\.notice) == [.installFailed(Self.label(SampleID.iPhoneOn), .download(.cancelled))])
    #expect(download.calls == [.download(Self.url.url)])
    #expect(appBundle.calls.isEmpty)
    #expect(model.busyDeviceIDs.isEmpty)
  }

  // MARK: - 받은 파일 풀기 실패

  @Test(
    "받은 내용이 zip 으로 읽히지 않으면 응답 형식으로 웹 페이지인지 나눠 알리고, 받은 파일은 지우며 검사하지 않는다",
    arguments: [
      ("text/html", true), ("TEXT/HTML", true), ("application/xhtml+xml", true),
      ("application/octet-stream", false), ("text/plain", false), (nil, false),
    ] as [(String?, Bool)]
  )
  func downloadedNotZip(mimeType: String?, isWebPage: Bool) async {
    let appBundle = AppBundleClientFake()
    appBundle.setExtractError(.zipUnreadable)
    let file = Self.downloadedFile(mimeType: mimeType)
    let download = Self.download(result: .success(file))
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle, download: download)

    await Self.installFromURL(model, on: SampleID.iPhoneOn)

    #expect(
      model.notices.map(\.notice)
        == [.installFailed(Self.label(SampleID.iPhoneOn), .downloadedNotZip(isWebPage: isWebPage))]
    )
    #expect(download.calls == [.download(Self.url.url), .removeDownloaded(file)])
    #expect(appBundle.calls == [.extractApp(file.file)])
    #expect(simulator.calls == [.fetchInventory])
    #expect(model.busyDeviceIDs.isEmpty)
  }

  @Test("받은 zip 의 그 밖의 풀기 실패는 받은 파일 문맥으로 알리고, 받은 파일은 지우며 검사하지 않는다", arguments: [
    AppBundleError.zipWithoutApp, .zipWithMultipleApps, .zipUnsafeEntry, .insufficientDiskSpace,
    .extractionUnavailable,
  ])
  func downloadedZipExtractFailure(error: AppBundleError) async {
    let appBundle = AppBundleClientFake()
    appBundle.setExtractError(error)
    let download = DownloadClientFake()
    let (model, _) = await Self.loadedModel(appBundle: appBundle, download: download)

    await Self.installFromURL(model, on: SampleID.iPhoneOn)

    #expect(model.notices.map(\.notice) == [.installFailed(Self.label(SampleID.iPhoneOn), .downloadedZip(error))])
    #expect(download.calls == [.download(Self.url.url), .removeDownloaded(Self.file)])
    #expect(appBundle.calls == [.extractApp(Self.file.file)])
  }

  @Test("받은 zip 은 응답 형식이 웹 페이지여도 zip 으로 읽히면 설치한다")
  func zipServedAsHTMLInstalls() async {
    let appBundle = AppBundleClientFake()
    let file = Self.downloadedFile(mimeType: "text/html")
    let download = Self.download(result: .success(file))
    let (model, simulator) = await Self.loadedModel(appBundle: appBundle, download: download)

    await Self.installFromURL(model, on: SampleID.iPhoneOn)

    #expect(model.notices.isEmpty)
    #expect(simulator.calls.contains(.install(Self.sample.location, SampleID.iPhoneOn)))
    #expect(download.calls == [.download(Self.url.url), .removeDownloaded(file)])
  }

  @Test("푼 .app 의 검사 실패는 고른 파일과 같은 알림이고, 푼 폴더도 지운다")
  func inspectFailureAfterDownload() async {
    let appBundle = AppBundleClientFake()
    appBundle.setInspectError(.macOSApp)
    let download = DownloadClientFake()
    let (model, _) = await Self.loadedModel(appBundle: appBundle, download: download)

    await Self.installFromURL(model, on: SampleID.iPhoneOn)

    #expect(model.notices.map(\.notice) == [.installFailed(Self.label(SampleID.iPhoneOn), .bundle(.macOSApp))])
    #expect(appBundle.calls == [.extractApp(Self.file.file), .inspect(Self.first.app), .removeExtracted(Self.first)])
    #expect(download.calls == [.download(Self.url.url), .removeDownloaded(Self.file)])
  }
}

// MARK: - 순수 규칙

struct LauncherURLInstallRuleTests {
  @Test("받은 파일의 풀기 실패: zip 으로 읽히지 않으면 웹 페이지 형식(대소문자 무시)인지로 나누고, 그 밖은 받은 zip 실패다")
  func downloadedFailureClassification() {
    #expect(AppInstallFailure.downloaded(.zipUnreadable, mimeType: "text/html") == .downloadedNotZip(isWebPage: true))
    #expect(AppInstallFailure.downloaded(.zipUnreadable, mimeType: "Text/HTML") == .downloadedNotZip(isWebPage: true))
    #expect(
      AppInstallFailure.downloaded(.zipUnreadable, mimeType: "application/xhtml+xml")
        == .downloadedNotZip(isWebPage: true)
    )
    for mimeType in ["application/octet-stream", "application/zip", "text/plain", "", nil] as [String?] {
      #expect(AppInstallFailure.downloaded(.zipUnreadable, mimeType: mimeType) == .downloadedNotZip(isWebPage: false))
    }
    let errors: [AppBundleError] = [
      .zipWithoutApp, .zipWithMultipleApps, .zipUnsafeEntry, .insufficientDiskSpace, .extractionUnavailable,
      .notLocalFile, .fileNotFound,
    ]
    for error in errors {
      #expect(AppInstallFailure.downloaded(error, mimeType: "text/html") == .downloadedZip(error), "\(error)")
    }
  }

  @Test("대상 기기 확인: 목록 없음·기기 없음·설치할 수 없는 상태·준비됨과 흐름별 실패 원인")
  func appInstallTarget() throws {
    let list = DeviceList(inventory: .sample)
    let ready = AppInstallTarget.current(SampleID.iPhoneOn, in: .loaded(list))
    #expect(try ready == .ready(#require(list.device(id: SampleID.iPhoneOn))))
    #expect(ready.installFailure == nil)
    #expect(ready.openURLFailure == nil)

    let notLoaded = AppInstallTarget.current(SampleID.iPhoneOn, in: .loading)
    #expect(notLoaded == .notLoaded)
    #expect(AppInstallTarget.current(SampleID.iPhoneOn, in: .failed(.commandFailed)) == .notLoaded)
    #expect(notLoaded.installFailure == .simulator(.deviceNotFound))
    #expect(notLoaded.openURLFailure == nil)

    let notFound = AppInstallTarget.current(VirtualDevice.ID("00000000-0000-0000-0000-0000000000FF"), in: .loaded(list))
    #expect(notFound == .notFound)
    #expect(notFound.installFailure == .simulator(.deviceNotFound))
    #expect(notFound.openURLFailure == .simulator(.deviceNotFound))

    let blocked = AppInstallTarget.current(SampleID.unavailableIPhone, in: .loaded(list))
    #expect(blocked == .blocked(.unavailable))
    #expect(blocked.installFailure == .deviceNotReady(.unavailable))
    #expect(blocked.openURLFailure == .deviceNotReady(.unavailable))
  }

  @Test("zip 판정은 확장자만 본다 (대소문자 무시)")
  func zipSource() {
    #expect(AppInstallSource.isZip(URL(filePath: "/a/b.zip")))
    #expect(AppInstallSource.isZip(URL(filePath: "/a/B.ZIP")))
    #expect(!AppInstallSource.isZip(URL(filePath: "/a/b.zip.app", directoryHint: .isDirectory)))
  }
}

// MARK: - 문구

struct LauncherDownloadTextTests {
  @Test("HTTP 상태는 로그인(401·403)·프록시(407)·없음(404·410)·서버 오류(5xx)·그 밖으로 나눠 코드를 함께 보인다")
  func httpStatusMessages() {
    for code in [401, 403] {
      #expect(LauncherText.httpStatusMessage(code).contains("로그인이나 접근 권한"))
      #expect(LauncherText.httpStatusMessage(code).contains("(HTTP \(code))"))
    }
    #expect(LauncherText.httpStatusMessage(407).contains("프록시가 인증을 요구"))
    for code in [404, 410] {
      #expect(LauncherText.httpStatusMessage(code).contains("서버에 파일이 없습니다 (HTTP \(code))"))
    }
    for code in [500, 503, 599] {
      #expect(LauncherText.httpStatusMessage(code).contains("서버 오류로 받지 못했습니다 (HTTP \(code))"))
    }
    for code in [400, 402, 408, 429, 600, 302] {
      #expect(LauncherText.httpStatusMessage(code).contains("서버가 파일을 주지 않았습니다 (HTTP \(code))"))
    }
    #expect(LauncherText.message(for: DownloadError.httpStatus(404)) == LauncherText.httpStatusMessage(404))
  }

  @Test("설치 실패 본문: 받기 실패는 받기 문구, 받은 파일 실패는 받은 파일 문구이고 웹 페이지면 로그인 페이지를 안내한다")
  func installFailureMessages() {
    #expect(LauncherText.message(for: AppInstallFailure.download(.offline)) == LauncherText.message(for: .offline))
    #expect(
      LauncherText.message(for: AppInstallFailure.downloadedNotZip(isWebPage: true)).contains("로그인이 필요한 주소")
    )
    #expect(
      !LauncherText.message(for: AppInstallFailure.downloadedNotZip(isWebPage: false)).contains("로그인이 필요한 주소")
    )
    #expect(LauncherText.message(for: AppInstallFailure.downloadedZip(.zipWithoutApp)).hasPrefix("받은 zip"))
    #expect(
      LauncherText.message(for: AppInstallFailure.downloadedZip(.zipUnreadable))
        == LauncherText.downloadedNotZipMessage(isWebPage: false)
    )
    #expect(
      LauncherText.message(for: AppInstallFailure.downloadedZip(.zipUnsafeEntry))
        == LauncherText.message(for: AppBundleError.zipUnsafeEntry)
    )
    // 받은 파일 실패 문구는 주소를 다시 입력하라고 하고, 파일을 고르라고 하지 않는다.
    for error in [AppBundleError.zipWithoutApp, .zipWithMultipleApps] {
      #expect(!LauncherText.downloadedZipMessage(for: error).contains("골라"))
    }
  }

  @Test("받는 중 글자는 전체 크기를 알 때(0 보다 클 때)만 전체를 함께 보인다")
  func downloadingLabel() {
    #expect(LauncherText.downloadingLabel(nil) == "받는 중…")
    let received = Int64(512).formatted(.byteCount(style: .file))
    let total = Int64(1024).formatted(.byteCount(style: .file))
    #expect(
      LauncherText.downloadingLabel(DownloadProgress(receivedBytes: 512, expectedBytes: 1024))
        == "받는 중… \(received) / \(total)"
    )
    #expect(LauncherText
      .downloadingLabel(DownloadProgress(receivedBytes: 512, expectedBytes: nil)) == "받는 중… \(received)")
    #expect(LauncherText
      .downloadingLabel(DownloadProgress(receivedBytes: 512, expectedBytes: 0)) == "받는 중… \(received)")
  }

  @Test("주소 입력 문제: 비어 있으면 문구가 없고, 나머지는 고칠 입력을 안내한다")
  func downloadURLProblemTexts() {
    #expect(LauncherText.downloadURLProblem(.empty) == nil)
    #expect(LauncherText.downloadURLProblem(.notHTTPS)?.contains("https://") == true)
    #expect(LauncherText.downloadURLProblem(.missingHost)?.contains("서버 주소") == true)
    #expect(LauncherText.downloadURLProblem(.hasCredentials)?.contains("로그인 없이") == true)
    #expect(LauncherText.downloadURLProblem(.malformed)?.contains("주소로 읽을 수 없습니다") == true)
  }

  @Test("웹 주소를 끌어다 놓으면 URL 에서… 메뉴를 안내한다")
  func notLocalFilePointsToURLMenu() {
    #expect(LauncherText.message(for: AppBundleError.notLocalFile).contains("“URL 에서…”"))
  }
}
