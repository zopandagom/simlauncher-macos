import Core
import DevEnvironmentInterface
import Foundation
import ScreenLayoutInterface
import SimulatorInterface
import Synchronization

/// iOS 레이아웃 한 번 읽기 (설계 4절). 준비는 기기 큐 밖(풀이 합류·`.preparing`), 요청·스크린샷만 기기 큐 안.
/// Xcode 확인 → 기기 확인 → 풀에서 세션(필요하면 `.preparing`) → `.reading` → [큐] 실행 중 앱 → 러너 요청 → 스크린샷 → 변환.
/// 응답 전에 세션이 끝나면(유휴 종료 순간 등) Xcode 확인부터 한 번 다시 읽는다 (끄는 중·앱 종료 중 제외). 다시 읽기는 읽기 한 번에 한 번뿐.
struct IOSLayoutReader: Sendable {
  let simulator: any SimulatorClient
  let devEnvironment: any DevEnvironmentClient
  let pool: LayoutRunnerPool
  let queue: KeyedSerialQueue<VirtualDevice.ID>
  let timing: IOSLayoutTiming

  func read(
    _ id: VirtualDevice.ID,
    onPhase: @escaping @Sendable (LayoutReadPhase) async -> Void
  ) async throws(ScreenLayoutError) -> LayoutSnapshot {
    // 다시 읽을 때 다른 읽기가 이미 새 러너를 준비해 `.preparing` 없이 세션을 얻으면 `.reading` 을 거듭 보내지 않는다.
    let phases = PhaseDeduplicator(onPhase)
    if case let .snapshot(snapshot) = try await self.readRound(id, onPhase: { await phases.send($0) }) {
      return snapshot
    }
    if let error = await self.pool.sessionEndedError(id) {
      throw error
    }
    if case let .snapshot(snapshot) = try await self.readRound(id, onPhase: { await phases.send($0) }) {
      return snapshot
    }
    throw await self.pool.lostSessionError(id)
  }

  /// 한 라운드: Xcode 확인부터 큐 안 요청까지. 각 라운드는 따로 큐 차례에 든다 (사이에 같은 기기의 다른 읽기가 끼어도 된다).
  /// 다시 읽는 라운드도 Xcode 를 다시 확인한다 (다른 읽기가 Xcode 를 바꿔 멈춘 경우 새 Xcode 로 준비하고, 옛 키로 다시 멈추게 하지 않는다).
  private func readRound(
    _ id: VirtualDevice.ID,
    onPhase: @escaping @Sendable (LayoutReadPhase) async -> Void
  ) async throws(ScreenLayoutError) -> ReadOnceResult {
    guard let xcode = await self.devEnvironment.selectedXcode() else { throw .xcodeUnavailable }
    guard !Task.isCancelled else { throw .cancelled }
    guard LayoutRunnerCommands.isUDID(id.rawValue) else { throw .deviceNotFound }
    let device = try await self.bootedDevice(id)
    let session = try await self.pool.session(for: id, xcode: xcode) { await onPhase(.preparing) }
    guard !Task.isCancelled else { throw .cancelled }
    await onPhase(.reading)
    let deviceName = device.name
    return try await self.queue.run(id) { () async throws(ScreenLayoutError) -> ReadOnceResult in
      try await self.readOnce(session: session, deviceName: deviceName)
    }
  }

  /// 목록에서 그 기기: 없으면 `.deviceNotFound`, 쓸 수 없으면 `.deviceUnavailable`, 켜져 있지 않으면 `.deviceNotBooted`.
  private func bootedDevice(_ id: VirtualDevice.ID) async throws(ScreenLayoutError) -> VirtualDevice {
    let inventory: DeviceInventory
    do throws(SimulatorError) {
      inventory = try await self.simulator.fetchInventory()
    } catch {
      throw Self.mapSimulatorError(error)
    }
    guard let device = inventory.devices.first(where: { $0.id == id }) else { throw .deviceNotFound }
    guard device.availability == .available else { throw .deviceUnavailable }
    guard device.state == .booted else { throw .deviceNotBooted }
    return device
  }

  private enum ReadOnceResult: Sendable {
    case snapshot(LayoutSnapshot)
    /// 응답 전에 세션이 끝났다 (스크린샷을 찍지 않았다).
    case sessionEnded
  }

  private func readOnce(
    session: LayoutRunnerPool.Session,
    deviceName: String
  ) async throws(ScreenLayoutError) -> ReadOnceResult {
    let running: [AppBundleID]
    do throws(SimulatorError) {
      running = try await self.simulator.runningApplications(on: session.deviceID)
    } catch {
      throw Self.mapSimulatorError(error)
    }
    let candidates = running.map(\.rawValue).filter { $0 != IOSLayoutRunner.appBundleID }
    let result = try await self.pool.request(
      .snapshot(bundleIDs: candidates, settle: self.timing.settleSeconds),
      to: session
    )
    guard case let .response(response) = result else { return .sessionEnded }
    let snapshot = try Self.snapshot(from: response)
    let png = try await self.screenshot(session.deviceID)
    guard let size = Self.pngSize(png) else { throw .unreadable }
    let nodes = try IOSLayoutConversion.nodes(from: snapshot.nodes, scale: session.scale)
    return .snapshot(LayoutSnapshot(
      deviceName: deviceName,
      capturedAt: Date(),
      screenshotPNG: png,
      pixelSize: size,
      unit: .pt,
      pixelsPerUnit: session.scale,
      nodes: nodes,
      appIdentifier: IOSLayoutConversion.appIdentifier(apps: snapshot.apps, system: snapshot.system),
      isSystemScreen: snapshot.system
    ))
  }

  /// 임시 파일에 찍어 메모리로 읽고, 성공·실패와 관계없이 곧바로 지운다.
  private func screenshot(_ id: VirtualDevice.ID) async throws(ScreenLayoutError) -> Data {
    let file = FileManager.default.temporaryDirectory
      .appending(path: "SimLauncher-Layout-\(UUID().uuidString).png", directoryHint: .notDirectory)
    defer { try? FileManager.default.removeItem(at: file) }
    do throws(SimulatorError) {
      try await self.simulator.screenshot(on: id, to: file)
    } catch {
      throw Self.mapSimulatorError(error)
    }
    guard let data = try? Data(contentsOf: file) else { throw .unreadable }
    return data
  }

  // MARK: - 순수

  /// 러너 응답 → 스냅샷. 실패 값은 6.1 표대로, 노드가 넘쳤으면(`truncated`·상한 초과) `.unreadable`.
  static func snapshot(
    from response: LayoutRunnerProtocol.Response
  ) throws(ScreenLayoutError) -> LayoutRunnerProtocol.Snapshot {
    switch response {
    case let .snapshot(snapshot):
      guard !snapshot.truncated, snapshot.nodes.count <= LayoutRunnerProtocol.maxNodes else { throw .unreadable }
      return snapshot
    case let .failure(failure):
      throw self.mapRunnerFailure(failure)
    case .quit:
      throw .unreadable
    }
  }

  /// `developerToolsUnavailable`→`xcodeUnavailable`, 기기 없음·꺼짐은 그대로, 그 밖→`unreadable`.
  static func mapSimulatorError(_ error: SimulatorError) -> ScreenLayoutError {
    switch error {
    case .developerToolsUnavailable: .xcodeUnavailable
    case .deviceNotFound: .deviceNotFound
    case .deviceNotBooted: .deviceNotBooted
    default: .unreadable
    }
  }

  /// `notForeground`→`appNotInForeground`(읽는 동안 앞 앱이 사라졌다), 그 밖→`unreadable`.
  static func mapRunnerFailure(_ failure: LayoutRunnerProtocol.RunnerFailure) -> ScreenLayoutError {
    switch failure {
    case .notForeground: .appNotInForeground
    case .snapshotFailed, .badRequest, .unknownCommand: .unreadable
    }
  }

  /// PNG IHDR 의 너비·높이 (시그니처 8바이트, 16~24 바이트 big-endian). PNG 가 아니거나 짧거나 0 이면 nil.
  static func pngSize(_ data: Data) -> LayoutSize? {
    let bytes = [UInt8](data.prefix(24))
    let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    let header: [UInt8] = [0x49, 0x48, 0x44, 0x52]
    guard bytes.count == 24, Array(bytes[0 ..< 8]) == signature, Array(bytes[12 ..< 16]) == header else { return nil }
    let width = bytes[16 ..< 20].reduce(0) { $0 << 8 | Int($1) }
    let height = bytes[20 ..< 24].reduce(0) { $0 << 8 | Int($1) }
    guard width > 0, height > 0 else { return nil }
    return LayoutSize(width: width, height: height)
  }
}

/// 앞과 같은 단계는 다시 보내지 않는 `onPhase` 감싸개. 한 읽기 안에서 차례로만 불려 확인과 호출 사이 경합이 없다.
private final class PhaseDeduplicator: Sendable {
  private let last = Mutex<LayoutReadPhase?>(nil)
  private let onPhase: @Sendable (LayoutReadPhase) async -> Void

  init(_ onPhase: @escaping @Sendable (LayoutReadPhase) async -> Void) {
    self.onPhase = onPhase
  }

  func send(_ phase: LayoutReadPhase) async {
    let isNew = self.last.withLock { last in
      guard last != phase else { return false }
      last = phase
      return true
    }
    if isNew {
      await self.onPhase(phase)
    }
  }
}
