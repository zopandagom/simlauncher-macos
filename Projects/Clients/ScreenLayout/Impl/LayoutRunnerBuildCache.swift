import CommandInterface
import Core
import Foundation
import ScreenLayoutInterface

/// 러너 빌드 캐시 (모든 기기가 함께 쓴다). `<뿌리>/<빌드 키>/Products` 에 `.xctestrun` 이 정확히 하나면 빌드된 것이다.
/// 빌드는 키마다 Task 하나를 함께 기다린다: 남은 `*.partial-*` 지우기 → `<키>.partial-<UUID>/Source` 에 소스 쓰기 →
/// `xcodebuild build-for-testing`(시간 제한) → 성공하면 `DerivedData/Build/Products` 만 `Products` 로 옮기고(116 MB → 3 MB, 실측)
/// 폴더 이름을 `<키>` 로 바꾼 뒤 쓰지 않는 다른 키 폴더를 지운다. 실패하면 partial 을 지운다 (실패는 디스크에 남지 않는다).
actor LayoutRunnerBuildCache {
  private let root: URL
  private let command: any CommandClient
  private let baseEnvironment: [String: String]
  private let timeout: Duration
  private var builds: [String: Task<Result<URL, ScreenLayoutError>, Never>] = [:]
  /// 이 캐시가 지금 빌드 중인 partial 폴더 이름 (남은 partial 지우기에서 뺀다).
  private var activePartials: Set<String> = []

  /// - Parameter root: `<러너 폴더>/builds`. 만들지 않는다 (처음 빌드할 때 만든다).
  init(root: URL, command: any CommandClient, baseEnvironment: [String: String], timeout: Duration) {
    self.root = root
    self.command = command
    self.baseEnvironment = baseEnvironment
    self.timeout = timeout
  }

  /// 빌드된 `.xctestrun`. 없으면 빌드한다 (같은 키의 빌드가 돌고 있으면 그것을 기다린다).
  /// - Parameter keep: 지우지 않을 다른 빌드 키 (살아 있는 러너가 쓰는 것).
  func xctestrun(
    key: String,
    xcode: XcodeInstallation,
    keep: Set<String>
  ) async -> Result<URL, ScreenLayoutError> {
    if let running = self.builds[key] {
      return await running.value
    }
    if let built = self.builtXCTestRun(key: key) {
      return .success(built)
    }
    let task = Task { await self.build(key: key, xcode: xcode, keep: keep) }
    self.builds[key] = task
    return await task.value
  }

  /// 돌고 있는 빌드를 모두 취소한다 (앱 종료). 각 빌드는 xcodebuild 가 멈춘 뒤 `.cancelled` 로 끝나고 partial 을 지운다.
  func cancelAll() {
    for task in self.builds.values {
      task.cancel()
    }
  }

  // MARK: - 빌드

  private func build(key: String, xcode: XcodeInstallation, keep: Set<String>) async -> Result<URL, ScreenLayoutError> {
    let partialName = "\(key).partial-\(UUID().uuidString)"
    let partial = self.root.appending(path: partialName, directoryHint: .isDirectory)
    self.activePartials.insert(partialName)
    defer {
      self.activePartials.remove(partialName)
      self.builds[key] = nil
    }
    let result = await self.buildInto(partial, key: key, xcode: xcode)
    if case .success = result {
      self.removeUnusedBuilds(keeping: keep.union([key]))
    } else {
      try? FileManager.default.removeItem(at: partial)
    }
    return result
  }

  private func buildInto(
    _ partial: URL,
    key: String,
    xcode: XcodeInstallation
  ) async -> Result<URL, ScreenLayoutError> {
    let source = partial.appending(path: "Source", directoryHint: .isDirectory)
    let derivedData = partial.appending(path: "DerivedData", directoryHint: .isDirectory)
    do {
      self.removeStalePartials()
      try LayoutRunnerSource.write(to: source)
    } catch {
      return .failure(.inspectorSetupFailed)
    }
    let result: CommandResult
    do throws(CommandError) {
      result = try await self.command.runCancellable(
        LayoutRunnerCommands.xcodebuild(xcode),
        LayoutRunnerCommands.buildArguments(sourceDirectory: source, derivedData: derivedData),
        environment: LayoutRunnerCommands.environment(base: self.baseEnvironment, xcode: xcode),
        timeout: self.timeout,
        onOutput: { _ in }
      )
    } catch {
      return .failure(Self.mapBuildError(error))
    }
    guard result.exitCode == 0 else { return .failure(.inspectorSetupFailed) }
    return self.finish(partial, derivedData: derivedData, key: key)
  }

  /// Products 만 남기고 `<키>` 로 이름을 바꾼다 (이미 있으면 지우고 바꾼다).
  private func finish(_ partial: URL, derivedData: URL, key: String) -> Result<URL, ScreenLayoutError> {
    let fileManager = FileManager.default
    let products = partial.appending(path: "Products", directoryHint: .isDirectory)
    let destination = self.root.appending(path: key, directoryHint: .isDirectory)
    do {
      try fileManager.moveItem(at: derivedData.appending(path: "Build/Products"), to: products)
      try fileManager.removeItem(at: derivedData)
      if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
        try fileManager.removeItem(at: destination)
      }
      try fileManager.moveItem(at: partial, to: destination)
    } catch {
      return .failure(.inspectorSetupFailed)
    }
    guard let built = self.builtXCTestRun(key: key) else {
      try? fileManager.removeItem(at: destination)
      return .failure(.inspectorSetupFailed)
    }
    return .success(built)
  }

  /// `<키>/Products` 의 `.xctestrun` 이 정확히 하나면 그것. 폴더가 있는데 0개·여럿이면 그 폴더를 지우고 nil (다시 빌드).
  private func builtXCTestRun(key: String) -> URL? {
    let folder = self.root.appending(path: key, directoryHint: .isDirectory)
    let products = folder.appending(path: "Products", directoryHint: .isDirectory)
    guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) else { return nil }
    let runs = (try? FileManager.default.contentsOfDirectory(at: products, includingPropertiesForKeys: nil))?
      .filter { $0.pathExtension == "xctestrun" } ?? []
    guard runs.count == 1, let run = runs.first else {
      try? FileManager.default.removeItem(at: folder)
      return nil
    }
    return run
  }

  /// 이 캐시가 빌드 중이 아닌 `*.partial-*` 를 지운다 (앱이 빌드 중에 끝나 남은 것).
  private func removeStalePartials() {
    for name in self.entries() where name.contains(".partial-") && !self.activePartials.contains(name) {
      try? FileManager.default.removeItem(at: self.root.appending(path: name, directoryHint: .isDirectory))
    }
  }

  /// `keeping` 밖의 다른 빌드 키 폴더를 지운다 (옛 Xcode·옛 소스의 빌드). 빌드 중인 partial 은 두고 남은 partial 은 지운다.
  private func removeUnusedBuilds(keeping: Set<String>) {
    for name in self.entries() where !keeping.contains(name) && !self.activePartials.contains(name) {
      try? FileManager.default.removeItem(at: self.root.appending(path: name, directoryHint: .isDirectory))
    }
  }

  private func entries() -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: self.root.path(percentEncoded: false))) ?? []
  }

  /// xcodebuild 를 시작하지 못함 → Xcode 문제, 취소 → `.cancelled`, 시간 초과·그 밖 → 준비 실패.
  static func mapBuildError(_ error: CommandError) -> ScreenLayoutError {
    switch error {
    case .launchFailed: .xcodeUnavailable
    case .cancelled: .cancelled
    case .timedOut: .inspectorSetupFailed
    }
  }
}
