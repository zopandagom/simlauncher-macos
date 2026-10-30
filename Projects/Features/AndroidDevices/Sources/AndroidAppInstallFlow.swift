import AndroidEmulatorInterface
import AndroidPackageInterface
import Core
import DownloadInterface
import Foundation

/// 앱 설치 흐름: (로컬이면 항목 수 / URL·카탈로그면 받은 결과) → apk 검사 → 지금 목록으로 대상 다시 확인 → 기기 값(API·ABI) →
/// 판정 → 설치 → 실행 → 다시 읽기. 같은 창구를 쓰는 앱 실행(행 "앱 실행…")과 링크 열기, 앱 작업 대상 확인도 맡는다
/// (그 시트와 앱 실행 시트의 목록 읽기는 `AndroidAppSheetsModel` 이 한다).
/// `AndroidDevicesModel` 이 `private` 으로 소유하고, 진행 기록(`activity`)을 시작한 Model 메서드 안에서만 부른다.
/// Client 는 직접 부르고, Model 상태에는 부를 때 넘겨받는 `Host` 창구로만 닿는다 (Model 상태를 직접 바꾸지 않는다).
/// 모든 실패가 안에서 알림으로 끝나 던지지 않는다. 명령이 기기에 닿기 전의 실패(받기·검사·대상·판정)는 다시 읽지 않는다.
/// 받은 파일은 모든 경로에서 정확히 한 번 지운다: 설치 명령이 끝나면(성공·실패) 곧바로(실행 전), 설치 전에 끝나면 알림을
/// 쌓기 전에. 설치 명령은 `--no-incremental` 이라 설치가 끝난 뒤 호스트 파일을 읽지 않는다 (AndroidEmulator Impl).
@MainActor
struct AndroidAppInstallFlow {
  /// Model 이 부를 때마다 만들어 넘기는 창구. Model 을 잡으므로 저장하지 않는다.
  struct Host {
    /// 알림을 쌓는다.
    let enqueue: @MainActor (AndroidDevicesNotice) -> Void
    /// 목록을 다시 읽는다 (읽는 중이면 그 읽기에 합쳐진다).
    let reload: @MainActor () async -> Void
    /// 지금 목록 상태. 부르는 순간의 값을 돌려준다 (미리 잡아 두지 않는다).
    let listState: @MainActor () -> AndroidDevicesListState
  }

  let emulator: any AndroidEmulatorClient
  let package: any AndroidPackageClient
  let download: any DownloadClient

  /// 고르거나 끌어다 놓은 항목: 정확히 하나여야 하고(둘 이상이면 이유를 알린다), 검사·판정을 통과하면 설치하고 실행한다.
  func install(_ items: [URL], on id: AndroidVirtualDevice.ID, label: AndroidDeviceLabel, host: Host) async {
    guard let item = items.first else { return }
    guard items.count == 1 else {
      host.enqueue(.installFailed(label, .multipleItems))
      return
    }
    let info: AndroidPackageInfo
    do throws(AndroidPackageError) {
      info = try await self.package.inspect(item)
    } catch {
      host.enqueue(.installFailed(label, .package(error)))
      return
    }
    await self.installInspected(info, on: id, label: label, downloaded: nil, host: host)
  }

  /// URL·카탈로그에서 받은 결과: 취소를 눌렀으면 받은 파일을 지우고 알림 없이, 실패면 출처에 맞는 알림으로 끝낸다
  /// (폴더는 Download 가 지웠다). 받았으면 검사하고 로컬 apk 와 같은 단계로 설치·실행한다. 받기 실패·검사 실패는 다시 읽지 않는다.
  func installDownloaded(
    _ result: Result<DownloadedFile, DownloadError>,
    cancelRequested: Bool,
    request: AndroidDownloadInstallRequest,
    host: Host
  ) async {
    let label = request.device
    if cancelRequested {
      // 막 끝난 성공 뒤에 취소를 눌렀어도 취소가 이긴다.
      if case let .success(file) = result {
        await self.download.removeDownloaded(file)
      }
      return
    }
    let file: DownloadedFile
    switch result {
    case let .success(downloaded):
      file = downloaded
    case let .failure(error):
      // 취소를 누르지 않았는데 온 `.cancelled` 도 이유 없이 행만 돌아가지 않게 알린다 (코드상 나오지 않는다).
      host.enqueue(.installFailed(label, .download(error, origin: request.origin)))
      return
    }
    let info: AndroidPackageInfo
    do throws(AndroidPackageError) {
      info = try await self.package.inspect(file.file)
    } catch {
      await self.download.removeDownloaded(file)
      host.enqueue(.installFailed(label, AndroidAppInstallFailure(
        downloaded: error,
        mimeType: file.mimeType,
        origin: request.origin
      )))
      return
    }
    await self.installInspected(info, on: request.deviceID, label: label, downloaded: file, host: host)
  }

  /// 검사를 통과한 apk: 대상 다시 확인 → 기기 값 → 판정 → 설치 → 실행 → 다시 읽기. `downloaded` 가 있으면 설치 명령이
  /// 끝난 직후(실행 전), 설치 전에 끝나면 알림을 쌓기 전에 지운다.
  private func installInspected(
    _ info: AndroidPackageInfo,
    on id: AndroidVirtualDevice.ID,
    label: AndroidDeviceLabel,
    downloaded: DownloadedFile?,
    host: Host
  ) async {
    // 검사하는 동안(받는 동안) 새로 고침으로 목록이 바뀌었을 수 있다. 이 기기의 작업은 지금 이 설치라 진행 중은 보지 않는다.
    if let failure = self.target(id, in: host.listState()).failure {
      await self.remove(downloaded)
      host.enqueue(.installFailed(label, .init(failure)))
      return
    }
    let traits: AndroidDeviceTraits
    do throws(AndroidEmulatorError) {
      traits = try await self.emulator.deviceTraits(id)
    } catch {
      await self.remove(downloaded)
      host.enqueue(.installFailed(label, .emulator(error)))
      await host.reload()
      return
    }
    if let problem = info.installProblem(on: traits) {
      await self.remove(downloaded)
      host.enqueue(.installFailed(label, .rejected(problem)))
      return
    }
    var installError: AndroidEmulatorError?
    do throws(AndroidEmulatorError) {
      try await self.emulator.install(info.location, on: id)
    } catch {
      installError = error
    }
    // 설치 명령이 끝나면 받은 파일은 필요 없다 (실측: 설치 직후 지워도 실행된다).
    await self.remove(downloaded)
    if let installError {
      host.enqueue(.installFailed(label, .emulator(installError)))
      await host.reload()
      return
    }
    do throws(AndroidEmulatorError) {
      try await self.emulator.launch(info.packageName, on: id)
    } catch {
      host.enqueue(.installedButNotLaunched(label, error))
    }
    await host.reload()
  }

  /// 받은 파일이 있으면 지운다. 로컬 apk(nil)면 아무것도 하지 않는다 (기다리지도 않는다).
  private func remove(_ downloaded: DownloadedFile?) async {
    guard let downloaded else { return }
    await self.download.removeDownloaded(downloaded)
  }

  /// 행 "앱 실행…" 시트에서 고른 앱을 실행하고 다시 읽는다. 실패하면 알림을 쌓는다.
  func launch(
    _ package: AndroidPackageName,
    on id: AndroidVirtualDevice.ID,
    label: AndroidDeviceLabel,
    host: Host
  ) async {
    do throws(AndroidEmulatorError) {
      try await self.emulator.launch(package, on: id)
    } catch {
      host.enqueue(.launchFailed(label, .emulator(error)))
    }
    await host.reload()
  }

  /// 행 "링크 열기…" 시트의 링크를 열고 다시 읽는다. 실패하면 알림을 쌓는다.
  func openURL(_ link: DeepLink, on id: AndroidVirtualDevice.ID, label: AndroidDeviceLabel, host: Host) async {
    do throws(AndroidEmulatorError) {
      try await self.emulator.openURL(link, on: id)
    } catch {
      host.enqueue(.openURLFailed(label, .emulator(error)))
    }
    await host.reload()
  }

  /// 시트를 연 사이 바뀌었을 수 있는 대상 기기를 지금 목록으로 확인한다. 안 되면 `failed` 로 만든 알림을 쌓고 nil.
  func target(
    _ id: AndroidVirtualDevice.ID,
    host: Host,
    failed: (AndroidAppActionFailure) -> AndroidDevicesNotice
  ) -> AndroidVirtualDevice? {
    let target = self.target(id, in: host.listState())
    guard case let .ready(device) = target else {
      if let failure = target.failure {
        host.enqueue(failed(failure))
      }
      return nil
    }
    return device
  }

  /// 앱 작업 대상 기기를 지금 목록으로 다시 확인한다 (시트를 연 사이나 검사하는 사이 바뀌었을 수 있다).
  /// 같은 기기의 진행 중 작업은 보지 않는다 (부르는 쪽이 정한다).
  func target(_ id: AndroidVirtualDevice.ID, in state: AndroidDevicesListState) -> AndroidAppTarget {
    guard case let .loaded(list) = state, let device = list.device(id: id) else { return .notFound }
    if case let .blocked(reason) = device.appActionAvailability {
      return .blocked(reason)
    }
    return .ready(device)
  }
}

/// 앱 작업 대상을 지금 목록으로 다시 확인한 결과.
enum AndroidAppTarget: Hashable, Sendable {
  case ready(AndroidVirtualDevice)
  /// 목록이 없거나 목록에 그 기기가 없다.
  case notFound
  /// 켜짐이 아니거나 쓸 수 없다 (`appActionAvailability`).
  case blocked(AndroidAppActionBlockReason)

  /// 실행·링크 열기 실패 원인. `.ready` 면 nil.
  var failure: AndroidAppActionFailure? {
    switch self {
    case .ready: nil
    case .notFound: .emulator(.deviceNotFound)
    case let .blocked(reason): .deviceNotReady(reason)
    }
  }
}

extension AndroidAppInstallFailure {
  /// 대상 확인 실패를 설치 실패 원인으로 옮긴다.
  init(_ failure: AndroidAppActionFailure) {
    switch failure {
    case let .deviceNotReady(reason): self = .deviceNotReady(reason)
    case let .emulator(error): self = .emulator(error)
    }
  }
}
