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

/// 켜진 기기 행의 URL·카탈로그에서 설치 (`downloadInstallRequested`): 대상 확인 → 받기(행에 진행·취소) → 검사 → 기기 값 →
/// 판정 → 설치 → 받은 파일 지우기 → 실행 → 다시 읽기.
@MainActor
struct AndroidDevicesDownloadTests: AndroidDevicesTesting {
  static let tablet = AndroidVirtualDevice.bootedTabletSample
  static let label = AndroidDeviceLabel(.bootedTabletSample)
  static let url = DownloadURL("https://builds.example.com/Sample-42.apk")!
  /// Fake 의 첫 받기 결과 (`.apk` 이름).
  static let file = DownloadedFile.fake(index: 1, name: .apk)
  static let info = AndroidPackageInfo.sample()

  static func request(
    _ device: AndroidVirtualDevice = .bootedTabletSample,
    origin: AndroidDownloadOrigin = .enteredURL
  ) -> AndroidDownloadInstallRequest {
    AndroidDownloadInstallRequest(
      deviceID: device.id,
      device: AndroidDeviceLabel(device),
      url: self.url,
      origin: origin
    )
  }

  /// 기기 목록 읽기 밖의 Client 호출.
  static func appCalls(_ fake: AndroidEmulatorClientFake) -> [AndroidEmulatorClientFake.Call] {
    fake.calls.filter { $0 != .fetchDevices }
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

  // MARK: - 성공·진행

  @Test("성공: .apk 이름으로 받고, 받은 파일을 검사·설치·실행한 뒤 다시 읽고, 받은 파일을 한 번 지운다")
  func installSucceeds() async {
    let setup = await Self.loadedFixture()
    await setup.model.downloadInstallRequested(Self.request())
    #expect(setup.download.downloadRequests == [.init(url: Self.url, name: .apk)])
    #expect(setup.package.calls == [Self.file.file])
    #expect(Self.appCalls(setup.fake) == [
      .deviceTraits(Self.tablet.id),
      .install(Self.info.location, Self.tablet.id),
      .launch(Self.info.packageName, Self.tablet.id),
    ])
    #expect(Self.removals(setup.download) == [Self.file])
    #expect(Self.fetchCount(setup.fake) == 2)
    #expect(setup.model.activity.task(on: Self.tablet.id) == nil)
    #expect(setup.model.activity.downloadStage(on: Self.tablet.id) == nil)
    #expect(setup.model.notices.isEmpty)
  }

  @Test("설치 명령이 끝나기 전에는 지우지 않고, 끝나면 곧바로 지운다")
  func removesRightAfterInstallCommand() async {
    let setup = await Self.loadedFixture { $0.suspendInstalls() }
    let task = Self.start { await setup.model.downloadInstallRequested(Self.request()) }
    await Self.waitUntil { Self.appCalls(setup.fake).count == 2 }
    #expect(Self.removals(setup.download).isEmpty)
    #expect(setup.model.activity.task(on: Self.tablet.id) == .installApp)
    #expect(setup.model.activity.downloadStage(on: Self.tablet.id) == nil)
    setup.fake.resumeInstalls()
    await task.value()
    #expect(Self.removals(setup.download) == [Self.file])
  }

  @Test("받는 동안 받기 단계는 응답 전 nil, 진행이 오면 그 값이고, 작업은 설치다")
  func progressIsReflected() async {
    let setup = await Self.loadedFixture()
    setup.download.setDownloadScript(progress: [], result: nil)
    setup.download.suspendDownloads()
    let task = Self.start { await setup.model.downloadInstallRequested(Self.request()) }
    await Self.waitUntil { setup.download.suspendedDownloadCount == 1 }
    #expect(setup.model.activity.task(on: Self.tablet.id) == .installApp)
    #expect(setup.model.activity.downloadStage(on: Self.tablet.id) == .receiving(nil))
    let progress = DownloadProgress(receivedBytes: 512, expectedBytes: 1024)
    await setup.download.sendDownloadProgress(progress)
    #expect(setup.model.activity.downloadStage(on: Self.tablet.id) == .receiving(progress))
    setup.download.resumeDownloads()
    await task.value()
    #expect(setup.model.activity.downloadStage(on: Self.tablet.id) == nil)
    #expect(setup.model.notices.isEmpty)
  }

  @Test("onAppear 는 목록을 읽은 뒤 남은 받기 폴더를 지운다")
  func onAppearRemovesLeftovers() async {
    let setup = Self.fixture()
    #expect(setup.download.leftoverCleanupCount == 0)
    await setup.model.onAppear()
    #expect(setup.download.leftoverCleanupCount == 1)
    #expect(Self.fetchCount(setup.fake) == 1)
  }

  // MARK: - 취소

  @Test("받는 중 취소: 취소 중으로 바뀌고, 받기가 멈추면 알림 없이 끝나며 다시 읽지 않는다")
  func cancelWhileReceiving() async {
    let setup = await Self.loadedFixture()
    setup.download.suspendDownloads()
    let task = Self.start { await setup.model.downloadInstallRequested(Self.request()) }
    await Self.waitUntil { setup.download.suspendedDownloadCount == 1 }
    setup.model.downloadCancelTapped(Self.tablet.id)
    #expect(setup.model.activity.downloadStage(on: Self.tablet.id) == .cancelling)
    await task.value()
    #expect(setup.model.notices.isEmpty)
    #expect(setup.package.calls.isEmpty)
    #expect(Self.removals(setup.download).isEmpty)
    #expect(Self.appCalls(setup.fake).isEmpty)
    #expect(Self.fetchCount(setup.fake) == 1)
    #expect(setup.model.activity.task(on: Self.tablet.id) == nil)
  }

  @Test("받기가 끝난 뒤(검사 중) 취소는 아무 일도 하지 않고 설치가 이어진다. 받지 않는 기기의 취소도 무시한다")
  func cancelAfterDownloadIsIgnored() async {
    let setup = await Self.loadedFixture()
    setup.package.suspend()
    let task = Self.start { await setup.model.downloadInstallRequested(Self.request()) }
    await Self.waitUntil { setup.package.calls.count == 1 }
    setup.model.downloadCancelTapped(Self.tablet.id)
    setup.model.downloadCancelTapped(AndroidVirtualDevice.phoneSample.id)
    #expect(setup.model.activity.downloadStage(on: Self.tablet.id) == nil)
    setup.package.resume()
    await task.value()
    #expect(Self.appCalls(setup.fake).count == 3)
    #expect(Self.removals(setup.download) == [Self.file])
    #expect(setup.model.notices.isEmpty)
  }

  @Test("막 끝난 성공 뒤 취소가 이기면 받은 파일을 지우고 알림·검사·다시 읽기 없이 끝난다 (흐름)")
  func lateCancelAfterSuccessRemovesFile() async {
    let setup = await Self.loadedFixture()
    let flow = AndroidAppInstallFlow(emulator: setup.fake, package: setup.package, download: setup.download)
    let enqueued = Counter()
    let reloads = Counter()
    let host = AndroidAppInstallFlow.Host(
      enqueue: { _ in enqueued.increment() },
      reload: { reloads.increment() },
      listState: { setup.model.listState },
      finished: { _, _ in }
    )
    await flow.installDownloaded(.success(Self.file), cancelRequested: true, request: Self.request(), host: host)
    #expect(Self.removals(setup.download) == [Self.file])
    #expect(enqueued.value == 0)
    #expect(reloads.value == 0)
    #expect(setup.package.calls.isEmpty)
    await flow.installDownloaded(.failure(.cancelled), cancelRequested: true, request: Self.request(), host: host)
    #expect(Self.removals(setup.download) == [Self.file])
    #expect(enqueued.value == 0)
  }

  // MARK: - 시작할 때의 대상

  @Test("시트를 연 사이 목록에서 사라진 기기: 요청의 라벨로 알리고 받지 않는다")
  func requestForMissingDevice() async {
    let setup = await Self.loadedFixture()
    let gone = AndroidVirtualDevice.secondPhoneSample.with(state: .booted)
    await setup.model.downloadInstallRequested(Self.request(gone))
    #expect(Self.notices(setup.model) == [
      .installFailed(AndroidDeviceLabel(gone), .emulator(.deviceNotFound)),
    ])
    #expect(setup.download.calls.isEmpty)
  }

  @Test("켜짐이 아니거나 쓸 수 없는 기기: 이유를 알리고 받지 않는다")
  func requestForBlockedDevice() async {
    let setup = await Self.loadedFixture()
    await setup.model.downloadInstallRequested(Self.request(.phoneSample))
    await setup.model.downloadInstallRequested(Self.request(.unsupportedNameSample))
    #expect(Self.notices(setup.model) == [
      .installFailed(AndroidDeviceLabel(.phoneSample), .deviceNotReady(.notBooted)),
      .installFailed(AndroidDeviceLabel(.unsupportedNameSample), .deviceNotReady(.unavailable)),
    ])
    #expect(setup.download.calls.isEmpty)
  }

  @Test("같은 기기가 다른 작업 중이면 알림 없이 끝나고 받지 않는다")
  func requestWhileBusy() async {
    let setup = await Self.loadedFixture()
    setup.package.suspend()
    let local = Self.start {
      await setup.model.appFileSelected(URL(filePath: "/tmp/app.apk"), for: Self.tablet.id)
    }
    await Self.waitUntil { setup.package.calls.count == 1 }
    await setup.model.downloadInstallRequested(Self.request())
    #expect(setup.download.calls.isEmpty)
    #expect(setup.model.notices.isEmpty)
    setup.package.resume()
    await local.value()
  }

  // MARK: - 받는 동안·받은 뒤 바뀐 기기

  @Test(
    "받는 동안 기기가 꺼지거나 사라지면 검사 뒤 대상 확인에서 알리고, 받은 파일을 지우고 설치하지 않는다",
    arguments: [false, true]
  )
  func deviceChangedWhileDownloading(removed: Bool) async {
    let setup = await Self.loadedFixture()
    setup.download.suspendDownloads()
    let task = Self.start { await setup.model.downloadInstallRequested(Self.request()) }
    await Self.waitUntil { setup.download.suspendedDownloadCount == 1 }
    let others = AndroidDeviceInventory.sample.devices.filter { $0.id != Self.tablet.id }
    setup.fake.setInventory(AndroidDeviceInventory(
      devices: removed ? others : others + [Self.tablet.with(state: .shutdown)],
      creationOptions: .sample
    ))
    await setup.model.refreshButtonTapped()
    setup.download.resumeDownloads()
    await task.value()
    let failure: AndroidAppInstallFailure = removed ? .emulator(.deviceNotFound) : .deviceNotReady(.notBooted)
    #expect(Self.notices(setup.model) == [.installFailed(Self.label, failure)])
    #expect(Self.removals(setup.download) == [Self.file])
    #expect(Self.appCalls(setup.fake).isEmpty)
  }

  @Test("판정 거절은 받은 파일을 지운 뒤 알리고 다시 읽지 않는다")
  func rejectedRemovesFile() async {
    let setup = await Self.loadedFixture()
    setup.package.setResult(.success(.sample(minSDK: .level(99))))
    await setup.model.downloadInstallRequested(Self.request())
    #expect(Self.notices(setup.model).count == 1)
    guard case .installFailed(_, .rejected) = Self.notices(setup.model).first else {
      Issue.record("판정 거절 알림이 아니다: \(Self.notices(setup.model))")
      return
    }
    #expect(Self.removals(setup.download) == [Self.file])
    #expect(Self.appCalls(setup.fake) == [.deviceTraits(Self.tablet.id)])
    #expect(Self.fetchCount(setup.fake) == 1)
  }

  @Test("기기 값 읽기·설치 명령 실패는 받은 파일을 한 번 지우고 알린 뒤 다시 읽는다")
  func emulatorFailureRemovesFileAndReloads() async {
    let traits = await Self.loadedFixture { $0.setDeviceTraits(.failure(.deviceNotBooted)) }
    await traits.model.downloadInstallRequested(Self.request())
    #expect(Self.notices(traits.model) == [.installFailed(Self.label, .emulator(.deviceNotBooted))])
    #expect(Self.removals(traits.download) == [Self.file])
    #expect(Self.fetchCount(traits.fake) == 2)

    let install = await Self.loadedFixture { $0.setInstallError(.installFailed(.updateIncompatible)) }
    await install.model.downloadInstallRequested(Self.request())
    #expect(Self.notices(install.model) == [
      .installFailed(Self.label, .emulator(.installFailed(.updateIncompatible))),
    ])
    #expect(Self.removals(install.download) == [Self.file])
    #expect(Self.appCalls(install.fake).count == 2)
    #expect(Self.fetchCount(install.fake) == 2)
  }

  @Test("실행 실패는 설치 후 실행 실패로 알리고, 받은 파일은 이미 지웠다")
  func launchFailure() async {
    let setup = await Self.loadedFixture { $0.setLaunchError(.launchFailed(.noLauncherActivity)) }
    await setup.model.downloadInstallRequested(Self.request(origin: .catalog))
    #expect(Self.notices(setup.model) == [
      .installedButNotLaunched(Self.label, .launchFailed(.noLauncherActivity)),
    ])
    #expect(Self.removals(setup.download) == [Self.file])
    #expect(Self.fetchCount(setup.fake) == 2)
  }
}

/// `downloadedPackageFailure` 의 사례 하나.
struct PackageFailureCase: Sendable {
  let error: AndroidPackageError
  let mimeType: String?
  let isWebPage: Bool

  init(_ error: AndroidPackageError, _ mimeType: String?, _ isWebPage: Bool) {
    self.error = error
    self.mimeType = mimeType
    self.isWebPage = isWebPage
  }
}

extension AndroidDevicesDownloadTests {
  // MARK: - 받기·검사 실패

  @Test(
    "받기 실패는 출처와 함께 알리고, 검사·기기 명령·다시 읽기·지우기가 없다",
    arguments: [
      (DownloadError.httpStatus(404), AndroidDownloadOrigin.enteredURL), (.offline, .enteredURL),
      (.insufficientDiskSpace, .catalog), (.httpStatus(410), .catalog), (.insecureRedirect, .catalog),
    ]
  )
  func downloadFailure(error: DownloadError, origin: AndroidDownloadOrigin) async {
    let setup = await Self.loadedFixture()
    setup.download.setDownloadScript(progress: [], result: .failure(error))
    await setup.model.downloadInstallRequested(Self.request(origin: origin))
    #expect(Self.notices(setup.model) == [.installFailed(Self.label, .download(error, origin: origin))])
    #expect(setup.package.calls.isEmpty)
    #expect(Self.appCalls(setup.fake).isEmpty)
    #expect(Self.removals(setup.download).isEmpty)
    #expect(Self.fetchCount(setup.fake) == 1)
    #expect(setup.model.activity.task(on: Self.tablet.id) == nil)
  }

  @Test(
    "받은 파일의 검사 실패는 웹 페이지 여부·출처와 함께 알리고, 받은 파일을 지우고 다시 읽지 않는다",
    arguments: [
      PackageFailureCase(.unreadable, "text/html", true), PackageFailureCase(
        .unreadable,
        "APPLICATION/XHTML+XML",
        true
      ),
      PackageFailureCase(.unreadable, "application/octet-stream", false), PackageFailureCase(.unreadable, nil, false),
      PackageFailureCase(.appBundle, "text/html", false), PackageFailureCase(
        .unsigned,
        "application/octet-stream",
        false
      ),
      PackageFailureCase(.unsafeEntry, nil, false),
    ]
  )
  func downloadedPackageFailure(testCase: PackageFailureCase) async {
    let (error, mimeType, isWebPage) = (testCase.error, testCase.mimeType, testCase.isWebPage)
    for origin in [AndroidDownloadOrigin.enteredURL, .catalog] {
      let setup = await Self.loadedFixture()
      let file = DownloadedFile(
        file: Self.file.file,
        folder: Self.file.folder,
        byteCount: 2048,
        mimeType: mimeType
      )
      setup.download.setDownloadScript(progress: [], result: .success(file))
      setup.package.setResult(.failure(error))
      await setup.model.downloadInstallRequested(Self.request(origin: origin))
      #expect(Self.notices(setup.model) == [
        .installFailed(Self.label, .downloadedPackage(error, isWebPage: isWebPage, origin: origin)),
      ])
      #expect(Self.removals(setup.download) == [file])
      #expect(Self.appCalls(setup.fake).isEmpty)
      #expect(Self.fetchCount(setup.fake) == 1)
    }
  }
}

/// 진행 기록의 받기 단계.
struct AndroidDeviceActivityDownloadTests {
  static let tablet = AndroidVirtualDevice.bootedTabletSample
  static let progress = DownloadProgress(receivedBytes: 1, expectedBytes: 2)

  @Test("받기 시작은 설치 작업과 받는 중(nil)을 함께 기록하고, 켜지지 않았거나 작업 중이면 아무것도 바꾸지 않는다")
  func beginDownload() {
    var activity = AndroidDeviceActivity()
    let result1 = activity.beginDownload(on: .phoneSample)
    #expect(!result1)
    #expect(activity == AndroidDeviceActivity())
    let result2 = activity.beginDownload(on: Self.tablet)
    #expect(result2)
    #expect(activity.task(on: Self.tablet.id) == .installApp)
    #expect(activity.downloadStage(on: Self.tablet.id) == .receiving(nil))
    let before = activity
    let result3 = activity.beginDownload(on: Self.tablet)
    #expect(!result3)
    #expect(activity == before)
  }

  @Test("진행은 받는 중일 때만 바뀌고, 취소 요청은 받는 중일 때만 된다")
  func progressAndCancel() {
    var activity = AndroidDeviceActivity()
    activity.downloadProgressed(Self.progress, on: Self.tablet.id)
    #expect(activity.downloadStage(on: Self.tablet.id) == nil)
    _ = activity.beginDownload(on: Self.tablet)
    activity.downloadProgressed(Self.progress, on: Self.tablet.id)
    #expect(activity.downloadStage(on: Self.tablet.id) == .receiving(Self.progress))
    #expect(!activity.isDownloadCancelRequested(on: Self.tablet.id))
    let result4 = activity.requestDownloadCancel(on: Self.tablet.id)
    #expect(result4)
    #expect(activity.isDownloadCancelRequested(on: Self.tablet.id))
    let result5 = activity.requestDownloadCancel(on: Self.tablet.id)
    #expect(!result5)
    activity.downloadProgressed(Self.progress, on: Self.tablet.id)
    #expect(activity.downloadStage(on: Self.tablet.id) == .cancelling)
  }

  @Test("받기 끝은 받기 단계만 지우고, 작업 끝은 둘 다 지운다. 같음 비교에 받기 단계가 든다")
  func endings() {
    var activity = AndroidDeviceActivity()
    _ = activity.beginDownload(on: Self.tablet)
    var plain = AndroidDeviceActivity()
    _ = plain.begin(.installApp, on: Self.tablet)
    #expect(activity != plain)
    activity.downloadEnded(on: Self.tablet.id)
    #expect(activity.downloadStage(on: Self.tablet.id) == nil)
    #expect(activity.task(on: Self.tablet.id) == .installApp)
    let result6 = activity.requestDownloadCancel(on: Self.tablet.id)
    #expect(!result6)
    #expect(activity == plain)
    var other = AndroidDeviceActivity()
    _ = other.beginDownload(on: Self.tablet)
    other.end(on: Self.tablet.id)
    #expect(other.downloadStage(on: Self.tablet.id) == nil)
    #expect(other.task(on: Self.tablet.id) == nil)
  }
}
