import AndroidSDKInterface
import CommandInterface
import Core
import DownloadInterface
import Foundation

/// 파일만 읽어 SDK 상태를 판정하고, 저장소 XML·패키지를 `DownloadClient` 로 받아 zipinfo·unzip(`CommandClient`)으로
/// SDK 안 스테이징에 푼 뒤 최종 경로로 원자적으로 옮기는 `AndroidSDKClient`. 이미 있는 패키지 폴더는 고치거나 덮어쓰지 않는다.
/// adb·emulator 는 실행하지 않는다 (실행하는 명령은 zipinfo·unzip 뿐).
public struct AndroidSDKClientImpl: AndroidSDKClient {
  private let download: any DownloadClient
  private let command: any CommandClient
  private let host: AndroidHostArchitecture
  private let sdkRoot: @Sendable () async -> AndroidSDKRootChoice
  private let availableCapacity: @Sendable (URL) -> Int64?
  private let volume: @Sendable (URL) -> SDKVolume
  private let downloadsDirectory: URL
  private let endpoints: RepositoryEndpoints
  private let staging = StagingFolders()

  /// App 은 이 Impl 을 하나만 만든다 (지금 쓰는 스테이징 목록을 함께 쓴다).
  /// - Parameters:
  ///   - download: Launcher 와 같은 인스턴스 (지금 받는 폴더 목록을 함께 써야 서로의 남은 폴더 정리가 진행 중인 받기를 지우지 않는다).
  ///   - command: zipinfo·unzip 실행.
  ///   - hostArchitecture: `AppBundleClientImpl.hostArchitecture` (판정을 복제하지 않는다).
  ///   - sdkRoot: 공개 메서드 한 번에 한 번 부른다. App 이 Preferences `AndroidSDKPath` 로 만든다.
  public init(
    download: any DownloadClient,
    command: any CommandClient,
    hostArchitecture: CPUArchitecture,
    sdkRoot: @escaping @Sendable () async -> AndroidSDKRootChoice
  ) {
    self.init(
      download: download,
      command: command,
      hostArchitecture: hostArchitecture,
      sdkRoot: sdkRoot,
      availableCapacity: SDKFiles.availableCapacity,
      volume: SDKVolume.read,
      downloadsDirectory: FileManager.default.temporaryDirectory,
      endpoints: .google
    )
  }

  /// 테스트용: 여유 공간·볼륨 읽기, 받기 임시 폴더(볼륨 비교용), 저장소 주소를 정한다. 여유가 nil 이면 그 비교를 건너뛴다.
  init(
    download: any DownloadClient,
    command: any CommandClient,
    hostArchitecture: CPUArchitecture,
    sdkRoot: @escaping @Sendable () async -> AndroidSDKRootChoice,
    availableCapacity: @escaping @Sendable (URL) -> Int64?,
    volume: @escaping @Sendable (URL) -> SDKVolume,
    downloadsDirectory: URL,
    endpoints: RepositoryEndpoints
  ) {
    self.download = download
    self.command = command
    self.host = AndroidHostArchitecture(hostArchitecture)
    self.sdkRoot = sdkRoot
    self.availableCapacity = availableCapacity
    self.volume = volume
    self.downloadsDirectory = downloadsDirectory
    self.endpoints = endpoints
  }

  @concurrent
  public func checkSDK() async -> AndroidSDKStatus {
    let choice = await self.sdkRoot()
    return AndroidSDKStatus.judge(self.facts(choice))
  }

  /// 상태 판정 → (쓸 수 없는 위치·막는 이유면 `.sdkFolderUnavailable`, 없는 것이 없으면 빈 계획) → XML 두 개 동시 받기 →
  /// 해석(메인 밖) → 선택. 받기 실패는 취소가 하나라도 있으면 `.cancelled`, 아니면 repository 쪽 실패를 먼저.
  @concurrent
  public func fetchInstallPlan() async throws(AndroidSDKPlanError) -> AndroidSDKInstallPlan {
    let choice = await self.sdkRoot()
    let status = AndroidSDKStatus.judge(self.facts(choice))
    let root = try Self.usableRoot(choice, status: status)
    let existing = SDKFiles.existingFolder(for: root.url)
    let sdkVolume = self.volume(existing)
    let sameVolume = sdkVolume.device != nil && sdkVolume.device == self.volume(self.downloadsDirectory).device
    guard !status.missing.isEmpty else {
      guard !Task.isCancelled else {
        throw .cancelled
      }
      return AndroidSDKInstallPlan(
        root: root,
        sdkVolumeName: sdkVolume.name,
        sameVolumeAsDownloads: sameVolume,
        packages: [],
        licenses: []
      )
    }
    let (repository, systemImages) = try await self.fetchRepositories()
    let input = AndroidSDKSelection.Input(
      repository: repository,
      repositoryBase: self.endpoints.repositoryBase,
      systemImages: systemImages,
      systemImagesBase: self.endpoints.systemImagesBase,
      host: self.host,
      missing: status.missing,
      installedEmulator: status.installedEmulatorRevision
    )
    let result = AndroidSDKSelection.plan(
      input,
      root: root,
      sdkVolumeName: sdkVolume.name,
      sameVolumeAsDownloads: sameVolume
    )
    guard !Task.isCancelled else {
      throw .cancelled
    }
    switch result {
    case let .success(plan):
      return plan
    case let .failure(.noCompatiblePackage(component)), let .failure(.licenseMissing(component)):
      throw .noCompatiblePackage(component)
    }
  }

  /// 시작 확인(위치 바뀜 → 라이선스 → 쓰기 → 여유) 뒤 패키지마다: 취소 확인 → 최종 경로에 무엇이든 있으면 건너뜀 → 설치.
  @concurrent
  public func install(
    _ plan: AndroidSDKInstallPlan,
    acceptedLicenses: Set<String>,
    progress: @escaping @Sendable (AndroidSDKInstallProgress) async -> Void
  ) async throws(AndroidSDKInstallError) -> AndroidSDKInstallOutcome {
    guard await self.sdkRoot() == .root(plan.root) else {
      throw .sdkLocationChanged
    }
    guard plan.licensesToConfirm(accepted: acceptedLicenses).isEmpty else {
      throw .licenseNotAccepted
    }
    let pending = plan.packages.filter { !SDKFiles.exists(plan.root.destination(for: $0.path)) }
    if !pending.isEmpty {
      try self.checkWritable(plan.root, pending: pending)
      try self.checkSpace(plan.root, pending: pending)
    }
    let pendingComponents = Set(pending.map(\.component))
    let reporter = InstallProgressReporter(
      packageCount: plan.packages.count,
      total: pending.reduce(0) { $0 + $1.archive.size },
      progress: progress
    )
    let installer = PackageInstaller(
      download: self.download,
      command: self.command,
      staging: self.staging,
      availableCapacity: self.availableCapacity
    )
    var installed: [AndroidSDKComponent] = []
    var alreadyPresent: [AndroidSDKComponent] = []
    for (offset, package) in plan.packages.enumerated() {
      guard !Task.isCancelled else {
        throw .cancelled
      }
      if SDKFiles.exists(plan.root.destination(for: package.path)) {
        alreadyPresent.append(package.component)
        if pendingComponents.contains(package.component) {
          await reporter.skipped(package)
        }
        continue
      }
      try await installer.install(package, index: offset + 1, root: plan.root, reporter: reporter)
      installed.append(package.component)
    }
    return AndroidSDKInstallOutcome(installed: installed, alreadyPresent: alreadyPresent)
  }

  @concurrent
  public func removeLeftovers() async {
    if case let .root(root) = await self.sdkRoot(),
       SDKFiles.rootKind(root.url.path(percentEncoded: false)) == .directory,
       let real = RealPath.of(root.url)
    {
      self.staging.removeLeftovers(root: real)
    }
    await self.download.removeLeftoverDownloads()
  }

  @concurrent
  public func inspectCandidateFolder(_ url: URL) async -> (candidate: AndroidSDKFolderCandidate, writable: Bool) {
    let (facts, writable) = SDKFileFacts.candidate(url, volume: self.volume)
    return (AndroidSDKFolderCandidate.judge(facts), writable)
  }

  /// 쓸 수 없는 위치이거나, 없는 것이 있는데 막는 이유가 있으면 `.sdkFolderUnavailable`.
  private static func usableRoot(
    _ choice: AndroidSDKRootChoice,
    status: AndroidSDKStatus
  ) throws(AndroidSDKPlanError) -> AndroidSDKRoot {
    guard case let .root(root) = choice else {
      throw .sdkFolderUnavailable
    }
    if case .unusable = status.location {
      throw .sdkFolderUnavailable
    }
    if !status.missing.isEmpty, status.installBlocker != nil {
      throw .sdkFolderUnavailable
    }
    return root
  }

  /// XML 두 개(repository·시스템 이미지)를 동시에 받아 메인 밖에서 해석한다. 받기 실패는 취소가 하나라도 있으면 `.cancelled`,
  /// 아니면 repository 쪽 실패를 먼저.
  private func fetchRepositories() async throws(AndroidSDKPlanError) -> (AndroidRepository, AndroidRepository) {
    async let repositoryData = self.fetch(self.endpoints.repository)
    async let systemImagesData = self.fetch(self.endpoints.systemImages)
    let fetched = await (repositoryData, systemImagesData)
    switch fetched {
    case let (.success(first), .success(second)):
      do throws(AndroidRepositoryProblem) {
        return try await (AndroidRepository.decoded(from: first), AndroidRepository.decoded(from: second))
      } catch {
        throw Task.isCancelled ? .cancelled : .repositoryUnreadable
      }
    case (.failure(.cancelled), _), (_, .failure(.cancelled)):
      throw .cancelled
    case let (.failure(error), _), let (_, .failure(error)):
      throw DownloadFailureMapping.failure(error).map { AndroidSDKPlanError.download($0) } ?? .cancelled
    }
  }

  private func facts(_ choice: AndroidSDKRootChoice) -> AndroidSDKFileFacts {
    SDKFileFacts.collect(choice, abi: self.host.systemImageABI, volume: self.volume)
  }

  private func fetch(_ url: DownloadURL) async -> Result<Data, DownloadError> {
    do throws(DownloadError) {
      return try await .success(self.download.fetchData(url, maxBytes: AndroidRepository.maxByteCount))
    } catch {
      return .failure(error)
    }
  }

  /// 위치(없으면 기본 위치만 가장 가까운 있는 조상)와, 받을 패키지마다 최종 경로의 가장 가까운 있는 조상이 쓸 수 있는 디렉터리여야 하고,
  /// 위치(또는 그 조상)의 볼륨이 링크와 `RENAME_EXCL` 을 지원해야 한다 (`SDKVolume.supportsInstall`. 볼륨은 위치에서만 본다).
  /// 고른 폴더가 없거나 파일·깨진 링크면 쓸 수 없다.
  private func checkWritable(_ root: AndroidSDKRoot, pending: [AndroidSelectedPackage]) throws(AndroidSDKInstallError) {
    let rootKind = SDKFiles.rootKind(root.url.path(percentEncoded: false))
    let rootFolder: URL
    switch rootKind {
    case .directory:
      rootFolder = root.url
    case .absent where root.isDefault:
      rootFolder = SDKFiles.nearestExistingAncestor(of: root.url)
    default:
      throw .sdkFolderUnavailable
    }
    guard SDKFiles.isWritableDirectory(rootFolder), self.volume(rootFolder).supportsInstall != false else {
      throw .sdkFolderUnavailable
    }
    guard rootKind == .directory else {
      return
    }
    for package in pending {
      let ancestor = SDKFiles.nearestExistingAncestor(of: root.destination(for: package.path))
      guard SDKFiles.isWritableDirectory(ancestor) else {
        throw .sdkFolderUnavailable
      }
    }
  }

  /// 받을 패키지마다 `archive.size × 3` 의 합을 SDK 볼륨 여유와, 가장 큰 `archive.size` 를 받기 볼륨 여유와 비교한다.
  /// 같은 볼륨이면 두 값의 합을 한 번에 비교한다 (풀자마자 받은 파일을 지우므로 받기 폴더는 하나만 동시에 있다).
  /// 여유를 읽지 못하면 그 비교를 건너뛴다.
  private func checkSpace(_ root: AndroidSDKRoot, pending: [AndroidSelectedPackage]) throws(AndroidSDKInstallError) {
    guard let first = pending.first?.component else {
      return
    }
    let estimate = pending.reduce(Int64(0)) {
      $0.addingClamped($1.archive.size.multipliedClamped(by: AndroidSDKInstallPlan.installSizeFactor))
    }
    let largest = pending.map(\.archive.size).max() ?? 0
    let sdkFolder = SDKFiles.existingFolder(for: root.url)
    let sdkDevice = self.volume(sdkFolder).device
    let sameVolume = sdkDevice != nil && sdkDevice == self.volume(self.downloadsDirectory).device
    let sdkAvailable = self.availableCapacity(sdkFolder)
    if sameVolume {
      let required = estimate.addingClamped(largest)
      if let sdkAvailable, required > sdkAvailable {
        throw .insufficientDiskSpace(first, required: required, available: sdkAvailable)
      }
      return
    }
    if let sdkAvailable, estimate > sdkAvailable {
      throw .insufficientDiskSpace(first, required: estimate, available: sdkAvailable)
    }
    if let downloadsAvailable = self.availableCapacity(self.downloadsDirectory), largest > downloadsAvailable {
      throw .insufficientDiskSpace(first, required: largest, available: downloadsAvailable)
    }
  }
}

private extension Int64 {
  /// 곱이 넘치면 `Int64.max`.
  func multipliedClamped(by factor: Int64) -> Int64 {
    let (product, overflow) = self.multipliedReportingOverflow(by: factor)
    return overflow ? .max : product
  }

  /// 합이 넘치면 `Int64.max`.
  func addingClamped(_ other: Int64) -> Int64 {
    let (sum, overflow) = self.addingReportingOverflow(other)
    return overflow ? .max : sum
  }
}
