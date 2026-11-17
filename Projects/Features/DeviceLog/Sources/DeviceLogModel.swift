import AppLogInterface
import Core
import Foundation
import Observation
import PreferencesInterface
import WorkspaceInterface

/// 기기별 앱 로그 창(iOS·Android 공용)의 Model. App 이 하나를 소유하고 모든 로그 창이 함께 쓴다.
/// 창(대상 `AppLogTarget`)마다 상태는 `DeviceLogWindow` 값이고, 세션 목록은 첫 창이 열릴 때 구독해 앱이 끝날 때까지 받는다.
/// 창을 닫으면 그 창의 줄 구독과 거르기만 끝난다 (Client 의 받기·앱은 계속된다).
/// 저장된 필터 목록(`savedFilters`)은 모든 창·기기·플랫폼이 함께 쓰는 목록 하나이고, Preferences 에서 창이 열릴 때와
/// 저장된 필터 동작(불러오기·"지금 필터 저장…"·저장·바꾸기·삭제) 때만 다시 읽는다. 새 창은 빈 필터로 시작한다.
/// 거르기(줄 맞춤과 강조 범위 계산)는 메인 밖(`CompiledLogFilter.filtered`)에서 하고, 창마다 한 줄로 차례를 지킨다: 전체 다시 거르기는 앞 작업을 취소하고
/// 새 토큰으로 시작하며, 새 줄 거르기는 돌고 있는 작업이 이어서 맡는다.
/// 아래 줄 "복사"·"저장…" 은 누른 순간의 보이는 줄·머리말 값을 스냅숏(`LogExportSnapshot`)으로 잡고, 글은 메인 밖에서 만들어
/// Workspace Client 로 클립보드·고른 파일에 쓴다. 창마다 내보내기 토큰을 두어 창을 닫거나 새 내보내기를 시작하면 앞 결과를 버린다.
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
  @ObservationIgnored private let workspace: any WorkspaceClient
  @ObservationIgnored private let simLauncherVersion: String?
  @ObservationIgnored private let now: @Sendable () -> Date
  @ObservationIgnored private let timeZone: TimeZone
  @ObservationIgnored private let copiedFeedbackDuration: Duration
  @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
  @ObservationIgnored private let makeExportText: @Sendable (LogExportSnapshot, TimeZone) async -> String
  @ObservationIgnored private var exportTokens: [AppLogTarget: Int] = [:]
  @ObservationIgnored private var pendingSaves: [AppLogTarget: LogExportSnapshot] = [:]
  @ObservationIgnored private var copiedResetTasks: [AppLogTarget: Task<Void, Never>] = [:]

  /// `makeExportText`: 복사·저장할 글 만들기(메인 밖). 테스트가 글을 만드는 동안을 붙잡으려고 바꾼다.
  init(
    appLog: any AppLogClient,
    preferences: any PreferencesClient,
    workspace: any WorkspaceClient,
    simLauncherVersion: String?,
    now: @escaping @Sendable () -> Date,
    timeZone: TimeZone,
    copiedFeedbackDuration: Duration,
    sleep: @escaping @Sendable (Duration) async throws -> Void,
    makeExportText: @escaping @Sendable (LogExportSnapshot, TimeZone) async -> String
  ) {
    self.appLog = appLog
    self.preferences = preferences
    self.workspace = workspace
    self.simLauncherVersion = simLauncherVersion
    self.now = now
    self.timeZone = timeZone
    self.copiedFeedbackDuration = copiedFeedbackDuration
    self.sleep = sleep
    self.makeExportText = makeExportText
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
  /// 진행 중인 내보내기의 결과도 버린다 (만드는 중인 글은 쓰지 않고, 이미 시작한 쓰기는 끝까지 가지만 보이지 않는다).
  public func windowDisappeared(_ target: AppLogTarget) {
    self.stopReading(target)
    self.endExport(in: target)
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

public extension DeviceLogModel {
  /// - Parameters:
  ///   - simLauncherVersion: 내보낼 글 머리말의 SimLauncher 버전 ("1.3.0 (45)"). 모르면 nil.
  ///   - now·timeZone: 머리말 "내보낸 시각" 과 저장 파일 이름의 시각.
  ///   - copiedFeedbackDuration·sleep: "복사됨" 을 보이는 시간과 그 기다리기 (테스트가 바꾼다).
  convenience init(
    appLog: any AppLogClient,
    preferences: any PreferencesClient,
    workspace: any WorkspaceClient,
    simLauncherVersion: String?,
    now: @escaping @Sendable () -> Date = { Date() },
    timeZone: TimeZone = .current,
    copiedFeedbackDuration: Duration = .seconds(2),
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.init(
      appLog: appLog,
      preferences: preferences,
      workspace: workspace,
      simLauncherVersion: simLauncherVersion,
      now: now,
      timeZone: timeZone,
      copiedFeedbackDuration: copiedFeedbackDuration,
      sleep: sleep,
      makeExportText: { await LogExportText.make($0, timeZone: $1) }
    )
  }
}

// MARK: - 일시정지·따라가기·지우기·다시 실행

// 클래스 본문 길이 상한(type_body_length) 때문에 같은 파일의 extension 에 둔다 (상태·private 소유물을 바꾼다).
public extension DeviceLogModel {
  // MARK: - 일시정지·따라가기·지우기

  /// 일시정지 ↔ 계속. 계속하면 멈춘 동안의 줄을 따라잡는다.
  func pauseTapped(in target: AppLogTarget) {
    guard let isPaused = self.windows[target]?.isPaused else { return }
    if isPaused {
      self.windows[target]?.resume()
      self.scheduleFiltering(target, isFull: false)
    } else {
      self.windows[target]?.pause()
    }
  }

  func followChanged(_ isFollowing: Bool, in target: AppLogTarget) {
    guard let current = self.windows[target]?.isFollowing, current != isFollowing else { return }
    self.windows[target]?.setFollowing(isFollowing)
  }

  /// 사용자가 스크롤해 맨 아래를 떠났다 → 따라가기 끔.
  func scrolledAwayFromBottom(in target: AppLogTarget) {
    self.followChanged(false, in: target)
  }

  /// 사용자가 스크롤해 맨 아래에 닿았다 → 따라가기 켬.
  func scrolledToBottom(in target: AppLogTarget) {
    self.followChanged(true, in: target)
  }

  func clearTapped(in target: AppLogTarget) {
    guard self.windows[target]?.selectedSessionID != nil else { return }
    // 거르는 중인 결과에는 지운 줄이 들어 있다.
    self.cancelFiltering(target)
    self.windows[target]?.clear()
  }

  // MARK: - 다시 실행

  /// 끝난 세션의 앱을 같은 기기에서 다시 실행한다 (기기를 켜지 않는다). 성공하면 새 세션으로 옮긴다
  /// (창이 열려 있고 아직 다시 실행한 세션을 보고 있을 때만).
  /// 도는 동안 창을 닫아도 계속되고, 상태(`.running`)가 남아 다시 연 창에서 겹쳐 누르지 못한다.
  func relaunchTapped(in target: AppLogTarget) async {
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
}

// MARK: - 내보내기 ("복사"·"저장…")

// 상태(`windows`)와 private 소유물을 바꾸므로 같은 파일에 둔다.
public extension DeviceLogModel {
  /// "복사": 누른 순간의 보이는 줄로 글을 만들어(메인 밖) 클립보드에 쓴다. 성공하면 잠시 "복사됨".
  /// 글을 만드는 동안 창을 닫거나 다른 내보내기가 시작되면 클립보드에 쓰지 않는다.
  func copyTapped(in target: AppLogTarget) async {
    guard let snapshot = self.beginExport(in: target) else { return }
    let token = self.exportTokens[target, default: 0]
    self.windows[target]?.setExport(.copying)
    let text = await self.makeExportText(snapshot, self.timeZone)
    guard self.exportTokens[target] == token, self.windows[target]?.isOpen == true else { return }
    do throws(WorkspaceExportError) {
      try await self.workspace.copyToClipboard(text)
    } catch {
      if self.exportTokens[target] == token {
        self.windows[target]?.setExport(.failed(.copy(error)))
      }
      return
    }
    guard self.exportTokens[target] == token else { return }
    self.windows[target]?.setExport(.copied)
    self.copiedResetTasks[target] = Task { [weak self, sleep = self.sleep, duration = self.copiedFeedbackDuration] in
      do {
        try await sleep(duration)
      } catch {
        return
      }
      guard let self, self.exportTokens[target] == token, self.windows[target]?.export == .copied else { return }
      self.windows[target]?.setExport(.idle)
    }
  }

  /// "저장…": 누른 순간의 값을 잡아 두고 저장 위치 고르기로 간다 (View 가 이 단계를 보고 저장 패널을 띄운다).
  func saveTapped(in target: AppLogTarget) {
    guard let snapshot = self.beginExport(in: target) else { return }
    let request = self.exportTokens[target, default: 0]
    self.pendingSaves[target] = snapshot
    let name = LogExportFileName.make(
      appName: snapshot.session.appName,
      deviceName: snapshot.session.deviceName,
      date: snapshot.exportedAt,
      timeZone: self.timeZone
    )
    self.windows[target]?.setExport(.choosingLocation(suggestedFileName: name, request: request))
  }

  /// 저장 패널에서 취소했다. 다른 요청의 결과면 무시한다.
  func saveLocationCancelled(request: Int, in target: AppLogTarget) {
    guard self.isChoosingLocation(request: request, in: target) else { return }
    self.pendingSaves[target] = nil
    self.windows[target]?.setExport(.idle)
  }

  /// 저장 패널에서 위치를 골랐다 (덮어쓰기는 패널이 확인했다): 잡아 둔 값으로 글을 만들어(메인 밖) 그 파일에 쓴다.
  /// 다른 요청의 결과이거나 그새 창을 닫았으면 쓰지 않는다.
  func saveLocationChosen(_ file: URL, request: Int, in target: AppLogTarget) async {
    guard self.isChoosingLocation(request: request, in: target),
          let snapshot = self.pendingSaves.removeValue(forKey: target)
    else { return }
    let token = self.exportTokens[target, default: 0]
    self.windows[target]?.setExport(.saving)
    let text = await self.makeExportText(snapshot, self.timeZone)
    guard self.exportTokens[target] == token else { return }
    do throws(WorkspaceExportError) {
      try await self.workspace.writeTextFile(text, to: file)
    } catch {
      if self.exportTokens[target] == token {
        self.windows[target]?.setExport(.failed(.save(error)))
      }
      return
    }
    if self.exportTokens[target] == token {
      self.windows[target]?.setExport(.saved(file))
    }
  }

  /// "Finder 에서 보기": 저장한 파일을 Finder 에서 고른다. 파일이 없으면 이유를 보인다.
  func revealSavedFileTapped(in target: AppLogTarget) async {
    guard case let .saved(file) = self.windows[target]?.export else { return }
    let token = self.exportTokens[target, default: 0]
    do throws(WorkspaceError) {
      try await self.workspace.revealInFinder(file)
    } catch {
      if self.exportTokens[target] == token, self.windows[target]?.export == .saved(file) {
        self.windows[target]?.setExport(.failed(.revealedFileMissing))
      }
    }
  }

  /// 내보낼 수 있으면 토큰을 올리고 "복사됨" 되돌리기를 멈춘 뒤 지금 값을 잡는다. 없으면 nil (아무것도 바꾸지 않는다).
  private func beginExport(in target: AppLogTarget) -> LogExportSnapshot? {
    guard let window = self.windows[target], window.canExport, !window.isExporting,
          let session = self.selectedSession(for: target)
    else { return nil }
    self.endExport(in: target)
    return LogExportSnapshot(
      window: window, session: session, exportedAt: self.now(), simLauncherVersion: self.simLauncherVersion
    )
  }

  /// 진행 중인 내보내기의 결과를 버린다: 토큰을 올리고 "복사됨" 되돌리기와 잡아 둔 저장 값을 버린다.
  private func endExport(in target: AppLogTarget) {
    self.exportTokens[target, default: 0] += 1
    self.copiedResetTasks.removeValue(forKey: target)?.cancel()
    self.pendingSaves[target] = nil
  }

  private func isChoosingLocation(request: Int, in target: AppLogTarget) -> Bool {
    guard case let .choosingLocation(_, current) = self.windows[target]?.export else { return false }
    return current == request && self.exportTokens[target] == request
  }
}
