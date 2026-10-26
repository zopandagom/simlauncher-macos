import AppBundleInterface
import Core
import DownloadInterface
import Foundation
import SimulatorInterface

/// 앱 설치 흐름: (zip 이면) 풀기 → 검사 → 지금 목록으로 판정 → 켜기·Simulator 앱 열기 → 설치 → 실행 → 다시 읽기.
/// 첫 단계인 켜기·Simulator 앱 열기(`bootIfNeededAndShowSimulator`)는 켜기 버튼·링크 열기도 함께 쓴다.
/// 링크 열기와 받기 결과 해석도 같은 창구를 쓰므로 여기에 둔다.
/// `LauncherModel` 이 `private` 으로 소유하고, 진행 기록(`activity`)을 시작한 Model 메서드(이벤트 메서드와 그것이 부르는
/// private 도우미, 예: `installApp`·`installDownload`) 안에서만 부른다. Model 상태를 직접 바꾸지 않는다 (바꾸는 것은 창구로만).
/// Client 는 직접 부르고, Model 상태에는 부를 때 넘겨받는 `Host` 창구로만 닿는다 (Model 상태는 `private(set)` 그대로).
/// 모든 실패가 안에서 알림으로 끝나 던지지 않는다.
@MainActor
struct AppInstallFlow {
  /// Model 이 부를 때마다 만들어 넘기는 창구. Model 을 잡으므로 저장하지 않는다.
  struct Host {
    /// 알림을 쌓는다.
    let enqueue: @MainActor (LauncherNotice) -> Void
    /// 목록을 다시 읽는다 (읽는 중이면 그 읽기에 합쳐진다).
    let reload: @MainActor () async -> Void
    /// 지금 목록 상태. 부르는 순간의 값을 돌려준다 (미리 잡아 두지 않는다).
    let listState: @MainActor () -> LauncherListState
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
    guard let extracted = await self.extract(item, label: label, host: host, failure: AppInstallFailure.bundle)
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
  func downloadedFile(
    from result: Result<DownloadedFile, DownloadError>,
    cancelRequested: Bool,
    label: LauncherNotice.Device,
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
      host.enqueue(.installFailed(label, .download(error, from: origin)))
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
    let extracted = await self.extract(file.file, label: label, host: host) { error in
      AppInstallFailure.downloaded(error, mimeType: mimeType, from: origin)
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

  /// zip 을 푼다. 실패하면 `failure` 로 만든 알림을 쌓고 nil (명령을 실행하기 전이라 다시 읽지 않는다.
  /// 풀다 만 폴더는 Impl 이 지웠다). 받은 zip 에도 쓴다.
  private func extract(
    _ zip: URL,
    label: LauncherNotice.Device,
    host: Host,
    failure: (AppBundleError) -> AppInstallFailure
  ) async -> ExtractedApp? {
    do throws(AppBundleError) {
      return try await self.appBundle.extractApp(fromZip: zip)
    } catch {
      host.enqueue(.installFailed(label, failure(error)))
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
    guard let prepared = await self.prepareInstall(url, on: id, label: label, host: host) else { return }
    await self.runInstall(prepared.info, on: prepared.device, label: label, host: host)
  }

  /// 검사하고, 검사가 끝난 시점의 목록으로 기기와 앱을 판정한다. 실패하면 알림을 쌓고 nil
  /// (명령을 실행하지 않았으므로 다시 읽지 않는다).
  private func prepareInstall(
    _ url: URL,
    on id: VirtualDevice.ID,
    label: LauncherNotice.Device,
    host: Host
  ) async -> (info: AppBundleInfo, device: VirtualDevice)? {
    let info: AppBundleInfo
    do throws(AppBundleError) {
      info = try await self.appBundle.inspect(url)
    } catch {
      host.enqueue(.installFailed(label, .bundle(error)))
      return nil
    }
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
    return (info, device)
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
