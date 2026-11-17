import AppLogInterface
import Foundation
import WorkspaceInterface

/// 로그 창 "복사"·"저장…" (보이는 줄 내보내기)의 단계. 창마다 하나이고 창을 닫으면 `.idle` 로 버린다.
/// 세션·필터를 바꾸거나 지우기·일시정지를 해도 그대로다 (복사한 글·저장한 파일은 그대로 사실이다).
public extension DeviceLogWindow {
  enum ExportPhase: Hashable, Sendable {
    case idle
    /// 글 만들기와 클립보드 쓰기.
    case copying
    /// "복사됨". Model 이 잠시 뒤 `.idle` 로 되돌린다.
    case copied
    /// 저장 패널이 떠 있다. `request` 는 이 요청의 번호이고, 패널 결과는 이 번호와 함께 돌아와야 받는다 (옛 패널 결과는 버린다).
    case choosingLocation(suggestedFileName: String, request: Int)
    /// 글 만들기와 파일 쓰기.
    case saving
    /// "저장했습니다: <파일 이름>" 과 "Finder 에서 보기".
    case saved(URL)
    case failed(LogExportFailure)
  }

  /// 내보내기 진행 중 (두 버튼 모두 끈다): 복사 중·저장 위치 고르는 중·저장 중.
  var isExporting: Bool {
    switch self.export {
    case .copying, .choosingLocation, .saving: true
    case .idle, .copied, .saved, .failed: false
    }
  }

  /// 지금 보이는 그대로 내보낼 수 있다 (진행 중 여부는 보지 않는다). 전체 다시 거르기를 기다리는 동안과 필터 문제가 있을 때는
  /// 보이는 줄이 화면의 필터와 맞지 않아 끈다.
  var canExport: Bool {
    self.isOpen && self.selectedSessionID != nil && !self.visibleLines.isEmpty && !self.isAwaitingFullFilter
      && self.filterProblem == nil
  }
}

/// 내보내기 실패. 화면 문구는 `DeviceLogText.exportFailed(_:)`.
public enum LogExportFailure: Hashable, Sendable {
  case copy(WorkspaceExportError)
  case save(WorkspaceExportError)
  /// 저장한 파일을 Finder 에서 찾지 못했다 (옮겨졌거나 지워짐).
  case revealedFileMissing
}

/// 버튼을 누른 순간의 창·세션 값 (메인에서 잡는다). 글은 이것만으로 메인 밖에서 만든다 (`LogExportText.make`).
/// 배열은 복사하지 않고 공유한다 (5만 줄 대입 0.0ms 측정. 잡은 동안 창에 줄이 더해지면 그때 한 번 복사된다).
struct LogExportSnapshot: Sendable {
  let session: AppLogSessionSummary
  let lines: [VisibleLogLine]
  let visibleCount: Int
  let totalCount: Int
  /// 버퍼가 차서 버린 앞 줄 수 (`DeviceLogWindow.discardedNotice`).
  let discarded: Int?
  /// 이 세션에서 받은 줄을 지운 적이 있다.
  let hasCleared: Bool
  let isPaused: Bool
  let newWhilePaused: Int
  let filter: LogFilter
  let exportedAt: Date
  /// "1.3.0 (45)". 모르면 nil.
  let simLauncherVersion: String?

  /// 창의 지금 값. 세션 요약은 부른 쪽이 고른 세션의 것을 넘긴다.
  init(window: DeviceLogWindow, session: AppLogSessionSummary, exportedAt: Date, simLauncherVersion: String?) {
    self.session = session
    self.lines = window.visibleLines
    self.visibleCount = window.visibleCount
    self.totalCount = window.totalCount
    self.discarded = window.discardedNotice
    self.hasCleared = window.clearedThrough[session.id, default: -1] >= 0
    self.isPaused = window.isPaused
    self.newWhilePaused = window.newWhilePaused
    self.filter = window.filter
    self.exportedAt = exportedAt
    self.simLauncherVersion = simLauncherVersion
  }

  /// 테스트가 값을 직접 정할 때.
  init(
    session: AppLogSessionSummary,
    lines: [VisibleLogLine],
    totalCount: Int,
    discarded: Int? = nil,
    hasCleared: Bool = false,
    isPaused: Bool = false,
    newWhilePaused: Int = 0,
    filter: LogFilter = LogFilter(),
    exportedAt: Date,
    simLauncherVersion: String? = nil
  ) {
    self.session = session
    self.lines = lines
    self.visibleCount = lines.count
    self.totalCount = totalCount
    self.discarded = discarded
    self.hasCleared = hasCleared
    self.isPaused = isPaused
    self.newWhilePaused = newWhilePaused
    self.filter = filter
    self.exportedAt = exportedAt
    self.simLauncherVersion = simLauncherVersion
  }
}
