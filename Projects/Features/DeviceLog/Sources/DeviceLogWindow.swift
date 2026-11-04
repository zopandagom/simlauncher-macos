import AppLogInterface
import Foundation

/// 로그 창 하나(대상 하나)의 상태: 고른 세션, 필터, 일시정지·따라가기, 받은 줄과 보이는 줄, 지운 지점, 다시 실행 상태,
/// 전체 다시 거르기 기다림.
/// 규칙만 담은 값이고, Client 구독과 메인 밖 거르기(`CompiledLogFilter.filtered`, 줄 맞춤과 강조 범위 계산)는 `DeviceLogModel` 이 한다.
/// 창을 닫으면 줄은 버리고(`close()`) 필터·따라가기·지운 지점·다시 실행 상태는 SimLauncher 가 켜져 있는 동안 남긴다.
public struct DeviceLogWindow: Sendable {
  public enum RelaunchState: Hashable, Sendable {
    case idle
    case running
    case failed(AppLogLaunchError)
  }

  /// 메인 밖에서 거를 줄 묶음 (`filterJob(isFull:)`). 결과는 `applyFilterResult(_:of:)` 로 돌려준다.
  struct FilterJob: Sendable {
    let sessionID: AppLogSessionID
    let lines: [AppLogLine]
    /// 이 번호까지 거른 것으로 본다.
    let through: Int
    /// 보이는 줄을 결과로 바꾼다 (아니면 끝에 붙인다).
    let isFull: Bool
    /// 결과 줄의 강조도 이 필터의 것이다.
    let filter: CompiledLogFilter
  }

  public private(set) var selectedSessionID: AppLogSessionID?
  public private(set) var filter = LogFilter()
  /// 지금 입력한 필터를 쓸 수 없는 이유. 있으면 보이는 줄은 마지막으로 쓸 수 있던 필터(`appliedFilter`)의 결과 그대로다.
  public private(set) var filterProblem: LogFilterProblem?
  private(set) var appliedFilter = CompiledLogFilter(includes: [], excludes: [])
  public private(set) var isFollowing = true
  /// 일시정지 중이면 멈춘 지점(그때까지 받은 마지막 번호). 이 뒤의 줄은 보이는 줄에 넣지 않는다.
  public private(set) var pausedThrough: Int?
  /// 고른 세션에서 받은 줄 중 지운 지점 뒤이고 버퍼에 남은 것 (번호 순).
  public private(set) var lines: [AppLogLine] = []
  /// `lines` 중 필터에 맞아 표에 보이는 줄과 그 강조 (번호 순). 강조는 그 줄을 거른 필터의 것이다.
  public private(set) var visibleLines: [VisibleLogLine] = []
  /// 이 번호까지 필터를 거쳐 `visibleLines` 에 반영했다.
  public private(set) var filteredThrough = -1
  /// 이 번호까지 받았다 (지운 줄·버린 줄 포함). 중복을 거른다.
  public private(set) var receivedThrough = -1
  /// 버퍼가 차서 Client 가 지금까지 버린 앞 줄 수 (번호가 이보다 작은 줄은 없다).
  public private(set) var droppedCount = 0
  /// 세션마다 지운 지점 (이 번호까지 지웠다). 창을 닫았다 열어도 지운 줄은 다시 보이지 않는다.
  public private(set) var clearedThrough: [AppLogSessionID: Int] = [:]
  /// 일시정지한 뒤 들어온 줄 수.
  public private(set) var newWhilePaused = 0
  /// 보이는 줄을 통째로 바꿀 때마다 1 늘린다. 표는 이 값이 바뀌면 전부 다시 읽고, 아니면 앞 버림·끝 추가만 반영한다.
  public private(set) var displayGeneration = 0
  public private(set) var relaunch = RelaunchState.idle
  public private(set) var isOpen = false
  /// 전체 다시 거르기(스냅숏 뒤·필터 바꿈 뒤)를 요청했고 그 결과가 아직 적용되지 않았다. 그동안 보이는 줄은 앞 결과이거나 비어 있어
  /// "맞는 줄 없음" 안내와 빈 줄 수를 숨긴다. 결과를 버리는 경로는 모두 새 전체 거르기나 `resetLines` 로 이어져 갇히지 않는다.
  private(set) var isAwaitingFullFilter = false

  public init() {}

  public var isPaused: Bool {
    self.pausedThrough != nil
  }

  public var visibleCount: Int {
    self.visibleLines.count
  }

  public var totalCount: Int {
    self.lines.count
  }

  /// "필터에 맞는 줄이 없습니다" 를 보일 때: 거른 결과가 정말 비었다 (거르기를 기다리는 동안은 숨긴다).
  public var showsNoMatchingNotice: Bool {
    self.visibleLines.isEmpty && !self.lines.isEmpty && !self.isAwaitingFullFilter && !self.hasOnlyUnfilteredLines
  }

  /// 아래 줄 수 글자를 숨길 때: 보이는 줄이 없고 결과를 기다리는 중이다.
  /// 일시정지 중 받은 줄만 있을 때의 "보이는 0줄" 은 사실이라 숨기지 않는다.
  public var hidesLineCounts: Bool {
    self.visibleLines.isEmpty && (self.isAwaitingFullFilter || (!self.isPaused && self.hasOnlyUnfilteredLines))
  }

  /// 받은 줄이 있지만 아직 하나도 거르지 않았다 (0줄 스냅숏 뒤 첫 묶음, 일시정지 중 지운 뒤 받은 줄).
  /// 끝 줄만 보면 묶음마다 참이 되어 안내가 깜빡이므로 첫 줄을 본다.
  private var hasOnlyUnfilteredLines: Bool {
    self.lines.first.map { $0.index > self.filteredThrough } ?? false
  }

  /// 버퍼가 차서 버린 앞 줄 중 사용자가 지우지 않은 것의 수. 없으면 nil.
  public var discardedNotice: Int? {
    guard let session = self.selectedSessionID else { return nil }
    let notice = self.droppedCount - (self.clearedThrough[session, default: -1] + 1)
    return notice > 0 ? notice : nil
  }

  // MARK: - 열기·닫기·세션

  mutating func open() {
    self.isOpen = true
  }

  /// 창을 닫는다: 줄을 버리고 고른 세션과 일시정지도 놓는다 (다시 열면 가장 늦은 세션을 받는 대로 보인다).
  mutating func close() {
    self.isOpen = false
    self.selectedSessionID = nil
    self.pausedThrough = nil
    self.resetLines(cleared: -1)
  }

  /// 세션을 고른다 (nil 이면 빈 화면). 줄은 비우고 Model 이 새로 구독한다.
  mutating func select(_ session: AppLogSessionID?) {
    self.selectedSessionID = session
    self.resetLines(cleared: session.map { self.clearedThrough[$0, default: -1] } ?? -1)
  }

  mutating func setRelaunch(_ state: RelaunchState) {
    self.relaunch = state
  }

  // MARK: - 받은 줄

  /// 구독의 첫 알림(버퍼 전체). 지운 지점 뒤만 남긴다. 일시정지 중이면 멈춘 지점을 스냅숏 끝으로 옮긴다 (연 창에 그때까지가 보이게).
  /// 그 뒤 Model 이 전체 다시 거르기를 한다.
  mutating func applySnapshot(_ update: AppLogLineUpdate) {
    guard let session = self.selectedSessionID else { return }
    let cleared = self.clearedThrough[session, default: -1]
    self.resetLines(cleared: cleared)
    self.droppedCount = update.droppedCount
    self.lines = update.lines.filter { $0.index > cleared && $0.index >= update.droppedCount }
    self.receivedThrough = max(cleared, update.lines.last?.index ?? cleared)
    if self.isPaused {
      self.pausedThrough = self.receivedThrough
    }
    // 닫힌 창은 거르기 결과가 오지 않는다 (`filterJob` 이 nil).
    self.isAwaitingFullFilter = self.isOpen
  }

  /// 새로 쌓인 줄 묶음. 버퍼에서 버린 줄은 앞에서 뺀다 (일시정지 중에는 보이는 줄은 그대로 두고 계속할 때 뺀다).
  /// 새 줄을 걸러야 하면(일시정지가 아니고 새 줄이 있으면) 참.
  mutating func applyBatch(_ update: AppLogLineUpdate) -> Bool {
    guard self.selectedSessionID != nil else { return false }
    let fresh = update.lines.filter { $0.index > self.receivedThrough }
    self.lines += fresh
    self.receivedThrough = fresh.last?.index ?? self.receivedThrough
    self.droppedCount = max(self.droppedCount, update.droppedCount)
    Self.dropFront(&self.lines, below: self.droppedCount, index: \.index)
    if self.isPaused {
      self.newWhilePaused += fresh.count
      return false
    }
    Self.dropFront(&self.visibleLines, below: self.droppedCount, index: \.index)
    return !fresh.isEmpty
  }

  // MARK: - 거르기

  /// 다음에 거를 묶음. 전체면 멈춘 지점까지의 모든 줄(일시정지가 아니면 전부), 아니면 아직 거르지 않은 끝 줄들
  /// (멈춘 지점까지). 거를 것이 없으면 nil (전체는 줄이 없어도 보이는 줄을 비우려고 돌려준다). 닫힌 창은 nil.
  func filterJob(isFull: Bool) -> FilterJob? {
    guard self.isOpen, let session = self.selectedSessionID else { return nil }
    let limit = self.pausedThrough ?? Int.max
    if isFull {
      let end = self.lines.firstIndex { $0.index > limit } ?? self.lines.endIndex
      let snapshot = Array(self.lines[..<end])
      return FilterJob(
        sessionID: session, lines: snapshot, through: snapshot.last?.index ?? self.filteredThrough, isFull: true,
        filter: self.appliedFilter
      )
    }
    // 끝 줄들은 보통 적다 (묶음 하나). 뒤에서부터 찾는다.
    var start = self.lines.endIndex
    while start > self.lines.startIndex, self.lines[start - 1].index > self.filteredThrough {
      start -= 1
    }
    let end = self.lines[start...].firstIndex { $0.index > limit } ?? self.lines.endIndex
    guard start < end else { return nil }
    let tail = Array(self.lines[start ..< end])
    return FilterJob(
      sessionID: session, lines: tail, through: tail.last?.index ?? self.filteredThrough, isFull: false,
      filter: self.appliedFilter
    )
  }

  mutating func applyFilterResult(_ result: [VisibleLogLine], of job: FilterJob) {
    guard job.sessionID == self.selectedSessionID else { return }
    let cleared = self.clearedThrough[job.sessionID, default: -1]
    // 거르는 동안 지웠거나 버린 줄은 넣지 않는다 (일시정지 중 버림은 계속할 때 뺀다).
    let floor = self.isPaused ? cleared + 1 : max(cleared + 1, self.droppedCount)
    if job.isFull {
      self.isAwaitingFullFilter = false
      self.visibleLines = result.filter { $0.index >= floor }
      self.filteredThrough = job.through
      self.displayGeneration += 1
    } else {
      let last = self.visibleLines.last?.index ?? Int.min
      self.visibleLines += result.filter { $0.index >= floor && $0.index > last }
      self.filteredThrough = max(self.filteredThrough, job.through)
    }
  }

  /// 필터 입력을 바꾼다. 쓸 수 있는 필터가 되어 다시 걸러야 하면 참. 정규식을 읽지 못하면 문제만 세우고 보이는 줄은 그대로다.
  mutating func changeFilter(_ change: (inout LogFilter) -> Void) -> Bool {
    var filter = self.filter
    change(&filter)
    guard filter != self.filter else { return false }
    self.filter = filter
    switch filter.compiled() {
    case let .success(compiled):
      self.filterProblem = nil
      self.appliedFilter = compiled
      // 닫힌 창·세션 없는 창은 거르기 결과가 오지 않는다 (`filterJob` 이 nil).
      if self.isOpen, self.selectedSessionID != nil {
        self.isAwaitingFullFilter = true
      }
      return true
    case let .failure(problem):
      self.filterProblem = problem
      return false
    }
  }

  // MARK: - 일시정지·따라가기·지우기

  mutating func pause() {
    guard !self.isPaused else { return }
    self.pausedThrough = self.receivedThrough
    self.newWhilePaused = 0
  }

  /// 계속한다: 일시정지 중 버린 줄을 보이는 줄에서 빼고, Model 이 멈춘 뒤의 줄을 거른다.
  mutating func resume() {
    guard self.isPaused else { return }
    self.pausedThrough = nil
    self.newWhilePaused = 0
    Self.dropFront(&self.visibleLines, below: self.droppedCount, index: \.index)
  }

  mutating func setFollowing(_ isFollowing: Bool) {
    self.isFollowing = isFollowing
  }

  /// 지금까지 받은 줄을 지운다. 이 세션은 창을 닫았다 열어도 이 뒤의 줄만 보인다.
  mutating func clear() {
    guard let session = self.selectedSessionID else { return }
    let cleared = max(self.receivedThrough, self.clearedThrough[session, default: -1])
    self.clearedThrough[session] = cleared
    let received = self.receivedThrough
    let dropped = self.droppedCount
    self.resetLines(cleared: cleared)
    self.receivedThrough = received
    self.droppedCount = dropped
    if self.isPaused {
      self.pausedThrough = cleared
    }
  }

  // MARK: - 도움

  private mutating func resetLines(cleared: Int) {
    self.lines = []
    self.visibleLines = []
    self.filteredThrough = cleared
    self.receivedThrough = cleared
    self.droppedCount = 0
    self.newWhilePaused = 0
    self.isAwaitingFullFilter = false
    if self.isPaused {
      self.pausedThrough = cleared
    }
    self.displayGeneration += 1
  }

  /// 번호가 `bound` 보다 작은 앞 줄을 뺀다. 묶음마다(최대 초당 10번) 한 번이라 원소 이동으로 충분하다 (5만 줄에서 측정).
  private static func dropFront<Line>(_ lines: inout [Line], below bound: Int, index: KeyPath<Line, Int>) {
    guard let first = lines.first, first[keyPath: index] < bound else { return }
    let count = lines.firstIndex { $0[keyPath: index] >= bound } ?? lines.endIndex
    lines.removeFirst(count)
  }
}
