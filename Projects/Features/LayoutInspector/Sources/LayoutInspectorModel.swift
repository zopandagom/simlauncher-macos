import Core
import Foundation
import Observation
import ScreenLayoutInterface

/// 기기별 화면 레이아웃 창(iOS·Android 공용)의 Model. App 이 하나를 소유하고 모든 레이아웃 창이 함께 쓴다.
/// 창(대상 `LayoutTarget`)마다 상태는 `LayoutInspectorWindow` 값이다. 창이 열리면 한 번 읽고, 다시 읽기는 "새로 고침" 때만 한다
/// (실시간 아님. 실패해도 자동으로 다시 시도하지 않는다). 창을 닫으면 읽기를 취소하고 창 값(스냅샷)을 버린다.
/// 읽기 번호(`tokens`)는 지우지 않고 늘리기만 해, 닫기 직전에 끝난 앞 읽기의 결과가 다시 연 창의 읽기와 번호가 같아지지 않는다.
@MainActor
@Observable
public final class LayoutInspectorModel {
  public private(set) var windows: [LayoutTarget: LayoutInspectorWindow] = [:]

  @ObservationIgnored private let screenLayout: any ScreenLayoutClient
  @ObservationIgnored private var tasks: [LayoutTarget: Task<Void, Never>] = [:]
  /// 창을 열 때 기기 이름을 묻는 Task (창을 닫으면 취소한다).
  @ObservationIgnored private var nameTasks: [LayoutTarget: Task<Void, Never>] = [:]
  /// 대상별 마지막으로 시작한(또는 닫으며 무효로 한) 읽기 번호.
  @ObservationIgnored private var tokens: [LayoutTarget: Int] = [:]

  public init(screenLayout: any ScreenLayoutClient) {
    self.screenLayout = screenLayout
  }

  // MARK: - 창 열기·닫기

  /// 창이 열렸다: 창 값을 만들고 읽으며, 첫 스냅샷 전 제목에 쓸 기기 이름도 함께 묻는다.
  /// 이미 창 값이 있으면(같은 창의 onAppear 가 다시 온 경우) 아무것도 하지 않는다.
  public func windowAppeared(_ target: LayoutTarget) {
    guard self.windows[target] == nil else { return }
    self.windows[target] = LayoutInspectorWindow()
    self.startReading(target)
    self.resolveDeviceName(target)
  }

  /// 창을 닫았다: 읽기를 취소하고 창 값(스냅샷)을 버린다. 늦게 끝난 결과는 번호가 달라 버려진다.
  public func windowDisappeared(_ target: LayoutTarget) {
    self.tasks[target]?.cancel()
    self.tasks[target] = nil
    self.nameTasks[target]?.cancel()
    self.nameTasks[target] = nil
    self.tokens[target, default: 0] += 1
    self.windows[target] = nil
  }

  // MARK: - 새로 고침

  /// "새로 고침"·"다시 시도". 창이 없거나 읽는 중이면 무시한다.
  public func refreshTapped(in target: LayoutTarget) {
    guard let window = self.windows[target], !window.isLoading else { return }
    self.startReading(target)
  }

  // MARK: - 고르기

  /// 캔버스 클릭(스크린샷 px). 점의 가장 안쪽 노드를 고르고, 빈 곳이면 고름을 푼다. 스냅샷이 없으면 무시한다.
  public func canvasClicked(at point: LayoutPoint, in target: LayoutTarget) {
    guard self.windows[target]?.snapshot != nil else { return }
    self.windows[target]?.canvasClicked(at: point)
  }

  /// "이 위치의 뷰" 목록에서 고르기. 지금 스택에 든 노드일 때만 바꾼다.
  public func stackNodeSelected(_ id: LayoutNode.ID, in target: LayoutTarget) {
    guard self.windows[target]?.pick?.stack.contains(id) == true else { return }
    self.windows[target]?.stackNodeSelected(id)
  }

  // MARK: - 읽기

  /// 기기 이름을 묻고 창에 넣는다. 창을 닫으면 취소하므로 닫은 뒤 늦게 온 이름은 버린다.
  private func resolveDeviceName(_ target: LayoutTarget) {
    self.nameTasks[target] = Task { [weak self, screenLayout] in
      let name = await screenLayout.deviceName(of: target)
      guard let self, !Task.isCancelled else { return }
      self.nameTasks[target] = nil
      guard let name else { return }
      self.windows[target]?.deviceNameResolved(name)
    }
  }

  private func startReading(_ target: LayoutTarget) {
    self.tokens[target, default: 0] += 1
    let token = self.tokens[target, default: 0]
    self.windows[target]?.beginReading()
    self.tasks[target] = Task { [weak self, screenLayout] in
      let result: Result<LayoutSnapshot, ScreenLayoutError>
      do throws(ScreenLayoutError) {
        let snapshot = try await screenLayout.snapshot(of: target) { @MainActor [weak self] phase in
          self?.phaseChanged(phase, in: target, token: token)
        }
        result = .success(snapshot)
      } catch {
        result = .failure(error)
      }
      self?.readFinished(result, in: target, token: token)
    }
  }

  private func phaseChanged(_ phase: LayoutReadPhase, in target: LayoutTarget, token: Int) {
    guard self.tokens[target] == token else { return }
    self.windows[target]?.phaseChanged(phase)
  }

  /// 번호가 같고 창이 있을 때만 적용한다. 번호가 같으면 이 읽기가 지금 Task 라 목록에서 뺀다.
  private func readFinished(_ result: Result<LayoutSnapshot, ScreenLayoutError>, in target: LayoutTarget, token: Int) {
    guard self.tokens[target] == token else { return }
    self.tasks[target] = nil
    guard self.windows[target] != nil else { return }
    switch result {
    case let .success(snapshot):
      self.windows[target]?.readSucceeded(snapshot)
    case let .failure(error):
      if let failure = LayoutInspectorFailure(error) {
        self.windows[target]?.readFailed(failure)
      } else {
        // 취소: 창을 닫은 경우는 번호가 이미 달라 여기 오지 않는다. 그 밖의 취소는 실패로 보이지 않고 읽기만 끝낸다.
        self.windows[target]?.readEnded()
      }
    }
  }
}
