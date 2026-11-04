import AppLogInterface
import Core
import Foundation
import Observation

/// 기기별 앱 로그 창(iOS·Android 공용)의 Model. App 이 하나를 소유하고 모든 로그 창이 함께 쓴다.
/// 창(대상 `AppLogTarget`)마다 상태는 `DeviceLogWindow` 값이고, 세션 목록은 첫 창이 열릴 때 구독해 앱이 끝날 때까지 받는다.
/// 창을 닫으면 그 창의 줄 구독과 거르기만 끝난다 (Client 의 받기·앱은 계속된다).
/// 거르기(줄 맞춤과 강조 범위 계산)는 메인 밖(`CompiledLogFilter.filtered`)에서 하고, 창마다 한 줄로 차례를 지킨다: 전체 다시 거르기는 앞 작업을 취소하고
/// 새 토큰으로 시작하며, 새 줄 거르기는 돌고 있는 작업이 이어서 맡는다.
@MainActor
@Observable
public final class DeviceLogModel {
  /// 모든 세션 (시작 시각 순, 구독으로 채운다).
  public private(set) var sessions: [AppLogSessionSummary] = []
  public private(set) var windows: [AppLogTarget: DeviceLogWindow] = [:]
  /// 세션 목록 첫 알림을 받았다. 그 전에는 세션이 없다고 단정할 수 없어 창이 "로그가 없습니다" 를 보이지 않는다.
  /// 거짓으로 돌아가지 않는다 (세션 구독은 앱이 끝날 때까지).
  public private(set) var hasReceivedSessions = false

  @ObservationIgnored private let appLog: any AppLogClient
  @ObservationIgnored private var sessionsTask: Task<Void, Never>?
  @ObservationIgnored private var lineTasks: [AppLogTarget: Task<Void, Never>] = [:]
  @ObservationIgnored private var lineTokens: [AppLogTarget: Int] = [:]
  @ObservationIgnored private var filterTasks: [AppLogTarget: Task<Void, Never>] = [:]
  @ObservationIgnored private var filterTokens: [AppLogTarget: Int] = [:]

  public init(appLog: any AppLogClient) {
    self.appLog = appLog
  }

  // MARK: - 창 열기·닫기·세션 고르기

  /// 창이 열렸다: 대상의 가장 늦은 세션을 골라 줄을 받는다. 세션이 아직 없으면 세션 목록 알림이 고른다.
  public func windowAppeared(_ target: AppLogTarget) {
    self.startSessionsIfNeeded()
    self.windows[target, default: DeviceLogWindow()].open()
    self.select(DeviceLogSessionChoice.latest(of: target, in: self.sessions), in: target)
  }

  /// 창을 닫았다: 줄 구독·거르기를 끝내고 줄을 버린다. 필터·따라가기·지운 지점·다시 실행 상태는 남긴다.
  public func windowDisappeared(_ target: AppLogTarget) {
    self.stopReading(target)
    self.windows[target]?.close()
  }

  public func sessionSelected(_ id: AppLogSessionID, in target: AppLogTarget) {
    guard let window = self.windows[target], window.isOpen, window.selectedSessionID != id else { return }
    self.clearRelaunchFailure(in: target)
    self.select(id, in: target)
  }

  // MARK: - 필터

  public func conditionAdded(in target: AppLogTarget) {
    self.changeFilter(in: target) { $0.addCondition() }
  }

  public func conditionRemoved(_ id: Int, in target: AppLogTarget) {
    self.changeFilter(in: target) { $0.removeCondition(id) }
  }

  public func conditionTextChanged(_ id: Int, _ text: String, in target: AppLogTarget) {
    self.changeFilter(in: target) { $0.setText(text, of: id) }
  }

  public func conditionKindChanged(_ id: Int, _ kind: LogFilter.Kind, in target: AppLogTarget) {
    self.changeFilter(in: target) { $0.setKind(kind, of: id) }
  }

  public func conditionExclusionChanged(_ id: Int, _ isExcluded: Bool, in target: AppLogTarget) {
    self.changeFilter(in: target) { $0.setExcluded(isExcluded, of: id) }
  }

  public func caseSensitivityChanged(_ isCaseSensitive: Bool, in target: AppLogTarget) {
    self.changeFilter(in: target) { $0.setCaseSensitive(isCaseSensitive) }
  }

  // MARK: - 일시정지·따라가기·지우기

  /// 일시정지 ↔ 계속. 계속하면 멈춘 동안의 줄을 따라잡는다.
  public func pauseTapped(in target: AppLogTarget) {
    guard let isPaused = self.windows[target]?.isPaused else { return }
    if isPaused {
      self.windows[target]?.resume()
      self.scheduleFiltering(target, isFull: false)
    } else {
      self.windows[target]?.pause()
    }
  }

  public func followChanged(_ isFollowing: Bool, in target: AppLogTarget) {
    guard let current = self.windows[target]?.isFollowing, current != isFollowing else { return }
    self.windows[target]?.setFollowing(isFollowing)
  }

  /// 사용자가 스크롤해 맨 아래를 떠났다 → 따라가기 끔.
  public func scrolledAwayFromBottom(in target: AppLogTarget) {
    self.followChanged(false, in: target)
  }

  /// 사용자가 스크롤해 맨 아래에 닿았다 → 따라가기 켬.
  public func scrolledToBottom(in target: AppLogTarget) {
    self.followChanged(true, in: target)
  }

  public func clearTapped(in target: AppLogTarget) {
    guard self.windows[target]?.selectedSessionID != nil else { return }
    // 거르는 중인 결과에는 지운 줄이 들어 있다.
    self.cancelFiltering(target)
    self.windows[target]?.clear()
  }

  // MARK: - 다시 실행

  /// 끝난 세션의 앱을 같은 기기에서 다시 실행한다 (기기를 켜지 않는다). 성공하면 새 세션으로 옮긴다.
  /// 도는 동안 창을 닫아도 계속되고, 상태(`.running`)가 남아 다시 연 창에서 겹쳐 누르지 못한다.
  public func relaunchTapped(in target: AppLogTarget) async {
    guard let window = self.windows[target], window.relaunch != .running,
          let session = window.selectedSessionID,
          let summary = self.sessions.first(where: { $0.id == session }), summary.state != .receiving
    else { return }
    self.windows[target]?.setRelaunch(.running)
    do {
      let newSession = try await self.appLog.relaunch(session)
      self.windows[target]?.setRelaunch(.idle)
      // 세션 목록 알림보다 먼저 올 수 있다. 알림도 같은 앱의 더 늦은 세션으로 옮기므로 결과는 같다.
      if let window = self.windows[target], window.isOpen, window.selectedSessionID != newSession {
        self.select(newSession, in: target)
      }
    } catch {
      self.windows[target]?.setRelaunch(.failed(error))
    }
  }

  // MARK: - 세션 목록

  private func startSessionsIfNeeded() {
    guard self.sessionsTask == nil else { return }
    self.sessionsTask = Task { [weak self, appLog] in
      for await sessions in await appLog.sessionUpdates() {
        guard let self else { return }
        self.sessionsReceived(sessions)
      }
    }
  }

  private func sessionsReceived(_ sessions: [AppLogSessionSummary]) {
    if !self.hasReceivedSessions {
      self.hasReceivedSessions = true
    }
    self.sessions = sessions
    // 창 값을 붙잡은 채 바꾸면 줄 배열이 통째로 복사된다. 대상만 모은다.
    let openTargets = self.windows.compactMap { $0.value.isOpen ? $0.key : nil }
    for target in openTargets {
      let current = self.windows[target]?.selectedSessionID
      let next = DeviceLogSessionChoice.selection(current: current, of: target, in: sessions)
      guard next != current else { continue }
      self.clearRelaunchFailure(in: target)
      self.select(next, in: target)
    }
  }

  /// 다른 세션으로 옮기면 앞 세션의 다시 실행 실패 안내를 지운다 (도는 중이면 그 결과가 정한다).
  private func clearRelaunchFailure(in target: AppLogTarget) {
    if case .failed = self.windows[target]?.relaunch {
      self.windows[target]?.setRelaunch(.idle)
    }
  }

  // MARK: - 줄 받기

  private func select(_ session: AppLogSessionID?, in target: AppLogTarget) {
    self.stopReading(target)
    self.windows[target]?.select(session)
    guard let session else { return }
    let token = self.lineTokens[target, default: 0]
    self.lineTasks[target] = Task { [weak self, appLog] in
      for await update in await appLog.lineUpdates(of: session) {
        guard let self, self.lineTokens[target] == token else { return }
        self.lineUpdateReceived(update, in: target)
      }
    }
  }

  private func lineUpdateReceived(_ update: AppLogLineUpdate, in target: AppLogTarget) {
    if update.isSnapshot {
      self.windows[target]?.applySnapshot(update)
      self.scheduleFiltering(target, isFull: true)
    } else if self.windows[target]?.applyBatch(update) == true {
      self.scheduleFiltering(target, isFull: false)
    }
  }

  /// 줄 구독과 거르기를 끝낸다 (스트림이 끝나 Client 의 구독도 풀린다).
  private func stopReading(_ target: AppLogTarget) {
    self.lineTasks[target]?.cancel()
    self.lineTasks[target] = nil
    self.lineTokens[target, default: 0] += 1
    self.cancelFiltering(target)
  }

  // MARK: - 거르기

  private func changeFilter(in target: AppLogTarget, _ change: (inout LogFilter) -> Void) {
    guard self.windows[target] != nil else { return }
    if self.windows[target]?.changeFilter(change) == true {
      self.scheduleFiltering(target, isFull: true)
    }
  }

  /// 전체면 앞 작업을 취소하고 처음부터, 아니면 돌고 있는 작업이 끝 줄까지 이어 거르게 둔다 (없으면 시작).
  private func scheduleFiltering(_ target: AppLogTarget, isFull: Bool) {
    if isFull {
      self.cancelFiltering(target)
    } else if self.filterTasks[target] != nil {
      return
    }
    let token = self.filterTokens[target, default: 0]
    self.filterTasks[target] = Task { [weak self] in
      await self?.runFiltering(target, token: token, isFull: isFull)
    }
  }

  private func runFiltering(_ target: AppLogTarget, token: Int, isFull: Bool) async {
    var isFull = isFull
    while let job = self.windows[target]?.filterJob(isFull: isFull) {
      let result = await CompiledLogFilter.filtered(job.lines, by: job.filter)
      guard self.filterTokens[target] == token, !Task.isCancelled else { return }
      self.windows[target]?.applyFilterResult(result, of: job)
      isFull = false
    }
    if self.filterTokens[target] == token {
      self.filterTasks[target] = nil
    }
  }

  private func cancelFiltering(_ target: AppLogTarget) {
    self.filterTasks[target]?.cancel()
    self.filterTasks[target] = nil
    self.filterTokens[target, default: 0] += 1
  }
}
