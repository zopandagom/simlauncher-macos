import AppBundleInterface
import Core
import DownloadInterface
import Foundation
import SimulatorInterface

/// 앱 설치 흐름: (zip 이면) 풀기 → 검사 → 지금 목록으로 판정 → 켜기·Simulator 앱 열기 → 설치 → 실행 → 다시 읽기.
/// 첫 단계인 켜기·Simulator 앱 열기(`bootIfNeededAndShowSimulator`)는 켜기 버튼·링크 열기도 함께 쓴다.
/// 링크 열기와 받기 결과 해석도 같은 창구를 쓰므로 여기에 둔다.
/// 여러 기기 설치는 받기·풀기·검사를 한 번만 하고, 기기별 판정 → 켜기 → 설치 → 실행을 동시에 돌려 끝나는 대로 그 기기를
/// `finished` 로 풀고, 결과를 알림 하나(`.batchFinished`)에 모은다. 여러 기기 켜기도 같은 방식이다.
/// `LauncherModel` 이 `private` 으로 소유하고, 진행 기록(`activity`)을 시작한 Model 메서드(이벤트 메서드와 그것이 부르는
/// private 도우미, 예: `installApp`·`installDownload`) 안에서만 부른다. Model 상태를 직접 바꾸지 않는다 (바꾸는 것은 창구로만).
/// Client 는 직접 부르고, Model 상태에는 부를 때 넘겨받는 `Host` 창구로만 닿는다 (Model 상태는 `private(set)` 그대로).
/// 모든 실패가 안에서 알림으로 끝나 던지지 않는다.
@MainActor
struct AppInstallFlow {
  /// Model 이 부를 때마다 만들어 넘기는 창구. Model 을 잡으므로 저장하지 않는다.
  /// 여러 기기 흐름이 기기별 자식 작업에 넘기므로 Sendable 이다 (Model 은 `@MainActor` 클래스라 잡아도 Sendable).
  struct Host: Sendable {
    /// 알림을 쌓는다.
    let enqueue: @MainActor @Sendable (LauncherNotice) -> Void
    /// 목록을 다시 읽는다 (읽는 중이면 그 읽기에 합쳐진다).
    let reload: @MainActor @Sendable () async -> Void
    /// 지금 목록 상태. 부르는 순간의 값을 돌려준다 (미리 잡아 두지 않는다).
    let listState: @MainActor @Sendable () -> LauncherListState
    /// 여러 기기 묶음에서 그 기기가 끝났다 (기기, 묶음 소유자 번호). 그 번호의 진행 기록만 지워 행을 바로 푼다.
    /// 한 기기 흐름은 부르지 않는다 (Model 의 defer 가 끝낸다).
    let finished: @MainActor @Sendable (VirtualDevice.ID, Int) -> Void
  }

  let simulator: any SimulatorClient
  let appBundle: any AppBundleClient
  let download: any DownloadClient

  /// 고르거나 끌어다 놓은 항목: 정확히 하나여야 하고(둘 이상이면 이유를 알린다), zip 이면 풀어서, 아니면 그대로 검사·설치·실행한다.
  func install(_ items: [URL], on id: VirtualDevice.ID, label: LauncherNotice.Device, host: Host) async {
    guard let item = items.first else { return }
    guard items.count == 1 else {
      host.enqueue(.installFailed(label, .multipleItems))
      return
    }
    guard AppInstallSource.isZip(item) else {
      await self.installBundle(item, on: id, label: label, host: host)
      return
    }
    guard let extracted = await self.extract(item, host: host, failed: { .installFailed(label, .bundle($0)) })
    else { return }
    await self.installExtracted(extracted, on: id, label: label, host: host)
  }

  /// 링크 열기 대상: 시트를 연 사이 바뀌었을 수 있어 지금 목록으로 다시 확인한다. 열 수 없으면 알림을 쌓고 nil.
  func openLinkTarget(_ draft: OpenURLDraft, host: Host) -> VirtualDevice? {
    let target = AppInstallTarget.current(draft.deviceID, in: host.listState())
    guard case let .ready(device) = target else {
      if let failure = target.openURLFailure {
        host.enqueue(.openURLFailed(draft.device, failure))
      }
      return nil
    }
    return device
  }

  /// 꺼져 있으면 켜고, Simulator 앱을 연 뒤 링크를 열고 다시 읽는다. 실패하면 알림을 쌓는다.
  func openLink(_ link: DeepLink, on device: VirtualDevice, label: LauncherNotice.Device, host: Host) async {
    // 막 켠 기기는 준비가 끝날 때까지 돌아오지 않는다 (콜드 부팅 직후 수십 초). 그동안 행이 진행 중을 보인다.
    guard await self.bootIfNeededAndShowSimulator(device, label: label, host: host) else { return }
    do throws(SimulatorError) {
      try await self.simulator.openURL(link, on: device.id)
    } catch {
      host.enqueue(.openURLFailed(label, .simulator(error)))
    }
    await host.reload()
  }

  /// 받기 결과를 해석한다. 취소를 눌렀으면 결과와 관계없이 알림 없이 nil (성공했으면 받은 파일을 지운다).
  /// 실패는 알림을 쌓고 nil (Client 가 폴더를 지웠다).
  /// 1대 요청이면 한 기기 흐름과 같은 알림, 여러 대면 `.batchInstallFailed` 다.
  func downloadedFile(
    from result: Result<DownloadedFile, DownloadError>,
    cancelRequested: Bool,
    start: InstallStart,
    origin: DownloadOrigin,
    host: Host
  ) async -> DownloadedFile? {
    if cancelRequested {
      if case let .success(file) = result {
        await self.download.removeDownloaded(file)
      }
      return nil
    }
    switch result {
    case let .success(file):
      return file
    case let .failure(error):
      // 취소를 누르지 않았는데 온 `.cancelled` 도 이유 없이 행만 돌아가지 않게 알린다 (코드상 나오지 않는다).
      host.enqueue(start.failedNotice(.download(error, from: origin)))
      return nil
    }
  }

  /// URL·카탈로그에서 받은 zip: 받는 동안 기기가 사라졌는지 확인 → 풀기 → 받은 파일 지우기 → 검사·설치·실행.
  /// `origin` 은 받은 파일 실패 문구만 고른다.
  func installDownloaded(
    _ file: DownloadedFile,
    on id: VirtualDevice.ID,
    label: LauncherNotice.Device,
    origin: DownloadOrigin,
    host: Host
  ) async {
    // 받는 동안 기기가 목록에서 사라졌으면(외부 삭제, 드묾) 풀지 않는다. 켜는 중 같은 상태는 검사 뒤 판정에 맡긴다.
    if case .notFound = AppInstallTarget.current(id, in: host.listState()) {
      await self.download.removeDownloaded(file)
      host.enqueue(.installFailed(label, .simulator(.deviceNotFound)))
      return
    }
    let mimeType = file.mimeType
    let extracted = await self.extract(file.file, host: host) { error in
      .installFailed(label, .downloaded(error, mimeType: mimeType, from: origin))
    }
    // 푼 뒤에는 받은 파일이 필요 없다. 설치 명령이 푼 .app 을 기기로 복사하기 전에 지워 디스크를 덜 쓴다.
    await self.download.removeDownloaded(file)
    guard let extracted else { return }
    await self.installExtracted(extracted, on: id, label: label, host: host)
  }

  /// 꺼져 있으면 켜고, 켜져 있던 기기도 Simulator 앱을 연다 (창을 닫아 두었어도 결과가 보이게). 켜기에 실패하면 알림을
  /// 띄우고 다시 읽은 뒤 false. 앱을 열지 못하면 알림만 띄우고 true (설치·실행·링크 열기는 창 없이 된다).
  func bootIfNeededAndShowSimulator(_ device: VirtualDevice, label: LauncherNotice.Device, host: Host) async -> Bool {
    if device.state == .shutdown {
      do throws(SimulatorError) {
        try await self.simulator.boot(device.id)
      } catch {
        host.enqueue(.bootFailed(label, error))
        await host.reload()
        return false
      }
    }
    do throws(SimulatorError) {
      try await self.simulator.openSimulatorApp()
    } catch {
      host.enqueue(.openAppFailed(label, error))
    }
    return true
  }

  /// zip 을 푼다. 실패하면 `failed` 로 만든 알림을 쌓고 nil (명령을 실행하기 전이라 다시 읽지 않는다.
  /// 풀다 만 폴더는 Impl 이 지웠다). 받은 zip 에도 쓴다.
  private func extract(
    _ zip: URL,
    host: Host,
    failed: (AppBundleError) -> LauncherNotice
  ) async -> ExtractedApp? {
    do throws(AppBundleError) {
      return try await self.appBundle.extractApp(fromZip: zip)
    } catch {
      host.enqueue(failed(error))
      return nil
    }
  }

  /// 푼 .app 을 설치하고, 성공·실패와 관계없이 끝나면 임시 폴더를 지운다 (비동기 defer 를 쓰지 않으려고 실패가 모두
  /// 안에서 끝나는 `installBundle` 뒤에 둔다). 설치 명령이 번들을 기기로 복사한 뒤라 지워도 된다.
  /// 지우지 못하면 다음에 기기 목록 화면을 열 때 지운다.
  private func installExtracted(
    _ extracted: ExtractedApp,
    on id: VirtualDevice.ID,
    label: LauncherNotice.Device,
    host: Host
  ) async {
    await self.installBundle(extracted.app, on: id, label: label, host: host)
    await self.appBundle.removeExtracted(extracted)
  }

  /// 검사·판정을 통과하면 설치하고 실행한다. 모든 실패가 안에서 알림으로 끝나 던지지 않는다.
  private func installBundle(_ url: URL, on id: VirtualDevice.ID, label: LauncherNotice.Device, host: Host) async {
    guard let info = await self.inspect(url, host: host, failed: { .installFailed(label, $0) }),
          let device = self.judge(info, on: id, label: label, host: host)
    else { return }
    await self.runInstall(info, on: device, label: label, host: host)
  }

  /// 검사한다. 실패하면 `failed` 로 만든 알림을 쌓고 nil (명령을 실행하지 않았으므로 다시 읽지 않는다).
  private func inspect(
    _ url: URL,
    host: Host,
    failed: (AppInstallFailure) -> LauncherNotice
  ) async -> AppBundleInfo? {
    do throws(AppBundleError) {
      return try await self.appBundle.inspect(url)
    } catch {
      host.enqueue(failed(.bundle(error)))
      return nil
    }
  }

  /// 검사가 끝난 시점의 목록으로 기기와 앱을 판정한다. 실패하면 알림을 쌓고 nil
  /// (명령을 실행하지 않았으므로 다시 읽지 않는다).
  private func judge(
    _ info: AppBundleInfo,
    on id: VirtualDevice.ID,
    label: LauncherNotice.Device,
    host: Host
  ) -> VirtualDevice? {
    // 검사하는 동안 새로 고침으로 목록이 바뀌었을 수 있다. 이 기기의 작업은 지금 이 설치라 진행 중은 보지 않는다.
    let target = AppInstallTarget.current(id, in: host.listState())
    guard case let .ready(device) = target else {
      if let failure = target.installFailure {
        host.enqueue(.installFailed(label, failure))
      }
      return nil
    }
    if let problem = info.installProblem(on: device.runtime, hostArchitecture: self.appBundle.hostArchitecture) {
      host.enqueue(.installFailed(label, .rejected(problem)))
      return nil
    }
    return device
  }

  /// 꺼져 있으면 켜고, Simulator 앱을 열고, 검사한 경로를 설치하고, 검사한 번들 ID 로 실행한 뒤 다시 읽는다.
  private func runInstall(
    _ info: AppBundleInfo,
    on device: VirtualDevice,
    label: LauncherNotice.Device,
    host: Host
  ) async {
    guard await self.bootIfNeededAndShowSimulator(device, label: label, host: host) else { return }
    do throws(SimulatorError) {
      try await self.simulator.install(info.location, on: device.id)
    } catch {
      host.enqueue(.installFailed(label, .simulator(error)))
      await host.reload()
      return
    }
    do throws(SimulatorError) {
      try await self.simulator.launch(info.bundleID, on: device.id)
    } catch {
      host.enqueue(.launchFailed(label, error))
    }
    await host.reload()
  }
}

// MARK: - 여러 기기

// 단계 메서드(`extract`·`inspect`·`judge`·`runInstall`)를 `private` 그대로 쓰려고 같은 파일에 둔다.
extension AppInstallFlow {
  /// 툴바 "파일에서 고르기…" 의 항목: (zip 이면 한 번 풀기 →) 한 번 검사 → 기기별 동시 판정·켜기·설치·실행 → 푼 폴더 지우기
  /// → 결과 알림. 시작한 기기가 없으면 건너뛴 이유를 알린다. 1대 요청은 Model 이 한 기기 흐름(`installApp`)으로 보내 여기 오지
  /// 않는다.
  func install(_ item: URL, start: InstallStart, host: Host) async {
    guard !start.begun.isEmpty else { return self.reportNotStarted(start, host: host) }
    guard AppInstallSource.isZip(item) else {
      return await self.notify(self.installEach(item, start: start, host: host), host: host)
    }
    guard let extracted = await self.extract(item, host: host, failed: { start.failedNotice(.bundle($0)) })
    else { return }
    let report = await self.installEach(extracted.app, start: start, host: host)
    await self.appBundle.removeExtracted(extracted)
    self.notify(report, host: host)
  }

  /// 받은 zip: 시작한 기기가 모두 목록에서 사라졌으면 풀지 않는다 → 한 번 풀기 → 받은 파일 지우기 → 위와 같다.
  /// 1대 요청이면 한 기기 흐름과 같다.
  func installDownloaded(_ file: DownloadedFile, start: InstallStart, origin: DownloadOrigin, host: Host) async {
    guard let first = start.begun.first else { return self.reportNotStarted(start, host: host) }
    guard !start.isSingle else {
      let label = start.requested[0].label
      return await self.installDownloaded(file, on: first.id, label: label, origin: origin, host: host)
    }
    let state = host.listState()
    if start.begun.allSatisfy({ AppInstallTarget.current($0.id, in: state) == .notFound }) {
      await self.download.removeDownloaded(file)
      let notFound = Dictionary(uniqueKeysWithValues: start.begun.map {
        ($0.id, BatchDeviceResult.installFailed(.simulator(.deviceNotFound)))
      })
      return self.notify(start.report(.install, results: notFound, simulatorAppError: nil), host: host)
    }
    let mimeType = file.mimeType
    let extracted = await self.extract(file.file, host: host) { error in
      start.failedNotice(.downloaded(error, mimeType: mimeType, from: origin))
    }
    await self.download.removeDownloaded(file)
    guard let extracted else { return }
    let report = await self.installEach(extracted.app, start: start, host: host)
    await self.appBundle.removeExtracted(extracted)
    self.notify(report, host: host)
  }

  /// 시작한 기기가 없을 때. 1대 요청이면 한 기기 흐름과 같다 (없음·상태 = 알림, 다른 작업 중 = 알림 없음).
  /// 여러 대면 결과 알림(모두 실패) 하나.
  func reportNotStarted(_ start: InstallStart, host: Host) {
    guard !start.isSingle else {
      guard let skip = start.skipped.first, skip.failure != .deviceBusy else { return }
      return host.enqueue(.installFailed(skip.target.label, skip.failure))
    }
    self.notify(start.report(.install, results: [:], simulatorAppError: nil), host: host)
  }

  /// 툴바 "선택한 기기 켜기": 시작한 기기가 1대면 행 "켜기" 와 같다 (실패 알림·성공이면 다시 읽기). 여러 대면 기기마다 동시에
  /// 켜고 Simulator 앱을 열어, 기기마다 다시 읽은 뒤 끝나는 대로 풀고 (먼저 켜진 행이 꺼짐으로 남지 않게), 실패가 있으면
  /// 결과 알림 하나.
  func boot(_ start: InstallStart, host: Host) async {
    guard start.begun.count > 1 else {
      guard let device = start.begun.first,
            await self.bootIfNeededAndShowSimulator(device, label: LauncherNotice.Device(device), host: host)
      else { return }
      return await host.reload()
    }
    let outcome = await self.eachDevice(start, host: host) { device, deviceHost in
      // 켜기 실패는 `bootIfNeededAndShowSimulator` 가 다시 읽는다.
      guard await self.bootIfNeededAndShowSimulator(device, label: LauncherNotice.Device(device), host: deviceHost)
      else { return }
      await deviceHost.reload()
    }
    self.notify(start.report(.boot, results: outcome.results, simulatorAppError: outcome.appError), host: host)
  }

  /// 한 번 검사하고 기기별로 동시에 판정 → 켜기 → 설치 → 실행한다. 검사가 실패하면 공통 실패 알림을 쌓고 nil.
  private func installEach(_ url: URL, start: InstallStart, host: Host) async -> BatchReport? {
    guard let info = await self.inspect(url, host: host, failed: start.failedNotice) else { return nil }
    let outcome = await self.eachDevice(start, host: host) { device, deviceHost in
      let label = LauncherNotice.Device(device)
      guard let current = self.judge(info, on: device.id, label: label, host: deviceHost) else { return }
      await self.runInstall(info, on: current, label: label, host: deviceHost)
    }
    return start.report(.install, results: outcome.results, simulatorAppError: outcome.appError)
  }

  /// 시작한 기기마다 동시에 `body` 를 돌리고, 끝나는 대로 `finished` 로 그 기기를 푼다. 기기별 알림은 쌓지 않고 결과로 모은다
  /// (Simulator 앱 열기 실패는 요청 순서로 처음 것 하나).
  private func eachDevice(
    _ start: InstallStart,
    host: Host,
    body: @escaping @MainActor @Sendable (VirtualDevice, Host) async -> Void
  ) async -> (results: [VirtualDevice.ID: BatchDeviceResult], appError: SimulatorError?) {
    await withTaskGroup(of: DeviceOutcome.self) { group in
      let owner = start.owner
      for device in start.begun {
        group.addTask { await Self.run(body, on: device, owner: owner, host: host) }
      }
      var results: [VirtualDevice.ID: BatchDeviceResult] = [:]
      var appErrors: [VirtualDevice.ID: SimulatorError] = [:]
      for await outcome in group {
        results[outcome.id] = outcome.result
        appErrors[outcome.id] = outcome.appError
      }
      return (results, start.begun.lazy.compactMap { appErrors[$0.id] }.first)
    }
  }

  /// 기기 한 대의 자식 작업: 알림을 결과로 모으는 창구로 `body` 를 돌리고, 끝나면 그 기기를 푼다.
  private static func run(
    _ body: @MainActor @Sendable (VirtualDevice, Host) async -> Void,
    on device: VirtualDevice,
    owner: Int,
    host: Host
  ) async -> DeviceOutcome {
    let collector = BatchResultCollector()
    await body(device, host.collecting(into: collector))
    host.finished(device.id, owner)
    return DeviceOutcome(id: device.id, result: collector.result, appError: collector.appError)
  }

  /// 결과가 있고 실패·건너뜀이 있으면 결과 알림을 쌓는다 (모두 성공이면 알림이 없다).
  private func notify(_ report: BatchReport?, host: Host) {
    guard let report, report.needsNotice else { return }
    host.enqueue(.batchFinished(report))
  }
}

private extension AppInstallFlow.Host {
  /// 알림을 기기 결과로 모으는 창구 (다시 읽기·목록·끝내기는 그대로).
  func collecting(into collector: BatchResultCollector) -> Self {
    Self(
      enqueue: { [enqueue] notice in
        if !collector.collect(notice) {
          enqueue(notice)
        }
      },
      reload: self.reload,
      listState: self.listState,
      finished: self.finished
    )
  }
}

/// 여러 기기 흐름에서 기기 한 대의 자식 작업이 돌려주는 값: 기기, 결과, Simulator 앱 열기 실패.
private struct DeviceOutcome: Sendable {
  let id: VirtualDevice.ID
  let result: BatchDeviceResult
  let appError: SimulatorError?
}

/// 여러 기기 흐름에서 기기 한 대의 알림을 결과로 바꿔 모은다. 기기별 자식 작업 안에서만 만든다.
@MainActor
private final class BatchResultCollector {
  private(set) var result: BatchDeviceResult = .succeeded
  /// Simulator 앱 열기 실패 (기기별 결과가 아니라 결과 알림 끝 줄).
  private(set) var appError: SimulatorError?

  /// 기기별 결과로 바꿀 수 있는 알림이면 모으고 true. 아니면 false (그대로 쌓는다).
  func collect(_ notice: LauncherNotice) -> Bool {
    switch notice {
    case let .installFailed(_, failure): self.result = .installFailed(failure)
    case let .launchFailed(_, error): self.result = .launchFailed(error)
    case let .bootFailed(_, error): self.result = .bootFailed(error)
    case let .openAppFailed(_, error): self.appError = self.appError ?? error
    default: return false
    }
    return true
  }
}
