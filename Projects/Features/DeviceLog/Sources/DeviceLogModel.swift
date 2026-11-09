import AppLogInterface
import Core
import Foundation
import Observation
import PreferencesInterface

/// 기기별 앱 로그 창(iOS·Android 공용)의 Model. App 이 하나를 소유하고 모든 로그 창이 함께 쓴다.
/// 창(대상 `AppLogTarget`)마다 상태는 `DeviceLogWindow` 값이고, 세션 목록은 첫 창이 열릴 때 구독해 앱이 끝날 때까지 받는다.
/// 창을 닫으면 그 창의 줄 구독과 거르기만 끝난다 (Client 의 받기·앱은 계속된다).
/// 저장된 필터 목록(`savedFilters`)은 모든 창·기기·플랫폼이 함께 쓰는 목록 하나이고, Preferences 에서 창이 열릴 때와
/// 저장된 필터 동작(불러오기·"지금 필터 저장…"·저장·바꾸기·삭제) 때만 다시 읽는다. 새 창은 빈 필터로 시작한다.
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
  /// 저장된 필터 목록과 잠금 여부 (모든 창 공용).
  public private(set) var savedFilters = SavedLogFilterSetting.empty

  @ObservationIgnored private let appLog: any AppLogClient
  @ObservationIgnored private let preferences: any PreferencesClient
  @ObservationIgnored private var sessionsTask: Task<Void, Never>?
  @ObservationIgnored private var lineTasks: [AppLogTarget: Task<Void, Never>] = [:]
  @ObservationIgnored private var lineTokens: [AppLogTarget: Int] = [:]
  @ObservationIgnored private var filterTasks: [AppLogTarget: Task<Void, Never>] = [:]
  @ObservationIgnored private var filterTokens: [AppLogTarget: Int] = [:]

  public init(appLog: any AppLogClient, preferences: any PreferencesClient) {
    self.appLog = appLog
    self.preferences = preferences
  }

  // MARK: - 창 열기·닫기·세션 고르기

  /// 창이 열렸다: 대상의 가장 늦은 세션을 골라 줄을 받는다. 세션이 아직 없으면 세션 목록 알림이 고른다.
  public func windowAppeared(_ target: AppLogTarget) {
    self.startSessionsIfNeeded()
    self.windows[target, default: DeviceLogWindow()].open()
    self.select(DeviceLogSessionChoice.latest(of: target, in: self.sessions), in: target)
    self.reloadSavedFilters()
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

  // MARK: - 저장된 필터

  /// 저장된 필터를 불러온다: 그 창 필터를 통째로 바꾼다. 읽을 수 없는 정규식이면 `changeFilter` 가 문제를 세우고
  /// 보이는 줄은 앞 필터 결과 그대로다.
  public func savedFilterSelected(_ filter: SavedLogFilter, in target: AppLogTarget) {
    self.changeFilter(in: target) { $0.load(filter) }
    self.reloadSavedFilters()
  }

  /// "지금 필터 저장…": 목록을 다시 읽고 막힘 이유가 없으면 빈 이름 시트를 연다 (50개여도 연다. 같은 이름 덮어쓰기는 된다).
  public func saveFilterTapped(in target: AppLogTarget) {
    guard let window = self.windows[target], window.saveDraft == nil else { return }
    self.reloadSavedFilters()
    guard self.saveBlock(for: target) == nil else { return }
    self.windows[target]?.beginSave()
  }

  public func saveNameChanged(_ name: String, in target: AppLogTarget) {
    guard self.windows[target]?.saveDraft?.step == .naming else { return }
    self.windows[target]?.setSaveName(name)
  }

  /// 시트의 "저장". 같은 이름이 있으면 바꿀지 묻는다. 막혔으면(잠김·50개 등) 부르지 않고 시트가 이유를 보인다.
  public func saveConfirmed(in target: AppLogTarget) {
    guard let draft = self.windows[target]?.saveDraft, draft.step == .naming, draft.nameProblem == nil else { return }
    self.reloadSavedFilters()
    guard self.saveBlock(for: target) == nil,
          !LogFilterSaveDraft.isOverLimit(name: draft.name, saved: self.savedFilters)
    else { return }
    self.store(name: draft.name, replacingSameName: false, in: target)
  }

  /// 같은 이름 확인의 "바꾸기": 그 자리를 지금 창 필터와 새로 입력한 이름 표기로 덮어쓴다.
  public func replaceConfirmed(in target: AppLogTarget) {
    guard let draft = self.windows[target]?.saveDraft, case .confirmingReplace = draft.step else { return }
    self.store(name: draft.name, replacingSameName: true, in: target)
  }

  /// 같은 이름 확인의 "취소": 이름을 둔 채 이름 입력으로 돌아간다.
  public func replaceCancelled(in target: AppLogTarget) {
    guard let draft = self.windows[target]?.saveDraft, case .confirmingReplace = draft.step else { return }
    self.windows[target]?.backToNaming()
  }

  /// 시트의 "취소": 저장하지 않고 시트를 닫는다.
  public func saveCancelled(in target: AppLogTarget) {
    guard self.windows[target]?.saveDraft != nil else { return }
    self.windows[target]?.endSave()
  }

  /// 같은 이름(대소문자 무시)의 저장된 필터를 지운다. 잠겼으면 부르지 않고, 그새 잠겼으면 다시 읽어 잠금으로 보인다.
  public func savedFilterDeleteTapped(_ name: String) {
    guard !self.savedFilters.isLocked else { return }
    do {
      self.savedFilters = try self.preferences.removeLogFilter(named: name)
    } catch {
      self.reloadSavedFilters()
    }
  }

  private func reloadSavedFilters() {
    self.savedFilters = self.preferences.savedLogFilters()
  }

  /// 창 필터를 이 이름으로 저장한다. 성공하면 시트를 닫고, 같은 이름이면 저장된 표기로 바꿀지 묻고,
  /// 잠김·50개면 다시 읽은 목록으로 이름 입력에 돌아간다 (시트가 이유를 보이고 저장 버튼을 끈다).
  private func store(name: String, replacingSameName: Bool, in target: AppLogTarget) {
    guard let window = self.windows[target],
          let filter = SavedLogFilter(
            name: name, conditions: window.filter.savedConditions(), isCaseSensitive: window.filter.isCaseSensitive
          )
    else { return }
    do throws(PreferencesError) {
      self.savedFilters = try self.preferences.saveLogFilter(filter, replacingSameName: replacingSameName)
      self.windows[target]?.endSave()
    } catch {
      self.reloadSavedFilters()
      switch error {
      case .duplicate:
        let existing = self.savedFilters.filters.first { SavedLogFilter.isSameName($0.name, filter.name) }
        self.windows[target]?.askReplace(existingName: existing?.name ?? filter.name)
      case .locked, .limitReached:
        self.windows[target]?.backToNaming()
      }
    }
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

  /// 끝난 세션의 앱을 같은 기기에서 다시 실행한다 (기기를 켜지 않는다). 성공하면 새 세션으로 옮긴다
  /// (창이 열려 있고 아직 다시 실행한 세션을 보고 있을 때만).
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
      // 알림이 먼저 오면 같은 앱의 새 세션이라 알림이 옮기고(선택이 이미 newSession), 결과가 먼저 오면 여기서 고른다
      // (그 뒤 그 세션이 아직 없는 알림은 그대로 둔다). 도는 동안 사용자가 다른 세션을 골랐으면 덮지 않는다.
      if let window = self.windows[target], window.isOpen, window.selectedSessionID == session {
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
    // 앞 목록: 이번 알림에서 새로 생긴 세션과 정리로 빠진 세션을 가린다 (`DeviceLogSessionChoice.selection`).
    let previous = Set(self.sessions.map(\.id))
    self.sessions = sessions
    // 창 값을 붙잡은 채 바꾸면 줄 배열이 통째로 복사된다. 대상만 모은다.
    let openTargets = self.windows.compactMap { $0.value.isOpen ? $0.key : nil }
    for target in openTargets {
      let current = self.windows[target]?.selectedSessionID
      let next = DeviceLogSessionChoice.selection(
        current: current, of: target, previous: previous, in: sessions
      )
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
